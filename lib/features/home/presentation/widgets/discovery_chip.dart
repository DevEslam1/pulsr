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
    final isHighContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final chipRadius = context.buttonRadius(rectRadius: 6.0);
    final tintedSurface = isHighContrast
        ? p.surfaceContainerHigh
        : Color.alphaBlend(
            iconColor.withValues(alpha: p.isDark ? 0.045 : 0.035),
            p.surfaceContainerHigh,
          );
    return PulsrPressable(
      onTap: onTap,
      pressedScale: 0.96,
      hapticStyle: PulsrHapticStyle.selection,
      focusBorderRadius: isCapsule ? chipRadius : AppRadii.full,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40.0),
        padding: isCapsule
            ? EdgeInsetsDirectional.symmetric(
                horizontal: compact ? AppSpacing.s10 : AppSpacing.s14,
                vertical: AppSpacing.s6,
              )
            : (compact
                ? const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.s10,
                    vertical: AppSpacing.s6,
                  )
                : const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.s8,
                    AppSpacing.s6,
                    AppSpacing.s14,
                    AppSpacing.s6,
                  )),
        decoration: isCapsule
            ? PulsrCapsuleStyle.decoration(p, borderRadius: chipRadius)
            : BoxDecoration(
                color: tintedSurface,
                borderRadius: AppRadii.full,
                border: Border.all(
                  color: isHighContrast ? p.borderStrong : p.borderSubtle,
                  width: isHighContrast ? 1.25 : 1.0,
                ),
                boxShadow: (p.isCalmDensity || isHighContrast)
                    ? null
                    : PulsrElevation.level1(p),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isCapsule && !compact)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconColor.withValues(alpha: p.isDark ? 0.16 : 0.12),
                ),
                child: Icon(
                  icon,
                  size: 14,
                  color: iconColor,
                ),
              )
            else
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
                fontSize: compact ? AppFontSize.caption : AppFontSize.label,
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
