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

  const DiscoveryChip({
    super.key,
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
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
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s10, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: AppRadii.r14All,
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: AppSpacing.s6),
              Text(
                label,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.label,
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
