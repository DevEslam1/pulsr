// lib/features/player/presentation/widgets/radio_now_playing_recommendations.dart
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/ambient_sound_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../data/db/app_database.dart';
import '../../cubit/player_cubit.dart';
import '../themes/player_theme.dart';
import '../themes/player_theme_scaffold.dart';
import 'ambient_sound_sheet.dart';
import 'quran_mode_sheet.dart';

/// Compact capsule recommendation bar displayed on the Now Playing screen when
/// listening to live radio, matching the sleek `Radio` pill (`AudioQualityBadge`)
/// directly above it:
/// - **Quran Mode capsule**: tap to toggle Quran Mode ON/OFF; long press to
///   open [QuranModeSheet].
/// - **Ambient Sounds capsule**: tap to toggle Ambient Sounds ON/OFF using the
///   user's saved effects & volumes; long press to open [AmbientSoundSheet].
class RadioNowPlayingRecommendations extends StatelessWidget {
  final PlayerThemeProps props;
  final PlayerCubit cubit;
  final PlayerThemeMetrics? metrics;

  const RadioNowPlayingRecommendations({
    super.key,
    required this.props,
    required this.cubit,
    this.metrics,
  });

  /// Only a live radio stream gets this recommendation surface. A net-library
  /// file ([SongSource.remote]) is finite and seekable, so it must not show the
  /// radio capsules (the Quran/ambient offers assume an endless live broadcast).
  static bool shouldShowFor(SongsTableData? song) =>
      SongSource.isLive(song?.source);

  @override
  Widget build(BuildContext context) {
    final song = props.state.currentSong;
    if (!shouldShowFor(song)) {
      return const SizedBox.shrink();
    }
    if (props.state.isLyricsVisible || props.state.isQueueVisible) {
      return const SizedBox.shrink();
    }

    final p = context.palette;
    final l10n = context.l10n;
    final isQuranOn = props.state.isQuranModeEnabled;
    final ambientService = AmbientSoundService();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.xxs,
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xxs,
        children: [
          _RadioPillCapsule(
            key: const ValueKey('radio_rec_quran_capsule'),
            icon: Icons.auto_stories_rounded,
            label: l10n.quranMode,
            accent: AppColors.quranEmerald,
            isActive: isQuranOn,
            palette: p,
            onTap: () {
              PulsrHaptics.selectionClick();
              unawaited(cubit.setQuranModeEnabled(!isQuranOn));
            },
            onLongPress: () {
              PulsrHaptics.mediumImpact();
              QuranModeSheet.show(context);
            },
          ),
          ListenableBuilder(
            listenable: ambientService,
            builder: (context, _) {
              final isAmbientOn = ambientService.isEnabled;
              final activeCount = ambientService.activeEffects.length;
              final percent = (ambientService.masterVolume * 100).round();
              final label = (isAmbientOn && activeCount > 0)
                  ? '${l10n.ambientSounds} · $percent%'
                  : l10n.ambientSounds;
              return _RadioPillCapsule(
                key: const ValueKey('radio_rec_ambient_capsule'),
                icon: Icons.water_drop_rounded,
                label: label,
                accent: props.activeColor,
                isActive: isAmbientOn,
                palette: p,
                onTap: () {
                  PulsrHaptics.selectionClick();
                  unawaited(ambientService.setEnabled(!isAmbientOn));
                },
                onLongPress: () {
                  PulsrHaptics.mediumImpact();
                  AmbientSoundSheet.show(context);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RadioPillCapsule extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final bool isActive;
  final PulsrPalette palette;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RadioPillCapsule({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.isActive,
    required this.palette,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isHighContrast = palette.isHighContrast ||
        (MediaQuery.maybeHighContrastOf(context) ?? false);
    final flat = palette.isCalmDensity || isHighContrast;

    final BoxDecoration decoration;
    if (isHighContrast) {
      decoration = BoxDecoration(
        color: isActive ? palette.surfaceContainerHigh : palette.surface,
        borderRadius: AppRadii.r20All,
        border: Border.all(
          color: isActive ? accent : palette.borderStrong,
          width: 1.5,
        ),
      );
    } else if (isActive) {
      decoration = BoxDecoration(
        gradient: flat
            ? null
            : LinearGradient(
                colors: [
                  accent.withValues(alpha: palette.isDark ? 0.22 : 0.16),
                  accent.withValues(alpha: palette.isDark ? 0.08 : 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: flat
            ? Color.alphaBlend(
                accent.withValues(alpha: palette.isDark ? 0.16 : 0.12),
                palette.surfaceContainer,
              )
            : null,
        borderRadius: AppRadii.r20All,
        border: Border.all(
          color: accent.withValues(alpha: palette.isDark ? 0.48 : 0.40),
          width: 1.0,
        ),
        boxShadow: flat
            ? null
            : [
                BoxShadow(
                  color: accent.withValues(
                    alpha: (palette.isDark ? 0.14 : 0.10) *
                        palette.chromeGlowScale,
                  ),
                  blurRadius: 8,
                  spreadRadius: -1,
                  offset: const Offset(0, 2),
                ),
              ],
      );
    } else {
      decoration = BoxDecoration(
        color: palette.surfaceContainer.withValues(
          alpha: palette.isDark ? 0.68 : 0.92,
        ),
        borderRadius: AppRadii.r20All,
        border: Border.all(
          color: palette.borderSubtle,
          width: 1.0,
        ),
      );
    }

    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSpacing.minTouchTarget,
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: AppRadii.r20All,
            child: Center(
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s10,
                  vertical: 5.0,
                ),
                decoration: decoration,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 13,
                      color: isActive ? accent : palette.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.s6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isActive
                              ? palette.textPrimary
                              : palette.textSecondary,
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w800,
                          letterSpacing: AppTracking.overline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
