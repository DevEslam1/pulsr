// lib/features/player/presentation/themes/player_top_bar.dart
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../sheets/song_options_sheet.dart';
import 'player_theme.dart';

/// Pull-down grab handle shown above the player top bar.
class PlayerPlayHandle extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const PlayerPlayHandle({
    super.key,
    this.padding =
        const EdgeInsets.only(top: AppSpacing.xxs, bottom: AppSpacing.s2),
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ExcludeSemantics(
      child: Padding(
        padding: padding,
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: (p.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.24),
              borderRadius: AppRadii.r2All,
            ),
          ),
        ),
      ),
    );
  }
}

/// Symmetrical top bar: dismiss control, centred "PLAYING FROM" header and the
/// song-info action. Card overrides the title/subtitle colours; classic uses a
/// slightly taller vertical inset.
class PlayerTopBar extends StatelessWidget {
  final PlayerThemeProps props;
  final bool isTablet;
  final Color? titleColor;
  final Color? subtitleColor;
  final double horizontalPadding;
  final double tabletHorizontalPadding;
  final double verticalPadding;
  final VoidCallback? onDismiss;
  final VoidCallback? onMore;
  final Widget? centerWidget;
  final bool showDismiss;
  final bool showMore;

  const PlayerTopBar({
    super.key,
    required this.props,
    required this.isTablet,
    this.titleColor,
    this.subtitleColor,
    this.horizontalPadding = 20,
    this.tabletHorizontalPadding = 28,
    this.verticalPadding = AppSpacing.s2,
    this.onDismiss,
    this.onMore,
    this.centerWidget,
    this.showDismiss = true,
    this.showMore = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final song = state.currentSong;
    final resolvedTitle = titleColor ?? p.textPrimary;
    final resolvedSubtitle = subtitleColor ?? p.textSecondary;
    final allowMotion = PulsrMotion.shouldAnimate(context);

    Widget circleButton({
      required IconData icon,
      required String semanticLabel,
      required double iconSize,
      required VoidCallback onTap,
    }) {
      return Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: SizedBox(
          width: AppSpacing.minTouchTarget,
          height: AppSpacing.minTouchTarget,
          child: Material(
            color: p.isDark ? AppColors.specularAt(0.08) : p.surfaceContainer,
            shape: CircleBorder(
              side: BorderSide(
                color: p.hairline,
                width: 1.0,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: resolvedTitle,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? tabletHorizontalPadding : horizontalPadding,
        vertical: verticalPadding,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (showDismiss)
            circleButton(
              icon: Icons.keyboard_arrow_down_rounded,
              semanticLabel: context.l10n.close,
              iconSize: isTablet ? 26 : 24,
              onTap: () {
                PulsrHaptics.lightImpact();
                if (onDismiss != null) {
                  onDismiss!();
                } else if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
            )
          else if (showMore)
            const SizedBox(
              width: AppSpacing.minTouchTarget,
              height: AppSpacing.minTouchTarget,
            ),
          Expanded(
            child: centerWidget != null
                ? Center(child: centerWidget!)
                : Semantics(
                    header: true,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: p.isDark
                                  ? AppColors.specularAt(0.05)
                                  : p.surfaceContainer.withValues(alpha: 0.6),
                              borderRadius: AppRadii.r12All,
                              border: Border.all(
                                color: p.hairline,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ExcludeSemantics(
                                  child: WaveformLogo(
                                    size: 12,
                                    color: state.isPlaying
                                        ? props.activeColor
                                        : resolvedSubtitle,
                                    animate: state.isPlaying && allowMotion,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.s6),
                                Flexible(
                                  child: Text(
                                    context.l10n.playingFrom.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontSize: AppFontSize.caption,
                                          letterSpacing: AppTracking.wide,
                                          fontWeight: FontWeight.w800,
                                          color: resolvedSubtitle.withValues(
                                            alpha: p.isDark ? 0.85 : 1.0,
                                          ),
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            (song?.album != null &&
                                    song!.album.trim().isNotEmpty)
                                ? song.album.trim()
                                : (song?.artist != null &&
                                        song!.artist.trim().isNotEmpty)
                                    ? song.artist.trim()
                                    : context.l10n.navLibrary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: isTablet
                                      ? AppFontSize.body
                                      : AppFontSize.bodySmall,
                                  color: resolvedTitle,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          if (showMore)
            circleButton(
              icon: Icons.more_horiz_rounded,
              semanticLabel: context.l10n.moreOptions,
              iconSize: isTablet ? 24 : 22,
              onTap: () {
                PulsrHaptics.lightImpact();
                if (onMore != null) {
                  onMore!();
                } else if (song != null) {
                  SongOptionsSheet.show(context, song: song);
                }
              },
            )
          else if (showDismiss)
            const SizedBox(
              width: AppSpacing.minTouchTarget,
              height: AppSpacing.minTouchTarget,
            ),
        ],
      ),
    );
  }
}
