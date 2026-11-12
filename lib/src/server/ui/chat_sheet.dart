import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/zehn_integrator.dart' show ZiComponentController;
import '../chat/chat_cubit.dart';
import '../chat/chat_settings.dart';
import '../chat/chat_state.dart';
import '../chat/history.dart';
import '../chat/history_cubit.dart';
import '../surface/form_draft.dart';
import '../surface/form_words.dart';
import '../surface/surface.dart';
import '../surface/surface_view.dart';
import 'chrome.dart';
import 'soap_bubble.dart';
import 'strings.dart';
import 'style.dart';
import 'voice.dart';

/// An in-app component builder (`ZehnIntelligence.registerComponent`).
typedef ZiComponentBuilder = Widget Function(BuildContext context, Map<String, Object?> props, ZiComponentController controller);

/// The assistant, in a bottom sheet, in the zehn/intelligence design:
/// a landing (welcome, the soap-bubble orb, suggestions), listening (halo
/// and waveform), the conversation, and the user's past conversations.
class ZiChatSheet extends StatefulWidget {
  const ZiChatSheet({
    super.key,
    required this.cubit,
    required this.settings,
    required this.language,
    required this.builders,
    this.openRoute,
    this.title,
    this.recorderFactory,
    this.history,
  });

  static const maxRecordingBytes = 1024 * 1024;
  static const _urlSchemes = {'https', 'tel', 'mailto'};

  final ZiChatCubit cubit;

  /// Theme and welcome words from `GET /v1/config`; they can
  /// change while the chat is open.
  final ValueListenable<ZiChatSettings> settings;
  final String Function() language;
  final Map<String, ZiComponentBuilder> builders;
  final FutureOr<void> Function(String route)? openRoute;
  final String? title;

  /// The microphone; the SDK's own recorder when null.
  final ZiVoiceRecorder Function()? recorderFactory;

  /// The user's past conversations; null shows no history button.
  final ZiHistory? history;

  static Future<void> show(
    BuildContext context, {
    required ZiChatCubit cubit,
    required ValueListenable<ZiChatSettings> settings,
    required String Function() language,
    required Map<String, ZiComponentBuilder> builders,
    required FutureOr<void> Function(String route)? openRoute,
    String? title,
    ZiVoiceRecorder Function()? recorderFactory,
    ZiHistory? history,
  }) {
    final style = ZiChatStyle.fromTheme(settings.value.theme);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: style.barrier,
      // Full height: useSafeArea keeps the top below the status bar / notch,
      // and the body keeps clear of the home indicator. The padding lifts the
      // whole sheet, composer included, above the keyboard.
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: SizedBox.expand(
          child: ZiChatSheet(
            cubit: cubit,
            settings: settings,
            language: language,
            builders: builders,
            openRoute: openRoute,
            title: title,
            recorderFactory: recorderFactory,
            history: history,
          ),
        ),
      ),
    );
  }

  @override
  State<ZiChatSheet> createState() => _ZiChatSheetState();
}

enum _View { landing, listening, conversation, history }

class _ZiChatSheetState extends State<ZiChatSheet> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _historyScroll = ScrollController();
  ZiHistoryCubit? _historyCubit;
  bool _showHistory = false;
  StreamSubscription<ZiComponentItem>? _opens;
  StreamSubscription<double>? _levels;
  ZiVoiceRecorder? _recorder;
  bool _typing = false;
  bool _listening = false;
  bool _closing = false;
  double _level = 0;
  DateTime? _startedAt;

  ZiStrings get _words => ZiStrings.of(widget.language());
  ZiChatSettings get _settings => widget.settings.value;
  ZiChatStyle get _style => ZiChatStyle.fromTheme(_settings.theme);

  @override
  void initState() {
    super.initState();
    _opens = widget.cubit.opens.listen(_open);
    widget.settings.addListener(_settingsChanged);
    _text.addListener(() => setState(() {}));
    _historyScroll.addListener(_historyScrolled);
    unawaited(widget.cubit.loadStarterSuggestions());
  }

  @override
  void dispose() {
    unawaited(_opens?.cancel());
    widget.settings.removeListener(_settingsChanged);
    unawaited(_levels?.cancel());
    _text.dispose();
    _scroll.dispose();
    _historyScroll.dispose();
    unawaited(_historyCubit?.close());
    unawaited(_recorder?.dispose());
    // Closing the chat stops spoken replies (MOBILE_INTEGRATION.md, section 4).
    unawaited(widget.cubit.stopAudio());
    super.dispose();
  }

  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  _View _view(ZiChatState state) {
    if (_showHistory) return _View.history;
    if (_listening) return _View.listening;
    if (state.items.isNotEmpty || state.busy || _typing) return _View.conversation;
    return _View.landing;
  }

  // ---- components and actions ----------------------------------------------

  void _open(ZiComponentItem item) {
    if (!mounted) return;
    final builder = widget.builders[item.component];
    if (item.kind == ZiComponentKind.route) {
      final route = item.route;
      if (builder != null) {
        final nav = Navigator.of(context);
        _closeChat();
        unawaited(nav.push(MaterialPageRoute<void>(
          builder: (c) => builder(c, item.data, ZiComponentController(onCompleted: () => Navigator.of(c).maybePop())),
        )));
      } else if (route != null && route.startsWith('/')) {
        _openRoute(route);
      } else {
        debugPrint('zehn_intelligence: no route for component "${item.component}"');
      }
      return;
    }
    if (builder == null && item.surface == null) {
      debugPrint('zehn_intelligence: nothing to draw for sheet "${item.component}"');
      return;
    }
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _style.background,
      builder: (c) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: builder != null
            ? builder(c, item.data, ZiComponentController(onCompleted: () => Navigator.of(c).maybePop()))
            : _surface(item.surface, item.data),
      ),
    ));
  }

  /// Closes the chat and opens [route] as it came: the server already
  /// filled and escaped it.
  void _openRoute(String route) {
    final open = widget.openRoute;
    _closeChat();
    if (open != null) unawaited(Future<void>.value(open(route)));
  }

  /// Closes this chat once, with any component sheet opened above it, and
  /// never a route under it.
  void _closeChat() {
    if (_closing || !mounted) return;
    _closing = true;
    final mine = ModalRoute.of(context);
    if (mine == null || !mine.isActive) return;
    Navigator.of(context)
      ..popUntil((route) => route == mine)
      ..pop();
  }

  void _onAction(ZiSurfaceAction action) {
    switch (action.name) {
      case 'ask':
        final text = action.args['text'];
        if (text is String) _send(text);
      case 'open_route':
        final route = action.args['route'];
        if (route is String && route.startsWith('/')) _openRoute(route);
      case 'open_url':
        final url = Uri.tryParse('${action.args['url'] ?? ''}');
        if (url != null && ZiChatSheet._urlSchemes.contains(url.scheme)) {
          unawaited(launchUrl(url, mode: LaunchMode.externalApplication));
        }
    }
  }

  Widget _component(ZiComponentItem item) {
    final builder = widget.builders[item.component];
    if (builder != null) return builder(context, item.data, const ZiComponentController());
    return _surface(item.surface, item.data);
  }

  /// Each template, parsed once, by the map it came in: its [ZiSurface], or
  /// the [FormatException] it failed with. Every keystroke in the chat's own
  /// input rebuilds the sheet; the cards must not be parsed again for it.
  final _parsed = Expando<Object>('templates');

  Widget _surface(Map<String, Object?>? json, Map<String, Object?> data) {
    if (json == null) return const SizedBox.shrink();
    final parsed = _parsed[json] ??= _parse(json);
    if (parsed is! ZiSurface) return const SizedBox.shrink();
    return ZiSurfaceView(
      surface: parsed,
      data: data,
      theme: ZiTheme(_settings.theme),
      language: widget.language(),
      onAction: _onAction,
    );
  }

  static Object _parse(Map<String, Object?> json) {
    try {
      return ZiSurface.parse(json);
    } on FormatException catch (e) {
      debugPrint('zehn_intelligence: a component template is broken: $e');
      return e;
    }
  }

  /// A card with fields. Its draft, and with it what is typed, belongs to the
  /// chat, so it outlives the card scrolling away and the sheet closing; the
  /// view listens to the draft and redraws only this card as the person
  /// types. Like a result card it has no frame of its own: the template's
  /// root `Box` is the card.
  Widget _formCard(ZiFormItem item, {required bool busy}) {
    final draft = widget.cubit.formDraft(item.formId);
    final language = widget.language();
    final Widget card;
    if (draft == null) {
      card = const SizedBox.shrink();
    } else if (!ziDraws(draft.surface)) {
      // A form that silently lost a field must not be sendable: none of it is drawn.
      final s = _style;
      card = Text(
        ziFormWord('update_app', language),
        key: const ValueKey('zi-form-update'),
        style: s.small.copyWith(color: s.muted),
      );
    } else {
      card = ZiSurfaceView(
        surface: draft.surface,
        data: item.data,
        theme: ZiTheme(_settings.theme),
        language: language,
        onAction: _onAction,
        form: ZiFormScope(
          formId: item.formId,
          draft: draft,
          status: item.status,
          busy: busy,
          onSubmit: () => unawaited(widget.cubit.submitForm(item.formId)),
        ),
      );
    }
    return KeyedSubtree(key: ValueKey('zi-form-${item.formId}'), child: card);
  }

  // ---- input ---------------------------------------------------------------

  void _send(String text) {
    if (text.trim().isEmpty) return;
    _text.clear();
    _startedAt ??= DateTime.now();
    unawaited(widget.cubit.sendText(text));
  }

  void _newChat() {
    widget.cubit.reset();
    _startedAt = null;
    setState(() => _typing = false);
    unawaited(widget.cubit.loadStarterSuggestions());
  }

  // ---- history -------------------------------------------------------------

  void _openHistory() {
    final history = widget.history;
    if (history == null) return;
    unawaited((_historyCubit ??= ZiHistoryCubit(history)).load());
    setState(() => _showHistory = true);
  }

  void _closeHistory() => setState(() => _showHistory = false);

  void _historyScrolled() {
    final position = _historyScroll.position;
    if (position.pixels > position.maxScrollExtent - 200) unawaited(_historyCubit?.loadMore());
  }

  /// Shows a past conversation in the chat, from the time it started.
  Future<void> _resume(ZiConversationSummary summary) async {
    final conversation = await _historyCubit?.open(summary.id);
    if (conversation == null || !mounted) return;
    widget.cubit.resume(conversation);
    setState(() {
      _showHistory = false;
      _typing = false;
      _startedAt = conversation.createdAt.toLocal();
    });
  }

  Future<void> _startListening() async {
    final recorder = _recorder ??= (widget.recorderFactory ?? DefaultVoiceRecorder.new)();
    if (!await recorder.start() || !mounted) return;
    _stopLevels();
    _levels = recorder.levels().listen((level) {
      if (mounted) setState(() => _level = level);
    });
    setState(() => _listening = true);
  }

  /// Not awaited: a level stream's cancel can lag behind the recorder, and
  /// stop/cancel must not wait on it.
  void _stopLevels() {
    unawaited(_levels?.cancel());
    _levels = null;
    _level = 0;
  }

  Future<void> _cancelListening() async {
    _stopLevels();
    setState(() => _listening = false);
    await _recorder?.cancel();
  }

  Future<void> _finishListening() async {
    _stopLevels();
    setState(() => _listening = false);
    final bytes = await _recorder?.stop();
    if (bytes == null || bytes.isEmpty || !mounted) return;
    _startedAt ??= DateTime.now();
    if (bytes.length > ZiChatSheet.maxRecordingBytes) {
      widget.cubit.showError('payload_too_large');
      return;
    }
    await widget.cubit.sendAudio(base64Encode(bytes), 'm4a', voiceReply: true);
  }

  // ---- layout --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = _style;
    final words = _words;
    return BlocProvider.value(
      value: widget.cubit,
      child: BlocConsumer<ZiChatCubit, ZiChatState>(
        // To the end on a new part, when an answer gets its speaker, and when
        // the turn ends (the follow-up chips take room).
        listenWhen: (a, b) =>
            a.items.length != b.items.length ||
            a.items.lastOrNull != b.items.lastOrNull ||
            !identical(a.voiced, b.voiced) ||
            a.busy != b.busy,
        listener: (context, _) => WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }),
        builder: (context, state) {
          final view = _view(state);
          final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: s.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              child: Stack(children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: ZiTopAura.height,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: view == _View.listening ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: const ZiTopAura(),
                    ),
                  ),
                ),
                Column(children: [
                  ZiDragHandle(style: s),
                  _header(view, s, words),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: keyboard ? 0 : MediaQuery.paddingOf(context).bottom),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: KeyedSubtree(
                          key: ValueKey(view),
                          child: switch (view) {
                            _View.landing => _landing(state, s, words),
                            _View.listening => _listeningView(s, words),
                            _View.conversation => _conversation(state, s, words),
                            _View.history => _historyView(s, words),
                          },
                        ),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _header(_View view, ZiChatStyle s, ZiStrings words) {
    if (view == _View.landing) {
      return ZiHeaderBar(
        style: s,
        title: widget.title ?? _settings.assistantName ?? words.title,
        subtitle: words.poweredBy,
        leadingIcon: 'close_line',
        leadingKey: const ValueKey('zi-close'),
        leadingLabel: words.close,
        onLeading: () => Navigator.of(context).maybePop(),
        trailingIcon: widget.history != null ? 'chat_history' : null,
        trailingKey: const ValueKey('zi-history'),
        trailingLabel: words.history,
        onTrailing: _openHistory,
      );
    }
    if (view == _View.history) {
      return ZiHeaderBar(
        style: s,
        title: words.history,
        subtitle: null,
        leadingIcon: 'arrow_left',
        leadingKey: const ValueKey('zi-back'),
        leadingLabel: words.back,
        onLeading: _closeHistory,
      );
    }
    final started = _startedAt;
    return ZiHeaderBar(
      style: s,
      title: words.chat,
      subtitle: view == _View.conversation && started != null ? _stamp(started) : null,
      leadingIcon: 'arrow_left',
      leadingKey: const ValueKey('zi-back'),
      leadingLabel: words.back,
      onLeading: view == _View.listening ? () => unawaited(_cancelListening()) : _newChat,
    );
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}, ${two(t.day)}.${two(t.month)}.${t.year}';
  }

  // ---- landing -------------------------------------------------------------

  Widget _landing(ZiChatState state, ZiChatStyle s, ZiStrings words) {
    final language = widget.language();
    final title = _settings.welcomeTitle(language) ?? words.welcomeTitle;
    final subtitle = _settings.welcomeSubtitle(language) ?? words.welcomeSubtitle;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: s.fill, borderRadius: BorderRadius.circular(20)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ZiIcon('search_ai', size: 32, color: s.ink),
                    const SizedBox(height: 8),
                    Text(title, style: s.bodyMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: s.body.copyWith(color: s.muted)),
                  ]),
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                key: const ValueKey('zi-orb'),
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(_startListening()),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  IgnorePointer(
                    child: SoapBubble(size: 128, backdrop: s.background, child: const ZiIcon('star_chat', size: 56)),
                  ),
                  const SizedBox(height: 12),
                  Text(words.tapToSpeak, style: s.body.copyWith(color: s.muted)),
                ]),
              ),
              const SizedBox(height: 24),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(height: 1, color: s.line),
                ),
                if (state.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 20, right: 16),
                    child: Text(words.tryAsking, style: s.bodyMedium),
                  ),
                  const SizedBox(height: 8),
                  _chips(state.suggestions, s),
                ],
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GestureDetector(
                    onTap: () => setState(() => _typing = true),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 48,
                      width: double.infinity,
                      decoration: BoxDecoration(color: s.fill, borderRadius: BorderRadius.circular(100)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        ZiIcon('keyboard', color: s.ink),
                        const SizedBox(width: 8),
                        Text(words.typeMessage, style: s.bodyMedium),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chips(List<String> suggestions, ZiChatStyle s) => SizedBox(
    height: 36,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: suggestions.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => _send(suggestions[i]),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: s.fill, borderRadius: BorderRadius.circular(100)),
          alignment: Alignment.center,
          child: Text(suggestions[i], style: s.smallMedium),
        ),
      ),
    ),
  );

  // ---- listening -----------------------------------------------------------

  Widget _listeningView(ZiChatStyle s, ZiStrings words) => Column(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            const Positioned(left: -36, top: -36, child: IgnorePointer(child: ZiListeningHalo())),
            SoapBubble(size: 128, backdrop: s.background, drive: _level),
            ZiIcon('mic_chatbot', size: 56, color: s.faint),
          ]),
          const SizedBox(height: 12),
          Text(words.listening, style: s.body.copyWith(color: s.muted)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: ZiWaveformBar(
          style: s,
          level: _level,
          onCancel: () => unawaited(_cancelListening()),
          onStop: () => unawaited(_finishListening()),
          onSend: () => unawaited(_finishListening()),
        ),
      ),
    ],
  );

  // ---- conversation --------------------------------------------------------

  Widget _conversation(ZiChatState state, ZiChatStyle s, ZiStrings words) {
    final last = state.items.lastOrNull;
    // The turn may still be running, but the next move is the person's.
    final waitingForUser = switch (last) {
      ZiConfirmItem(status: ZiConfirmStatus.pending) || ZiFormItem(status: ZiFormStatus.pending) => true,
      _ => false,
    };
    final thinking = state.busy && last is! ZiAssistantItem && !waitingForUser;
    final followUps = !state.busy && state.items.isNotEmpty && state.suggestions.isNotEmpty;
    // Each turn's last part carries the speaker, when its speech is held.
    final lastPart = {
      for (final item in state.items)
        if (item is ZiAssistantItem && state.voiced.contains(item.turnId)) item.turnId: item,
    };
    return Column(children: [
      Expanded(
        child: ListView(
          controller: _scroll,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            for (final item in state.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: item is ZiAssistantItem && identical(lastPart[item.turnId], item)
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _item(item, s, words, busy: state.busy),
                        _speaker(item.turnId, state, s, words),
                      ])
                    : _item(item, s, words, busy: state.busy),
              ),
            if (thinking)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  const ZiIcon('sparkles'),
                  const SizedBox(width: 8),
                  Text(words.thinking, style: s.body),
                ]),
              ),
          ],
        ),
      ),
      if (followUps) ...[const SizedBox(height: 4), _chips(state.suggestions, s), const SizedBox(height: 4)],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: state.readOnly ? _ended(s, words) : _inputBar(state, s, words),
      ),
    ]);
  }

  /// Plays the turn's spoken answer again, from the phone's memory, or
  /// stops it.
  Widget _speaker(String turnId, ZiChatState state, ZiChatStyle s, ZiStrings words) {
    final playing = state.playing == turnId;
    return Semantics(
      button: true,
      label: playing ? words.stopAnswer : words.playAnswer,
      child: GestureDetector(
        key: ValueKey('zi-speak-$turnId'),
        behavior: HitTestBehavior.opaque,
        onTap: state.busy && !playing ? null : () => unawaited(widget.cubit.replay(turnId)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
          child: SizedBox.square(
            dimension: 32,
            child: Icon(
              playing ? Icons.stop_rounded : Icons.volume_up_outlined,
              size: 20,
              color: playing ? s.accent : s.muted,
            ),
          ),
        ),
      ),
    );
  }

  /// In place of the input under a conversation that can't go on.
  Widget _ended(ZiChatStyle s, ZiStrings words) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text(words.chatEnded, style: s.small.copyWith(color: s.muted), textAlign: TextAlign.center),
    const SizedBox(height: 8),
    GestureDetector(
      key: const ValueKey('zi-new-chat'),
      onTap: _newChat,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: s.fill, borderRadius: BorderRadius.circular(100)),
        child: Text(words.newChat, style: s.bodyMedium),
      ),
    ),
  ]);

  // ---- history list --------------------------------------------------------

  Widget _historyView(ZiChatStyle s, ZiStrings words) => BlocBuilder<ZiHistoryCubit, ZiHistoryState>(
    bloc: _historyCubit,
    builder: (context, h) {
      final error = h.error;
      if (error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(words.error(error), style: s.body.copyWith(color: s.muted), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => unawaited(_historyCubit?.load()),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: s.fill, borderRadius: BorderRadius.circular(100)),
                  child: Text(words.retry, style: s.smallMedium),
                ),
              ),
            ]),
          ),
        );
      }
      if (h.items.isEmpty) {
        return Center(
          child: h.loading
              ? CircularProgressIndicator(color: s.accent)
              : Text(words.historyEmpty, style: s.body.copyWith(color: s.muted)),
        );
      }
      final notice = h.notice;
      return Column(children: [
        if (notice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(words.error(notice), style: s.small.copyWith(color: s.danger)),
          ),
        Expanded(
          child: ListView.separated(
            controller: _historyScroll,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: h.items.length + (h.loading ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => i < h.items.length
                ? _historyRow(h.items[i], h, s, words)
                : Center(child: CircularProgressIndicator(color: s.accent)),
          ),
        ),
      ]);
    },
  );

  /// Tap to open, swipe left to delete.
  Widget _historyRow(ZiConversationSummary c, ZiHistoryState h, ZiChatStyle s, ZiStrings words) => Dismissible(
    key: ValueKey('zi-history-${c.id}'),
    direction: DismissDirection.endToStart,
    confirmDismiss: (_) async => await _historyCubit?.delete(c.id) ?? false,
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: s.danger, borderRadius: BorderRadius.circular(20)),
      child: Text(words.delete, style: s.smallMedium.copyWith(color: s.onAccent)),
    ),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: h.opening == null ? () => unawaited(_resume(c)) : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: s.fill, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.title.isEmpty ? words.chat : c.title, style: s.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(_stamp(c.lastTurnAt.toLocal()), style: s.small.copyWith(color: s.muted)),
            ]),
          ),
          if (h.opening == c.id) ...[
            const SizedBox(width: 12),
            SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: s.accent)),
          ],
        ]),
      ),
    ),
  );

  Widget _item(ZiChatItem item, ZiChatStyle s, ZiStrings words, {required bool busy}) => switch (item) {
    ZiUserItem() => Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: s.fill, borderRadius: BorderRadius.circular(20)),
        child: Text(item.text.isEmpty ? '…' : item.text, style: s.body),
      ),
    ),
    ZiAssistantItem() => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.line),
      ),
      child: MarkdownBody(
        data: item.text,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: s.body,
          listBullet: s.body,
          a: s.body.copyWith(color: s.accent),
        ),
      ),
    ),
    ZiComponentItem() => _component(item),
    ZiConfirmItem() => _confirmCard(item, s, words, busy: busy),
    ZiFormItem() => _formCard(item, busy: busy),
    ZiErrorItem() => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.line),
      ),
      child: Row(children: [
        Expanded(child: Text(words.error(item.code, wait: item.retryAfter), style: s.body.copyWith(color: s.danger))),
        if (item.retryable)
          GestureDetector(
            onTap: () => unawaited(widget.cubit.retry()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: s.fill, borderRadius: BorderRadius.circular(100)),
              child: Text(words.retry, style: s.smallMedium),
            ),
          ),
      ]),
    ),
  };

  /// A data-changing call: one card with the server's template and, under
  /// it, Cancel and Confirm. One tap answers it; nothing reaches the app's
  /// API before Confirm. The card's colours and radius are the theme's.
  Widget _confirmCard(ZiConfirmItem item, ZiChatStyle s, ZiStrings words, {required bool busy}) {
    final t = ZiTheme(_settings.theme);
    final pending = item.status == ZiConfirmStatus.pending;
    final onSurface = t.color('on_surface', s.ink);
    final strong = item.method == 'DELETE' ? s.danger : t.color('accent', s.accent);
    Widget button(String text, Key key, {required bool confirm}) => Expanded(
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : () => unawaited(widget.cubit.decide(item.actionId, confirm: confirm)),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: confirm ? strong : t.color('chip', s.fill),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            text,
            style: s.smallMedium.copyWith(color: confirm ? t.color('on_accent', s.onAccent) : onSurface),
          ),
        ),
      ),
    );
    return Container(
      key: const ValueKey('zi-confirm-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.color('surface', s.background),
        borderRadius: BorderRadius.circular(t.radius('card', 20)),
        border: Border.all(color: t.color('border', s.line)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (item.surface != null)
          _surface(item.surface, item.data)
        else
          Text(words.confirmDefault, style: s.bodyMedium.copyWith(color: onSurface)),
        const SizedBox(height: 16),
        if (pending)
          Row(children: [
            button(words.decline, const ValueKey('zi-decline'), confirm: false),
            const SizedBox(width: 8),
            button(item.label ?? words.confirm, const ValueKey('zi-confirm'), confirm: true),
          ])
        else
          Text(
            switch (item.status) {
              ZiConfirmStatus.confirmed => words.confirmed,
              ZiConfirmStatus.cancelled => words.cancelled,
              _ => words.expired,
            },
            style: s.small.copyWith(color: t.color('muted', s.muted)),
          ),
      ]),
    );
  }

  Widget _inputBar(ZiChatState state, ZiChatStyle s, ZiStrings words) {
    final hasText = _text.text.trim().isNotEmpty;
    final Widget action;
    if (hasText) {
      action = ZiCircleButton(
        key: const ValueKey('zi-send'),
        icon: 'arrow_up',
        onTap: state.busy || !hasText ? null : () => _send(_text.text),
        background: hasText && !state.busy ? s.accent : s.accent.withValues(alpha: 0.4),
        iconColor: s.onAccent,
        tooltip: words.send,
      );
    } else {
      action = ZiCircleButton(
        key: const ValueKey('zi-mic'),
        icon: 'mic_chatbot',
        onTap: state.busy ? null : () => unawaited(_startListening()),
        background: s.line,
        iconColor: s.muted,
        tooltip: words.holdToSpeak,
      );
    }
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _text,
          autofocus: _typing && state.items.isEmpty,
          minLines: 1,
          maxLines: 4,
          maxLength: ZiChatCubit.maxTextLength,
          textInputAction: TextInputAction.send,
          onSubmitted: _send,
          style: s.small,
          cursorColor: s.accent,
          decoration: InputDecoration(
            hintText: words.typeMessage,
            hintStyle: s.small.copyWith(color: s.muted),
            counterText: '',
            filled: true,
            fillColor: s.fill,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      ),
      const SizedBox(width: 8),
      action,
    ]);
  }
}
