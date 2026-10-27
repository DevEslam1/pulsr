import 'package:flutter/material.dart';

import '../../../../core/theme/aura_theme.dart';
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
    return PulsrPressable(
      onTap: onTap,
      pressedScale: 0.97,
      hapticStyle: PulsrHapticStyle.selection,
      focusBorderRadius: AppRadii.r14All,
      // 48dp tap target around a lighter 36dp visual pill: the row does not
      // need nine heavy 48dp capsules competing with the hero card.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.s8 : AppSpacing.s10,
              vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: AppRadii.r14All,
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 14 : 15, color: iconColor),
              SizedBox(width: compact ? AppSpacing.xxs : AppSpacing.s6),
              Text(
                label,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: compact ? AppFontSize.caption : AppFontSize.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
