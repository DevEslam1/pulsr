// lib/features/player/presentation/themes/player_track_header.dart
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/services/sound_feedback_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../data/db/app_database.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../../cubit/player_cubit.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/player_more_sheet.dart';
import 'player_theme.dart';
import 'player_theme_scaffold.dart' show PlayerThemeMetrics;

/// Heart button with the scale animation shared by every theme.
class PlayerAnimatedFavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final Color favoriteColor;
  final Color inactiveColor;
  final double iconSize;
  final String semanticLabel;
  final VoidCallback onTap;

  const PlayerAnimatedFavoriteButton({
    super.key,
    required this.isFavorite,
    required this.favoriteColor,
    required this.inactiveColor,
    this.iconSize = 24,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final allowMotion = PulsrMotion.shouldAnimate(context);
    return Semantics(
      button: true,
      toggled: isFavorite,
      label: semanticLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSpacing.minTouchTarget,
          minHeight: AppSpacing.minTouchTarget,
        ),
        child: InkWell(
          onTap: () {
            PulsrHaptics.confirm();
            SoundFeedbackService.playClick();
            onTap();
          },
          child: Center(
            child: AnimatedSwitcher(
              duration: context.motionMs(260),
              transitionBuilder: (child, anim) {
                if (!allowMotion) return child;
                final isHeart = (child.key as ValueKey<bool>?)?.value == true;
                final curve =
                    isHeart ? Curves.easeOutBack : Curves.easeOutCubic;
                return ScaleTransition(
                  scale: anim.drive(
                    CurveTween(curve: context.motionCurve(curve)),
                  ),
                  child: child,
                );
              },
              child: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                key: ValueKey(isFavorite),
                color: isFavorite ? favoriteColor : inactiveColor,
                size: iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Track header: [download / add-to-playlist] title + artist [favourite],
/// followed by the audio-quality badge (and an optional extra badge chip).
class PlayerTrackHeader extends StatelessWidget {
  final PlayerThemeProps props;
  final bool isTablet;
  final double horizontalPadding;
  final double tabletHorizontalPadding;
  final double? verticalPadding;
  final Color? titleColor;
  final Color? subtitleColor;
  final Widget? extraBadge;
  final double badgeGap;
  final double titleArtistGap;
  final bool showQualityBadge;
  final double? titleFontSize;
  final double? subtitleFontSize;
  final double? actionButtonSize;
  final PlayerThemeMetrics? metrics;

  /// Left-aligns title/artist instead of centering them. Minimal uses this to
  /// read as a typographic layout rather than a re-skinned Classic.
  final bool alignStart;

  const PlayerTrackHeader({
    super.key,
    required this.props,
    required this.isTablet,
    this.horizontalPadding = 16,
    this.tabletHorizontalPadding = 28,
    this.verticalPadding,
    this.titleColor,
    this.subtitleColor,
    this.extraBadge,
    this.badgeGap = AppSpacing.s8,
    this.titleArtistGap = AppSpacing.xs,
    this.showQualityBadge = true,
    this.titleFontSize,
    this.subtitleFontSize,
    this.actionButtonSize,
    this.metrics,
    this.alignStart = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAlignStart = alignStart || PlayerSplitViewScope.of(context);
    final p = context.palette;
    final state = props.state;
    final song = state.currentSong;
    final isFav = song?.isFavorite == true;
    // Every theme shares one readable hierarchy: a white title and a neutral
    // grey artist on dark backdrops, palette text colours on light ones.
    final resolvedTitle = titleColor ?? p.textPrimary;
    final resolvedSubtitle = subtitleColor ?? p.textSecondary;
    final hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

    final double effectiveVerticalPadding =
        verticalPadding ?? metrics?.trackHeaderVerticalPadding ?? AppSpacing.s6;
    final double resolvedTitleFontSize = titleFontSize ??
        metrics?.titleFontSize ??
        (isTablet ? AppFontSize.headline : AppFontSize.title);
    final double resolvedSubtitleFontSize = subtitleFontSize ??
        metrics?.artistFontSize ??
        (isTablet ? AppFontSize.callout : AppFontSize.bodySmall);
    final double resolvedActionButtonSize = actionButtonSize ??
        metrics?.actionButtonSize ??
        (isTablet ? 48.0 : 44.0);
    final double iconSize =
        isTablet ? 24.0 : (resolvedActionButtonSize < 42.0 ? 18.0 : 20.0);

    final qualityBadge = song == null
        ? null
        : AudioQualityBadge(
            song: song,
            activeColor: props.activeColor,
            compact: true,
            showDevice: false,
          );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? tabletHorizontalPadding : horizontalPadding,
        vertical: effectiveVerticalPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Minimal distils the header: add-to-playlist lives in the More
              // sheet, so the title can start at the screen gutter.
              if (!effectiveAlignStart)
                SizedBox(
                  width: resolvedActionButtonSize,
                  height: resolvedActionButtonSize,
                  child: Material(
                    color: p.isDark
                        ? AppColors.specularAt(0.07)
                        : p.surfaceContainer,
                    shape: CircleBorder(
                      side: BorderSide(
                        color: p.hairline,
                        width: 1.0,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasDownload
                        ? Center(
                            child: YtmDownloadButton(
                              song: song,
                              activeColor: props.activeColor,
                              iconColor: resolvedSubtitle,
                              iconSize: iconSize,
                            ),
                          )
                        : Semantics(
                            button: true,
                            label: context.l10n.addToPlaylist,
                            excludeSemantics: true,
                            child: InkWell(
                              onTap: () {
                                if (song != null) {
                                  PulsrHaptics.lightImpact();
                                  AddToPlaylistSheet.show(context, song: song);
                                }
                              },
                              child: Center(
                                child: Icon(
                                  Icons.playlist_add_rounded,
                                  size: iconSize,
                                  color: resolvedSubtitle,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: effectiveAlignStart ? 0 : AppSpacing.s10,
                    end: AppSpacing.s10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: effectiveAlignStart
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: MarqueeText(
                          text: song?.title ?? context.l10n.noTrackSelected,
                          textAlign: effectiveAlignStart
                              ? TextAlign.start
                              : TextAlign.center,
                          style: TextStyle(
                            fontSize: resolvedTitleFontSize,
                            fontWeight: FontWeight.w900,
                            color: resolvedTitle,
                            height: 1.22,
                            letterSpacing: AppTracking.title,
                          ),
                        ),
                      ),
                      SizedBox(height: titleArtistGap),
                      SizedBox(
                        width: double.infinity,
                        child: MarqueeText(
                          text: song?.artist ?? context.l10n.unknownArtist,
                          textAlign: effectiveAlignStart
                              ? TextAlign.start
                              : TextAlign.center,
                          style: TextStyle(
                            fontSize: resolvedSubtitleFontSize,
                            fontWeight: FontWeight.w600,
                            color: resolvedSubtitle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedContainer(
                duration: context.motionMs(200),
                width: resolvedActionButtonSize,
                height: resolvedActionButtonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFav
                      ? p.favorite.withValues(alpha: p.isDark ? 0.16 : 0.12)
                      : (p.isDark
                          ? AppColors.specularAt(0.07)
                          : p.surfaceContainer),
                  border: Border.all(
                    color: isFav
                        ? p.favorite.withValues(alpha: 0.45)
                        : p.hairline,
                    width: 1.0,
                  ),
                  boxShadow: isFav
                      ? [
                          BoxShadow(
                            color: p.favorite.withValues(alpha: 0.20),
                            blurRadius: 10,
                            spreadRadius: -2,
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: PlayerAnimatedFavoriteButton(
                    isFavorite: isFav,
                    semanticLabel:
                        isFav ? context.l10n.unlike : context.l10n.like,
                    favoriteColor: p.favorite,
                    inactiveColor: resolvedSubtitle,
                    iconSize: iconSize,
                    onTap: () {
                      if (song != null) {
                        props.cubit.toggleFavorite(song.id);
                      }
                    },
                  ),
                ),
              ),
              if (effectiveAlignStart) ...[
                const SizedBox(width: AppSpacing.s6),
                Semantics(
                  button: true,
                  label: context.l10n.moreOptions,
                  excludeSemantics: true,
                  child: SizedBox(
                    width: resolvedActionButtonSize,
                    height: resolvedActionButtonSize,
                    child: Material(
                      color: p.isDark
                          ? AppColors.specularAt(0.07)
                          : p.surfaceContainer,
                      shape: CircleBorder(
                        side: BorderSide(
                          color: p.hairline,
                          width: 1.0,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          PulsrHaptics.lightImpact();
                          PlayerMoreSheet.show(context,
                              song: song, activeColor: props.activeColor);
                        },
                        child: Center(
                          child: Icon(
                            Icons.more_horiz_rounded,
                            size: iconSize,
                            color: resolvedSubtitle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (showQualityBadge && qualityBadge != null) ...[
            SizedBox(height: badgeGap),
            Align(
              alignment: effectiveAlignStart
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    qualityBadge,
                    if (extraBadge != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      extraBadge!,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared studio-styled bookmark resume prompt banner used by both
/// [PlayerControlsColumn] and [PlayerThemeScaffold].
class PlayerBookmarkPromptBanner extends StatelessWidget {
  final PlayerCubit cubit;
  final Duration position;

  const PlayerBookmarkPromptBanner({
    super.key,
    required this.cubit,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                p.warning.withValues(alpha: p.isDark ? 0.20 : 0.14),
                p.warning.withValues(alpha: p.isDark ? 0.08 : 0.06),
              ],
            ),
            borderRadius: AppRadii.r16All,
            border: Border.all(
              color: p.warning.withValues(alpha: 0.42),
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.warning.withValues(alpha: 0.22),
                  ),
                  child: Icon(
                    Icons.bookmark_rounded,
                    size: 16,
                    color: p.warning,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.resumeFromPrompt(Formatters.formatDuration(position)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.bodySmall,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: p.warning,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(
                    AppSpacing.minTouchTarget,
                    AppSpacing.minTouchTarget,
                  ),
                  textStyle: const TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: () {
                  PulsrHaptics.selectionClick();
                  cubit.seekToBookmark();
                },
                child: Text(l10n.resume),
              ),
              SizedBox(
                // 48dp touch target; the glyph stays 17dp and is centred.
                width: AppSpacing.minTouchTarget,
                height: AppSpacing.minTouchTarget,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: l10n.close,
                  onPressed: () {
                    PulsrHaptics.lightImpact();
                    cubit.dismissBookmark();
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    size: 17,
                    color: p.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
