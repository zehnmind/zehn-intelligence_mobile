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
/// and waveform) and the conversation.
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
  });

  static const maxRecordingBytes = 1024 * 1024;
  static const _urlSchemes = {'https', 'tel', 'mailto'};

  final ZiChatCubit cubit;

  /// Theme, services and welcome words; they change when the starter
  /// suggestions bring new ones.
  final ValueListenable<ZiChatSettings> settings;
  final String Function() language;
  final Map<String, ZiComponentBuilder> builders;
  final FutureOr<void> Function(String route)? openRoute;
  final String? title;

  /// The microphone; the SDK's own recorder when null.
  final ZiVoiceRecorder Function()? recorderFactory;

  static Future<void> show(
    BuildContext context, {
    required ZiChatCubit cubit,
    required ValueListenable<ZiChatSettings> settings,
    required String Function() language,
    required Map<String, ZiComponentBuilder> builders,
    required FutureOr<void> Function(String route)? openRoute,
    String? title,
    ZiVoiceRecorder Function()? recorderFactory,
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
          ),
        ),
      ),
    );
  }

  @override
  State<ZiChatSheet> createState() => _ZiChatSheetState();
}

enum _View { landing, listening, conversation }

class _ZiChatSheetState extends State<ZiChatSheet> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
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
  bool get _speech => _settings.speech;

  @override
  void initState() {
    super.initState();
    _opens = widget.cubit.opens.listen(_open);
    widget.settings.addListener(_settingsChanged);
    _text.addListener(() => setState(() {}));
    unawaited(widget.cubit.loadStarterSuggestions());
  }

  @override
  void dispose() {
    unawaited(_opens?.cancel());
    widget.settings.removeListener(_settingsChanged);
    unawaited(_levels?.cancel());
    _text.dispose();
    _scroll.dispose();
    unawaited(_recorder?.dispose());
    // Closing the chat stops spoken replies (MOBILE_INTEGRATION.md, section 4).
    unawaited(widget.cubit.stopAudio());
    super.dispose();
  }

  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  _View _view(ZiChatState state) {
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
        _openRoute(route, item.data);
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

  void _openRoute(String template, Map<String, Object?> data) {
    final route = template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => Uri.encodeComponent('${data[m[1]] ?? ''}'));
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
        if (route is String && route.startsWith('/')) _openRoute(route, const {});
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

  Widget _surface(Map<String, Object?>? json, Map<String, Object?> data) {
    if (json == null) return const SizedBox.shrink();
    try {
      return ZiSurfaceView(
        surface: ZiSurface.parse(json),
        data: data,
        theme: ZiTheme(_settings.theme),
        language: widget.language(),
        onAction: _onAction,
      );
    } on FormatException catch (e) {
      debugPrint('zehn_intelligence: a component template is broken: $e');
      return const SizedBox.shrink();
    }
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

  Future<void> _startListening() async {
    if (!_speech) {
      setState(() => _typing = true);
      return;
    }
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
    await widget.cubit.sendAudio(base64Encode(bytes), 'm4a', voiceReply: _settings.voiceReply);
  }

  // ---- layout --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = _style;
    final words = _words;
    return BlocProvider.value(
      value: widget.cubit,
      child: BlocConsumer<ZiChatCubit, ZiChatState>(
        listenWhen: (a, b) => a.items.length != b.items.length || a.items.lastOrNull != b.items.lastOrNull,
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
        title: widget.title ?? words.title,
        subtitle: words.poweredBy,
        leadingIcon: 'close_line',
        leadingKey: const ValueKey('zi-close'),
        leadingLabel: words.close,
        onLeading: () => Navigator.of(context).maybePop(),
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
    final title = _settings.welcomeTitle ?? words.welcomeTitle;
    final subtitle = _settings.welcomeSubtitle ?? words.welcomeSubtitle;
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
                  if (_speech) ...[
                    const SizedBox(height: 12),
                    Text(words.tapToSpeak, style: s.body.copyWith(color: s.muted)),
                  ],
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
    final waitingForUser = last is ZiConfirmItem && last.status == ZiConfirmStatus.pending;
    final thinking = state.busy && last is! ZiAssistantItem && !waitingForUser;
    final followUps = !state.busy && state.items.isNotEmpty && state.suggestions.isNotEmpty;
    return Column(children: [
      Expanded(
        child: ListView(
          controller: _scroll,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            for (final item in state.items)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: _item(item, s, words)),
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
        child: _inputBar(state, s, words),
      ),
    ]);
  }

  Widget _item(ZiChatItem item, ZiChatStyle s, ZiStrings words) => switch (item) {
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
    ZiConfirmItem() => _confirmCard(item, s, words),
    ZiErrorItem() => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.line),
      ),
      child: Row(children: [
        Expanded(child: Text(words.error(item.code), style: s.body.copyWith(color: s.danger))),
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

  /// A data-changing call: the user allows or cancels it here.
  Widget _confirmCard(ZiConfirmItem item, ZiChatStyle s, ZiStrings words) {
    final pending = item.status == ZiConfirmStatus.pending;
    Widget button(String text, Key key, {required bool allow}) => Expanded(
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.cubit.answerConfirmation(item.callId, allow: allow),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: allow ? s.accent : s.fill, borderRadius: BorderRadius.circular(100)),
          child: Text(text, style: s.smallMedium.copyWith(color: allow ? s.onAccent : s.ink)),
        ),
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pending ? s.accent : s.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.title ?? words.confirmDefault, style: s.bodyMedium),
        const SizedBox(height: 12),
        if (pending)
          Row(children: [
            button(words.decline, const ValueKey('zi-decline'), allow: false),
            const SizedBox(width: 8),
            button(words.allow, const ValueKey('zi-allow'), allow: true),
          ])
        else
          Text(
            switch (item.status) {
              ZiConfirmStatus.allowed => words.allowed,
              ZiConfirmStatus.declined => words.declined,
              _ => words.expired,
            },
            style: s.small.copyWith(color: s.muted),
          ),
      ]),
    );
  }

  Widget _inputBar(ZiChatState state, ZiChatStyle s, ZiStrings words) {
    final hasText = _text.text.trim().isNotEmpty;
    final Widget action;
    if (hasText || !_speech) {
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
