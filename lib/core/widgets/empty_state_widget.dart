// lib/core/widgets/empty_state_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../constants/app_radii.dart';
import '../theme/aura_theme.dart';

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? primaryActionLabel;
  final IconData? primaryActionIcon;
  final VoidCallback? onPrimaryAction;
  final bool isPrimaryLoading;
  final String? secondaryActionLabel;
  final IconData? secondaryActionIcon;
  final VoidCallback? onSecondaryAction;
  final Color? iconColor;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.primaryActionLabel,
    this.primaryActionIcon,
    this.onPrimaryAction,
    this.isPrimaryLoading = false,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.onSecondaryAction,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final effectiveIconColor = iconColor ?? p.accent;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Animated Vector Graphic Container
            Stack(
              alignment: Alignment.center,
              children: [
                // Outer Glow Pulse Circle
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: effectiveIconColor.withValues(alpha: 0.08),
                  ),
                )
                    .animate(
                        onPlay: (controller) =>
                            controller.repeat(reverse: true))
                    .scaleXY(
                        begin: 0.9,
                        end: 1.15,
                        duration: 2500.ms,
                        curve: Curves.easeInOut),

                // Inner Glass Circle Container
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.surfaceContainer,
                    border: Border.all(
                      color: effectiveIconColor.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: effectiveIconColor.withValues(alpha: 0.2),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: 40,
                      color: effectiveIconColor,
                    ),
                  ),
                ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
              ],
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    fontSize: 20,
                  ),
            ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.15, end: 0),
            const SizedBox(height: 8),

            // Subtitle
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.15, end: 0),

            if (primaryActionLabel != null && onPrimaryAction != null) ...[
              const SizedBox(height: 28),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.cardRadius),
                    elevation: 2,
                  ),
                  onPressed: isPrimaryLoading ? null : onPrimaryAction,
                  child: isPrimaryLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.onAccent,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (primaryActionIcon != null) ...[
                              Icon(primaryActionIcon, size: 20),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              primaryActionLabel!,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ],
                        ),
                ),
              ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.2, end: 0),
            ],

            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.textPrimary,
                  side: BorderSide(color: p.hairline),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape:
                      RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
                ),
                onPressed: onSecondaryAction,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (secondaryActionIcon != null) ...[
                      Icon(secondaryActionIcon,
                          size: 18, color: p.textSecondary),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      secondaryActionLabel!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 450.ms),
            ],
          ],
        ),
      ),
    );
  }
}
