// lib/features/settings/presentation/widgets/settings_conflict_card.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';

/// Explains why a setting is currently blocked by a conflict and, when the
/// conflicting state can be changed programmatically, offers a one-tap
/// resolution action. When [resolveLabel]/[onResolve] are null (e.g. the
/// blocker is hardware or OS level) the card degrades to explanatory text.
class SettingsConflictCard extends StatelessWidget {
  final String reason;
  final String? resolveLabel;
  final VoidCallback? onResolve;

  const SettingsConflictCard({
    super.key,
    required this.reason,
    this.resolveLabel,
    this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canResolve = resolveLabel != null && onResolve != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.block_rounded, color: p.error, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(reason,
                    style: TextStyle(
                        color: p.error,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (canResolve) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: FilledButton.tonalIcon(
                onPressed: onResolve,
                icon: Icon(Icons.auto_fix_high_rounded, size: 14),
                label: Text(resolveLabel!,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor: p.error.withValues(alpha: 0.18),
                  foregroundColor: p.error,
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
