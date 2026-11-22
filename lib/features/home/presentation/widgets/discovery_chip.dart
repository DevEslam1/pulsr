import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/theme/pulsr_button_style.dart';
import '../../../../core/widgets/pulsr_pressable.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class DiscoveryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  /// A denser variant for pinned actions (e.g. "More tools") where horizontal
  /// space is at a premium on phones. The tap target stays 48 dp.
  final bool compact;

  const DiscoveryChip({
    super.key,
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isCapsule = context.isCapsuleButtons;
    final chipRadius = context.buttonRadius(rectRadius: 6.0);
    return PulsrPressable(
      onTap: onTap,
      pressedScale: 0.97,
      hapticStyle: PulsrHapticStyle.selection,
      focusBorderRadius: isCapsule ? chipRadius : AppRadii.full,
      // 40dp+ touch target styled as a clean borderless tinted pill
      // (surfaceContainerHigh) with comfortable horizontal padding.
      child: Container(
        constraints: const BoxConstraints(minHeight: 40.0),
        padding: EdgeInsets.symmetric(
            horizontal: compact
                ? (isCapsule ? 10.0 : AppSpacing.s10)
                : (isCapsule ? 14.0 : AppSpacing.s12),
            vertical: isCapsule ? 6.0 : AppSpacing.s8),
        decoration: isCapsule
            ? PulsrCapsuleStyle.decoration(p, borderRadius: chipRadius)
            : BoxDecoration(
                color: p.surfaceContainerHigh,
                borderRadius: AppRadii.full,
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: compact ? 14 : 15,
              color: isCapsule
                  ? PulsrCapsuleStyle.foregroundColor(p)
                  : iconColor,
            ),
            SizedBox(width: compact ? AppSpacing.xs : AppSpacing.s8),
            Text(
              label,
              style: TextStyle(
                color: isCapsule
                    ? PulsrCapsuleStyle.foregroundColor(p)
                    : p.textPrimary,
                fontSize: compact
                    ? AppFontSize.caption
                    : (isCapsule ? 12.0 : AppFontSize.label),
                fontWeight: isCapsule ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: isCapsule ? 0.2 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
