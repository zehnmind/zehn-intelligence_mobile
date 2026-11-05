import '../tools/tool_result.dart';

/// One detail line on a confirmation card.
class ConfirmationDetail {
  const ConfirmationDetail(this.label, this.value);

  final String label;
  final String value;
}

/// A write that has passed validation but will not run until the user says
/// so.
///
/// Written by the app from its own data, never by the model: if the model
/// could author the card, it could describe a cancellation as something
/// harmless and the user would be confirming a sentence the model chose.
///
/// The [args] are captured here, not re-supplied by the model at confirm
/// time, so what the user sees is exactly what executes.
class PendingConfirmation {
  const PendingConfirmation({
    required this.tool,
    required this.args,
    required this.title,
    required this.body,
    this.details = const [],
    this.warning,
    this.confirmLabel,
    this.declineLabel,
    this.destructive = true,
    this.stepUpReason,
  });

  /// The tool that runs on confirm.
  final String tool;
  final Map<String, Object?> args;
  final String title;
  final String body;
  final List<ConfirmationDetail> details;

  /// Extra line shown in the error colour, e.g. that a refund is forfeited.
  final String? warning;

  /// What the confirm button says — "Reserve" rather than a bare "Confirm",
  /// so the button names what it does. Null uses the generic label.
  final String? confirmLabel;

  /// What the dismiss button says. Null uses the generic "Cancel" — which is
  /// wrong on a card about cancelling something.
  final String? declineLabel;

  /// Styles the card as a warning. True for undoing something (a
  /// cancellation); false for making something (a booking), which is not a
  /// loss and should not look like one.
  final bool destructive;

  /// When set, tapping confirm first asks the host to verify the user again
  /// — a fingerprint, a PIN — with this reason. Refused or cancelled, the
  /// write does not run.
  final String? stepUpReason;

  bool get requiresStepUp => stepUpReason != null;
}

/// What a write's confirmation step decided.
sealed class ConfirmStep {
  const ConfirmStep();
}

/// Show [confirmation] and wait for the user.
final class AskToConfirm extends ConfirmStep {
  const AskToConfirm(this.confirmation);

  final PendingConfirmation confirmation;
}

/// It cannot be done — say why now, rather than after the user has already
/// tapped confirm. [result] is rendered like any other tool result.
final class RefuseWith extends ConfirmStep {
  const RefuseWith(this.result);

  final ToolResult result;
}
