import 'package:flutter/material.dart';

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
      focusBorderRadius: isCapsule ? chipRadius : AppRadii.r14All,
      // 48dp tap target around a lighter 36dp visual pill: the row does not
      // need nine heavy 48dp capsules competing with the hero card.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: compact
                  ? (isCapsule ? 8.5 : AppSpacing.s8)
                  : (isCapsule ? 11.0 : AppSpacing.s10),
              vertical: isCapsule ? 4.5 : AppSpacing.xs),
          decoration: isCapsule
              ? PulsrCapsuleStyle.decoration(p, borderRadius: chipRadius)
              : BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: AppRadii.r14All,
                  border: Border.all(color: p.hairline),
                ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: compact ? 13 : 14,
                color: isCapsule
                    ? PulsrCapsuleStyle.foregroundColor(p)
                    : iconColor,
              ),
              SizedBox(width: compact ? AppSpacing.xxs : AppSpacing.s6),
              Text(
                label,
                style: TextStyle(
                  color: isCapsule
                      ? PulsrCapsuleStyle.foregroundColor(p)
                      : p.textPrimary,
                  fontSize: compact
                      ? AppFontSize.caption
                      : (isCapsule ? 11.5 : AppFontSize.label),
                  fontWeight: isCapsule ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: isCapsule ? 0.2 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
