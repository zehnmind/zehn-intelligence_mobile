import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/model/agent_message.dart';
import '../chat/agent_chat_bloc.dart';
import '../components/agent_component_registry.dart';
import '../scope/agent_scope.dart';
import '../speech/agent_speech_output.dart';
import 'agent_confirm_card.dart';
import 'agent_fallback_text.dart';

/// The conversation.
///
/// Every assistant turn is badged so the user can always tell app UI from
/// assistant UI — the components below the badge were chosen by a model, and
/// that should never be ambiguous.
class AgentMessageList extends StatefulWidget {
  const AgentMessageList({
    super.key,
    required this.messages,
    this.taps,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final List<AgentMessage> messages;

  /// What taps do. Defaults to the scope's standard behaviour.
  final AgentTapResolver? taps;
  final EdgeInsetsGeometry padding;

  @override
  State<AgentMessageList> createState() => _AgentMessageListState();
}

class _AgentMessageListState extends State<AgentMessageList> {
  final ScrollController _controller = ScrollController();

  /// The newest message was in view when the list last moved.
  bool _atEnd = true;

  /// The list's height at the last metrics change.
  double? _viewport;

  /// One key per message, to find a turn on screen.
  final Map<String, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    // A conversation reopened is shown at its newest message, as every chat
    // is.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  void didUpdateWidget(AgentMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final messages = widget.messages;
    final previous = oldWidget.messages;
    if (messages.length != previous.length) {
      _scrollToEnd();
    } else if (messages.isNotEmpty &&
        messages.last.status != previous.last.status) {
      _revealStartOf(messages.last);
    }
  }

  /// A turn that just finished can be much taller than the "thinking" row it
  /// replaced, which was at the very bottom. Scroll its start into view: a
  /// short answer ends up shown whole, a long one from its first line.
  void _revealStartOf(AgentMessage message) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      var context = _keys[message.id]?.currentContext;
      if (context == null && _controller.hasClients) {
        // Not laid out yet — far below the fold. Bring the end into view
        // first, so there is something to reveal.
        _controller.jumpTo(_controller.position.maxScrollExtent);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        context = _keys[message.id]?.currentContext;
      }
      if (context == null || !context.mounted) return;
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Scrolls to the newest message. The list's full height is only an
  /// estimate until the rows near the end are laid out, so it keeps going
  /// until it really is at the end.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (var i = 0; i < 4; i++) {
        if (!mounted || !_controller.hasClients) return;
        final position = _controller.position;
        if (position.pixels >= position.maxScrollExtent - 0.5) return;
        await _controller.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _onScroll(ScrollNotification notification) {
    // Depth 0 only: a card's own horizontal list scrolls inside this one.
    if (notification.depth == 0) {
      final metrics = notification.metrics;
      _atEnd = metrics.pixels >= metrics.maxScrollExtent - 24;
    }
    return false;
  }

  /// The keyboard opening shrinks the list from below. Left alone, the
  /// newest message — usually the one being answered — would slide out of
  /// view.
  bool _onMetricsChanged(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    final previous = _viewport;
    _viewport = metrics.viewportDimension;

    final shrank = previous != null && metrics.viewportDimension < previous;
    if (shrank && _atEnd && _controller.hasClients) {
      _controller.jumpTo(metrics.maxScrollExtent);
    }
    return false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AgentScope.of(context);
    final taps = widget.taps ?? scope.taps;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetricsChanged,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ListView.separated(
          controller: _controller,
          padding: widget.padding,
          itemCount: widget.messages.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final message = widget.messages[index];
            return KeyedSubtree(
              key: _keys.putIfAbsent(message.id, GlobalKey.new),
              child: message.isUser
                  ? _UserBubble(text: message.text)
                  : _AssistantTurn(message: message, scope: scope, taps: taps),
            );
          },
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = AgentScope.themeOf(context);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.userBubble,
            borderRadius: BorderRadius.circular(theme.radius),
          ),
          child: Text(
            text,
            style: theme.body.copyWith(color: theme.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _AssistantTurn extends StatelessWidget {
  const _AssistantTurn({
    required this.message,
    required this.scope,
    required this.taps,
  });

  final AgentMessage message;
  final AgentScope scope;
  final AgentTapResolver taps;

  @override
  Widget build(BuildContext context) {
    final speech = scope.speech;
    final canSpeak =
        speech != null &&
        speech.isAvailable &&
        message.status == AgentMessageStatus.complete;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: AgentAssistantBadge()),
            if (canSpeak)
              _SpeakButton(
                message: message,
                speech: speech,
                fallbackLanguage: scope.agent.session.languageCode,
              ),
          ],
        ),
        const SizedBox(height: 6),
        ..._body(context),
      ],
    );
  }

  List<Widget> _body(BuildContext context) {
    final strings = AgentScope.stringsOf(context);
    switch (message.status) {
      case AgentMessageStatus.thinking:
        return const [_ThinkingRow()];

      case AgentMessageStatus.failed:
        return [AgentFallbackText(strings.actionFailed)];

      case AgentMessageStatus.cancelled:
        return [AgentFallbackText(strings.confirmCancelled)];

      case AgentMessageStatus.awaitingConfirmation:
        final confirmation = message.pendingConfirmation;
        if (confirmation == null) return const [];
        return [
          AgentConfirmCard(
            confirmation: confirmation,
            onConfirm: () => _confirm(context),
            onCancel: () => context.read<AgentChatBloc>().add(
              AgentConfirmationDeclined(message.id),
            ),
          ),
        ];

      case AgentMessageStatus.complete:
        if (message.components.isEmpty) {
          return [AgentFallbackText(strings.actionFailed)];
        }
        // The app's language, as the rest of the screen: cards are app UI.
        final language = scope.agent.session.languageCode;
        return [
          for (var i = 0; i < message.components.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            scope.agent.components.build(
              context,
              message.components[i],
              taps: taps,
              languageCode: language,
            ),
          ],
        ];
    }
  }

  /// Confirms, after asking the host to verify the user again when the card
  /// requires it. Not verified, nothing runs and the card stays.
  Future<void> _confirm(BuildContext context) async {
    final bloc = context.read<AgentChatBloc>();
    final confirmation = message.pendingConfirmation;
    if (confirmation == null) return;

    var verified = false;
    if (confirmation.requiresStepUp) {
      final stepUp = scope.stepUp;
      verified =
          stepUp != null && await stepUp(context, confirmation.stepUpReason!);
      if (!verified) {
        if (context.mounted) {
          scope.notice(context, AgentScope.stringsOf(context).stepUpFailed);
        }
        return;
      }
    }
    bloc.add(AgentConfirmationAccepted(message.id, verified: verified));
  }
}

/// Marks everything below it as assistant-generated rather than app UI.
class AgentAssistantBadge extends StatelessWidget {
  const AgentAssistantBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AgentScope.themeOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 16, height: 16, child: theme.badge),
        const SizedBox(width: 6),
        Text(
          AgentScope.stringsOf(context).assistantLabel,
          style: theme.captionStrong.copyWith(color: theme.accent),
        ),
      ],
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow();

  @override
  Widget build(BuildContext context) {
    final theme = AgentScope.themeOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: theme.accent),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            AgentScope.stringsOf(context).thinking,
            style: theme.body.copyWith(color: theme.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Plays a reply aloud, or stops it if it is the one playing.
class _SpeakButton extends StatelessWidget {
  const _SpeakButton({
    required this.message,
    required this.speech,
    required this.fallbackLanguage,
  });

  final AgentMessage message;
  final AgentSpeechOutput speech;
  final String fallbackLanguage;

  @override
  Widget build(BuildContext context) {
    final theme = AgentScope.themeOf(context);
    return ValueListenableBuilder<String?>(
      valueListenable: speech.speaking,
      builder: (context, speakingId, _) {
        final isThis = speakingId == message.id;
        return IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: theme.textSecondary,
          icon: Icon(
            isThis ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
          ),
          onPressed: () => isThis
              ? speech.stop()
              : speech.speak(
                  message.id,
                  message.speechText,
                  message.language ?? fallbackLanguage,
                ),
        );
      },
    );
  }
}
