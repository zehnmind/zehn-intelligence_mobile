import 'package:flutter/widgets.dart';

import '../../core/model/confirmation.dart';
import '../scope/agent_scope.dart';
import '../theme/agent_theme.dart';

/// The gate in front of a write.
///
/// The arguments shown here are the ones captured when the write was
/// validated, not values re-supplied at tap time, so what the user reads is
/// exactly what will run. Until confirm is tapped, nothing has happened.
class AgentConfirmCard extends StatelessWidget {
  const AgentConfirmCard({
    super.key,
    required this.confirmation,
    required this.onConfirm,
    required this.onCancel,
    this.isBusy = false,
  });

  final PendingConfirmation confirmation;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = AgentScope.themeOf(context);
    final strings = AgentScope.stringsOf(context);
    final destructive = confirmation.destructive;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.radius),
        border: Border.all(
          color: destructive ? theme.dangerBorder : theme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            confirmation.title,
            style: theme.bodyStrong.copyWith(color: theme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            confirmation.body,
            style: theme.small.copyWith(color: theme.textSecondary),
          ),
          if (confirmation.details.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final detail in confirmation.details)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        detail.label,
                        style: theme.small.copyWith(color: theme.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        detail.value,
                        textAlign: TextAlign.end,
                        style: theme.smallStrong.copyWith(
                          color: theme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (confirmation.warning != null) ...[
            const SizedBox(height: 8),
            Text(
              confirmation.warning!,
              style: theme.caption.copyWith(color: theme.danger),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: theme.button(
                  context,
                  AgentButtonSpec(
                    label: confirmation.declineLabel ?? strings.cancel,
                    kind: AgentButtonKind.secondary,
                    onTap: isBusy ? null : onCancel,
                    busy: isBusy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: theme.button(
                  context,
                  AgentButtonSpec(
                    label: confirmation.confirmLabel ?? strings.confirm,
                    kind: destructive
                        ? AgentButtonKind.danger
                        : AgentButtonKind.primary,
                    onTap: isBusy ? null : onConfirm,
                    busy: isBusy,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
