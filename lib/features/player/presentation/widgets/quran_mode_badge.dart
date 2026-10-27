// lib/features/player/presentation/widgets/quran_mode_badge.dart
import 'package:flutter/material.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import '../../../../core/theme/aura_theme.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'quran_mode_sheet.dart';

/// Interactive pill badge displayed next to the audio quality / radio banner
/// whenever Quran Mode is active. Tapping opens [QuranModeSheet].
class QuranModeBadge extends StatelessWidget {
  final bool compact;
  final VoidCallback? onTap;

  const QuranModeBadge({
    super.key,
    this.compact = true,
    this.onTap,
  });

  static const Color badgeColor = AppColors.quranEmerald;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () => QuranModeSheet.show(context),
        borderRadius: AppRadii.r20All,
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 3 : 6,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                badgeColor.withValues(alpha: 0.20),
                badgeColor.withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: AppRadii.r20All,
            border: Border.all(
              color: badgeColor.withValues(alpha: 0.45),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: badgeColor.withValues(alpha: 0.14),
                blurRadius: 8,
                spreadRadius: -1,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_stories_rounded,
                  size: compact ? 12 : 14,
                  color: badgeColor,
                ),
                const SizedBox(width: AppSpacing.s6),
                Text(
                  'Quran Mode',
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: compact ? AppFontSize.tiny : AppFontSize.label,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.overline,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Icon(
                  Icons.tune_rounded,
                  size: compact ? 11 : 13,
                  color: badgeColor.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
