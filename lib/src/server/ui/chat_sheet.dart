import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/zehn_integrator.dart' show ZiComponentController;
import '../../voice/voice_recorder.dart';
import '../bootstrap/bootstrap.dart';
import '../bootstrap/bootstrap_repository.dart';
import '../chat/chat_cubit.dart';
import '../chat/chat_state.dart';
import '../surface/surface.dart';
import '../surface/surface_view.dart';
import 'strings.dart';

/// An in-app component builder (`ZehnIntelligence.registerComponent`).
typedef ZiComponentBuilder = Widget Function(BuildContext context, Map<String, Object?> props, ZiComponentController controller);

/// The chat, in a bottom sheet: messages, console-made cards, chips, and a
/// composer with hold-to-speak when the app has speech.
class ZiChatSheet extends StatefulWidget {
  const ZiChatSheet({
    super.key,
    required this.cubit,
    required this.bootstrap,
    required this.language,
    required this.builders,
    this.openRoute,
    this.title,
  });

  static const maxRecordingBytes = 1024 * 1024;
  static const _urlSchemes = {'https', 'tel', 'mailto'};

  final ZiChatCubit cubit;
  final ZiBootstrapRepository bootstrap;
  final String Function() language;
  final Map<String, ZiComponentBuilder> builders;
  final FutureOr<void> Function(String route)? openRoute;
  final String? title;

  static Future<void> show(
    BuildContext context, {
    required ZiChatCubit cubit,
    required ZiBootstrapRepository bootstrap,
    required String Function() language,
    required Map<String, ZiComponentBuilder> builders,
    required FutureOr<void> Function(String route)? openRoute,
    String? title,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: ZiChatSheet(
        cubit: cubit,
        bootstrap: bootstrap,
        language: language,
        builders: builders,
        openRoute: openRoute,
        title: title,
      ),
    ),
  );

  @override
  State<ZiChatSheet> createState() => _ZiChatSheetState();
}

class _ZiChatSheetState extends State<ZiChatSheet> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final Set<String> _refreshed = {};
  StreamSubscription<ZiComponentItem>? _opens;
  AgentVoiceRecorder? _recorder;
  bool _recording = false;

  ZiStrings get _words => ZiStrings.of(widget.language());
  ZiBootstrap? get _boot => widget.bootstrap.current;

  @override
  void initState() {
    super.initState();
    _opens = widget.cubit.opens.listen(_open);
    unawaited(widget.cubit.loadStarterSuggestions());
  }

  @override
  void dispose() {
    unawaited(_opens?.cancel());
    _text.dispose();
    _scroll.dispose();
    unawaited(_recorder?.dispose());
    super.dispose();
  }

  // ---- components and actions ----------------------------------------------

  void _open(ZiComponentItem item) {
    if (!mounted) return;
    final builder = widget.builders[item.component];
    final def = _boot?.components[item.component];
    if (item.kind == ZiComponentKind.route) {
      if (builder != null) {
        final nav = Navigator.of(context)..pop();
        unawaited(nav.push(MaterialPageRoute<void>(
          builder: (c) => builder(c, item.data, ZiComponentController(onCompleted: () => Navigator.of(c).maybePop())),
        )));
      } else if (def?.route != null) {
        _openRoute(def!.route!, item.data);
      } else {
        debugPrint('zehn_intelligence: no route for component "${item.component}"');
      }
      return;
    }
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: builder != null
            ? builder(c, item.data, ZiComponentController(onCompleted: () => Navigator.of(c).maybePop()))
            : _surface(def?.surface, item.data),
      ),
    ));
  }

  void _openRoute(String template, Map<String, Object?> data) {
    final route = template.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (m) => Uri.encodeComponent('${data[m[1]] ?? ''}'),
    );
    final open = widget.openRoute;
    Navigator.of(context).pop();
    if (open != null) unawaited(Future<void>.value(open(route)));
  }

  void _onAction(ZiSurfaceAction action) {
    switch (action.name) {
      case 'ask':
        final text = action.args['text'];
        if (text is String) unawaited(widget.cubit.sendText(text));
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
    final surface = _boot?.components[item.component]?.surface;
    if (surface == null) {
      // Published after this copy of the start-up data: fetch once, redraw.
      if (_refreshed.add(item.component)) {
        unawaited(widget.bootstrap.refresh().then((_) {
          if (mounted) setState(() {});
        }));
      }
      return const SizedBox.shrink();
    }
    return _surface(surface, item.data);
  }

  Widget _surface(Map<String, Object?>? json, Map<String, Object?> data) {
    if (json == null) return const SizedBox.shrink();
    try {
      return ZiSurfaceView(
        surface: ZiSurface.parse(json),
        data: data,
        theme: ZiTheme(_boot?.theme ?? const {}),
        language: widget.language(),
        onAction: _onAction,
      );
    } on FormatException catch (e) {
      debugPrint('zehn_intelligence: a component template is broken: $e');
      return const SizedBox.shrink();
    }
  }

  // ---- composer ------------------------------------------------------------

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    _text.clear();
    unawaited(widget.cubit.sendText(text));
  }

  Future<void> _startRecording() async {
    final recorder = _recorder ??= AgentVoiceRecorder(aac: true);
    if (await recorder.start() && mounted) setState(() => _recording = true);
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    setState(() => _recording = false);
    final path = await _recorder?.stop();
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    await AgentVoiceRecorder.discard(path);
    if (bytes.isEmpty) return;
    if (bytes.length > ZiChatSheet.maxRecordingBytes) {
      widget.cubit.showError('payload_too_large');
      return;
    }
    await widget.cubit.sendAudio(
      base64Encode(bytes),
      AgentVoiceRecorder.extensionFor(aac: true),
      voiceReply: _boot?.services.contains('tts') ?? false,
    );
  }

  // ---- layout --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final words = _words;
    final colors = Theme.of(context).colorScheme;
    return BlocProvider.value(
      value: widget.cubit,
      child: BlocConsumer<ZiChatCubit, ZiChatState>(
        listenWhen: (a, b) => a.items.length != b.items.length || a.items.lastOrNull != b.items.lastOrNull,
        listener: (context, _) => WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }),
        builder: (context, state) {
          final typing = state.busy && state.items.lastOrNull is! ZiAssistantItem;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(children: [
                Expanded(child: Text(widget.title ?? words.title, style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  tooltip: words.newChat,
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: state.busy
                      ? null
                      : () {
                          widget.cubit.reset();
                          unawaited(widget.cubit.loadStarterSuggestions());
                        },
                ),
                IconButton(
                  tooltip: words.close,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  for (final item in state.items) _item(item, words, colors),
                  if (typing) _bubble(const Text('…'), mine: false, colors: colors),
                ],
              ),
            ),
            if (!state.busy && state.suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final s in state.suggestions)
                    ActionChip(label: Text(s), onPressed: () => unawaited(widget.cubit.sendText(s))),
                ]),
              ),
            _composer(state, words, colors),
          ]);
        },
      ),
    );
  }

  Widget _item(ZiChatItem item, ZiStrings words, ColorScheme colors) => switch (item) {
    ZiUserItem() => _bubble(
      Text(item.text.isEmpty ? '…' : item.text, style: TextStyle(color: colors.onPrimary)),
      mine: true,
      colors: colors,
    ),
    ZiAssistantItem() => _bubble(
      MarkdownBody(data: item.text, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))),
      mine: false,
      colors: colors,
    ),
    ZiComponentItem() => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: _component(item)),
    ZiErrorItem() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(Icons.error_outline, color: colors.error, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(words.error(item.code), style: TextStyle(color: colors.error))),
        if (item.retryable) TextButton(onPressed: () => unawaited(widget.cubit.retry()), child: Text(words.retry)),
      ]),
    ),
  };

  Widget _bubble(Widget child, {required bool mine, required ColorScheme colors}) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: mine ? colors.primary : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    ),
  );

  Widget _composer(ZiChatState state, ZiStrings words, ColorScheme colors) {
    final speech = _boot?.services.contains('stt') ?? false;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(children: [
          if (speech)
            GestureDetector(
              onLongPressStart: state.busy ? null : (_) => unawaited(_startRecording()),
              onLongPressEnd: (_) => unawaited(_stopRecording()),
              child: Tooltip(
                message: words.holdToSpeak,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.mic_rounded, color: _recording ? colors.error : colors.primary),
                ),
              ),
            ),
          Expanded(
            child: _recording
                ? Text(words.listening, style: TextStyle(color: colors.error))
                : TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: ZiChatCubit.maxTextLength,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: words.placeholder,
                      counterText: '',
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                      isDense: true,
                    ),
                  ),
          ),
          IconButton(
            tooltip: words.send,
            icon: const Icon(Icons.send_rounded),
            onPressed: state.busy ? null : _send,
          ),
        ]),
      ),
    );
  }
}
