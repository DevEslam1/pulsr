// lib/features/player/presentation/widgets/mini_player/mini_player_compact_card.dart
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_blur.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_strokes.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../../core/motion/pulsr_motion.dart';
import '../../../../../core/performance/gpu_budget.dart';
import '../../../../../core/theme/aura_theme.dart';
import '../../../../../core/utils/adaptive.dart';
import '../../../../../core/utils/l10n_extensions.dart';
import '../../../../../core/utils/pulsr_haptics.dart';
import '../../../../../core/widgets/cached_artwork.dart';
import '../../../../../core/widgets/glass_container.dart';
import '../../../../../core/widgets/spinning_vinyl_disc.dart';
import '../../../../../core/widgets/waveform_logo.dart';
import '../../../../../data/db/app_database.dart';
import '../../../../queue/presentation/widgets/queue_slot_switcher.dart';
import '../../../../settings/cubit/settings_state.dart';
import '../../../cubit/player_cubit.dart';
import '../../../cubit/player_state.dart';
import '../../themes/player_theme.dart';
import 'mini_player_error_bar.dart';
import 'mini_player_progress_bar.dart';

export 'mini_player_error_bar.dart';

/// Compact glass card surface for [MiniPlayer]: swipeable queue carousel,
/// transport buttons, wavy progress bar, grab handle, and error banner.
class MiniPlayerCompactCard extends StatelessWidget {
  final PlayerState state;
  final PlayerCubit cubit;
  final SongsTableData song;
  final List<SongsTableData> queue;
  final int currentIndex;
  final PlayerThemeMode playerThemeMode;
  final PageController? pageController;
  final bool carouselEnabled;
  final bool swipeInFlight;
  final bool showGrabChevron;
  final double horizontalDragDx;
  final bool swipeThresholdCrossed;
  final IconData? swipeLeftIcon;
  final IconData? swipeRightIcon;
  final ValueNotifier<bool> isInteracting;
  final ValueNotifier<double> carouselDragDelta;
  final VoidCallback onTap;
  final void Function(int page) onPageChanged;
  final VoidCallback onDrainPendingSync;
  final VoidCallback onRetryError;

  const MiniPlayerCompactCard({
    super.key,
    required this.state,
    required this.cubit,
    required this.song,
    required this.queue,
    required this.currentIndex,
    required this.playerThemeMode,
    required this.pageController,
    required this.carouselEnabled,
    required this.swipeInFlight,
    required this.showGrabChevron,
    required this.horizontalDragDx,
    required this.swipeThresholdCrossed,
    required this.swipeLeftIcon,
    required this.swipeRightIcon,
    required this.isInteracting,
    required this.carouselDragDelta,
    required this.onTap,
    required this.onPageChanged,
    required this.onDrainPendingSync,
    required this.onRetryError,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final surface = context.playerSurfacePalette;
    final activeAccent = p.accent;
    final isTablet = Adaptive.isTablet(context);
    final playerRadius = isTablet ? AppRadii.r28All : AppRadii.r24All;
    final isHighContrast =
        p.isHighContrast || MediaQuery.highContrastOf(context);
    final isCalm = p.isCalmDensity || GpuBudget.isEnabled || isHighContrast;
    final allowMotion = PulsrMotion.shouldAnimate(context);
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    final carouselHeight = 52.0 * textScale.clamp(1.0, 1.65);

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        isTablet ? 24 : 12,
        0,
        isTablet ? 24 : 12,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: playerRadius,
          boxShadow: [
            ...PulsrElevation.level4(context),
            // Intentional accent glow (not depth): keeps the player's identity
            // over bright artwork.
            if (!isCalm)
              BoxShadow(
                color: activeAccent.withValues(alpha: p.isDark ? 0.08 : 0.04),
                blurRadius: 16,
                spreadRadius: -4,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: playerRadius,
          child: GlassContainer(
            blur: AppBlur.chip,
            opacity: p.isDark ? 0.62 : 0.80,
            borderRadius: playerRadius,
            border: Border.all(
              color: p.hairline,
              width: AppStrokes.hairline,
            ),
            enableBlur: !isCalm,
            color: isCalm
                ? p.surfaceContainerHigh
                : Color.alphaBlend(
                    activeAccent.withValues(alpha: p.isDark ? 0.09 : 0.06),
                    p.surfaceContainerHigh,
                  ),
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                // Subtle top inner specular highlight
                if (!isCalm)
                  PositionedDirectional(
                    top: 0,
                    start: 20,
                    end: 20,
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: Container(
                          height: 1,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                surface.scrimStart.withValues(alpha: 0.0),
                                (p.isDark
                                        ? surface.highContrastInk
                                        : surface.scrimStart)
                                    .withValues(alpha: p.isDark ? 0.12 : 0.08),
                                surface.scrimStart.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.s10,
                        AppSpacing.s6,
                        AppSpacing.xxs,
                        0,
                      ),
                      child: Row(
                        children: [
                          // Interactive Swipeable Track Info Carousel
                          Expanded(
                            child: SizedBox(
                              height: carouselHeight,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  NotificationListener<ScrollNotification>(
                                    onNotification: _handleScrollNotification,
                                    child: PageView.builder(
                                      controller: pageController,
                                      physics: carouselEnabled
                                          ? const BouncingScrollPhysics()
                                          : const NeverScrollableScrollPhysics(),
                                      itemCount: queue.length,
                                      onPageChanged: onPageChanged,
                                      itemBuilder: (context, index) =>
                                          _buildCarouselItem(
                                        context,
                                        item: queue[index],
                                        index: index,
                                        isCurrent: index == currentIndex,
                                        allowMotion: allowMotion,
                                        activeAccent: activeAccent,
                                      ),
                                    ),
                                  ),
                                  if (carouselEnabled)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: ValueListenableBuilder<double>(
                                          valueListenable: carouselDragDelta,
                                          builder: (context, delta, _) {
                                            if (delta.abs() <= 0.05) {
                                              return const SizedBox.shrink();
                                            }
                                            final isNext = delta > 0;
                                            final progress =
                                                (delta.abs() / 0.35)
                                                    .clamp(0.0, 1.0);
                                            final crossed = delta.abs() >= 0.35;
                                            return Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                if (isNext)
                                                  PositionedDirectional(
                                                    end: 2,
                                                    child:
                                                        MiniPlayerSwipeActionBadge(
                                                      key: const ValueKey(
                                                          'mini_player_carousel_badge_next'),
                                                      icon: Icons
                                                          .skip_next_rounded,
                                                      progress: progress,
                                                      thresholdCrossed: crossed,
                                                      accentColor: activeAccent,
                                                    ),
                                                  )
                                                else
                                                  PositionedDirectional(
                                                    start: 2,
                                                    child:
                                                        MiniPlayerSwipeActionBadge(
                                                      key: const ValueKey(
                                                          'mini_player_carousel_badge_prev'),
                                                      icon: Icons
                                                          .skip_previous_rounded,
                                                      progress: progress,
                                                      thresholdCrossed: crossed,
                                                      accentColor: activeAccent,
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          // Primary Play/Pause Button with tonal capsule (>= 48x48dp hit target)
                          SizedBox(
                            width: AppSpacing.minTouchTarget,
                            height: AppSpacing.minTouchTarget,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: AppSpacing.minTouchTarget,
                                minHeight: AppSpacing.minTouchTarget,
                              ),
                              tooltip: state.isPlaying
                                  ? context.l10n.pause
                                  : context.l10n.play,
                              icon: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: activeAccent.withValues(
                                    alpha: p.isDark ? 0.14 : 0.10,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: AnimatedSwitcher(
                                  duration: context.motion(PulsrMotion.state),
                                  transitionBuilder: (child, anim) =>
                                      allowMotion
                                          ? ScaleTransition(
                                              scale: anim, child: child)
                                          : child,
                                  child: state.isBuffering
                                      ? SizedBox(
                                          key: const ValueKey<String>(
                                              'buffering'),
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.3,
                                            color: activeAccent,
                                          ),
                                        )
                                      : Icon(
                                          state.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          key: ValueKey<bool>(state.isPlaying),
                                          color: activeAccent,
                                          size: 28,
                                        ),
                                ),
                              ),
                              onPressed: () {
                                PulsrHaptics.lightImpact();
                                cubit.togglePlayPause();
                              },
                            ),
                          ),
                          // Skip Next Control
                          IconButton(
                            constraints: const BoxConstraints(
                              minWidth: AppSpacing.minTouchTarget,
                              minHeight: AppSpacing.minTouchTarget,
                            ),
                            tooltip: context.l10n.next,
                            icon: Icon(
                              Icons.skip_next_rounded,
                              color: state.hasNextNeighbour
                                  ? p.textPrimary
                                  : p.textTertiary.withValues(alpha: 0.38),
                              size: 26,
                            ),
                            onPressed: state.hasNextNeighbour
                                ? () {
                                    PulsrHaptics.selectionClick();
                                    cubit.next();
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                    RepaintBoundary(
                      child: MiniPlayerProgressBar(
                        duration: state.duration,
                        activeAccent: activeAccent,
                        hairlineColor: p.textTertiary
                            .withValues(alpha: p.isDark ? 0.45 : 0.35),
                        isPlaying: state.isPlaying,
                        isBuffering: state.isBuffering,
                        onSeek: (pos) => cubit.seek(pos),
                      ),
                    ),
                  ],
                ),
                // Top grab handle pill (+ directional chevron for first N sessions)
                Positioned(
                  top: showGrabChevron ? 1.5 : 4.5,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: context.motion(PulsrMotion.state),
                            width: swipeInFlight ? 34 : 28,
                            height: 3.0,
                            decoration: BoxDecoration(
                              color: p.textTertiary.withValues(
                                alpha: isHighContrast ? 0.72 : 0.34,
                              ),
                              borderRadius: AppRadii.r1_5All,
                            ),
                          ),
                          if (showGrabChevron) ...[
                            const SizedBox(width: AppSpacing.s2),
                            Icon(
                              Icons.keyboard_arrow_up_rounded,
                              key: const ValueKey('dock_grab_chevron'),
                              size: 12,
                              color: p.textTertiary.withValues(
                                alpha: isHighContrast ? 0.85 : 0.54,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (state.errorMessage != null)
                  PositionedDirectional(
                    top: 5,
                    start: 6,
                    end: 6,
                    child: MiniPlayerErrorBar(
                      message: state.errorMessage!,
                      accentColor: activeAccent,
                      onRetry: onRetryError,
                      onDismiss: cubit.clearError,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      isInteracting.value = true;
    } else if (notification is ScrollUpdateNotification &&
        carouselEnabled &&
        pageController != null &&
        pageController!.hasClients) {
      final page = pageController!.page;
      if (page != null) {
        carouselDragDelta.value = (page - currentIndex).clamp(-1.0, 1.0);
      }
    } else if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        isInteracting.value = true;
      } else if (!swipeInFlight) {
        isInteracting.value = false;
        if (carouselDragDelta.value != 0.0) {
          carouselDragDelta.value = 0.0;
        }
      }
    } else if (notification is ScrollEndNotification) {
      isInteracting.value = false;
      if (carouselDragDelta.value != 0.0) {
        carouselDragDelta.value = 0.0;
      }
      if (!swipeInFlight) {
        onDrainPendingSync();
      }
    }
    return false;
  }

  Widget _buildCarouselItem(
    BuildContext context, {
    required SongsTableData item,
    required int index,
    required bool isCurrent,
    required bool allowMotion,
    required Color activeAccent,
  }) {
    final p = context.palette;
    final surface = context.playerSurfacePalette;

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            // Artwork or Vinyl Disc
            Stack(
              alignment: Alignment.center,
              children: [
                if (playerThemeMode == PlayerThemeMode.vinyl)
                  SpinningVinylDisc(
                    id: item.id,
                    remoteArtworkUrl: item.remoteArtworkUrl,
                    size: 46,
                    isPlaying: state.isPlaying && isCurrent && allowMotion,
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.r12All,
                      border: Border.all(
                        color: p.hairline,
                        width: 0.75,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: surface.shadowAt(p.isDark ? 0.30 : 0.10),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Hero(
                      tag: isCurrent
                          ? nowPlayingArtHeroTag(playerThemeMode)
                          : 'queue_art_${item.id}_$index',
                      child: CachedArtwork(
                        id: item.id,
                        remoteUrl: item.remoteArtworkUrl,
                        type: ArtworkType.AUDIO,
                        size: 46,
                        borderRadius: 12,
                      ),
                    ),
                  ),
                if (isCurrent &&
                    state.isPlaying &&
                    playerThemeMode != PlayerThemeMode.vinyl)
                  PositionedDirectional(
                    bottom: 2,
                    end: 2,
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3.5,
                          vertical: 2.0,
                        ),
                        decoration: BoxDecoration(
                          color: surface.scrimEnd.withValues(alpha: 0.78),
                          borderRadius: AppRadii.r4All,
                          border: Border.all(
                            color: surface.specularAt(0.14),
                            width: 0.5,
                          ),
                        ),
                        child: WaveformLogo(
                          size: 11,
                          color: p.accent,
                          animate: allowMotion,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.sm),
            // Track title & artist.
            Expanded(
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  Transform.translate(
                    offset: Offset(
                      horizontalDragDx != 0.0
                          ? math.pow(horizontalDragDx.abs(), 0.78) *
                              horizontalDragDx.sign
                          : 0.0,
                      0,
                    ),
                    child: MediaQuery.withClampedTextScaling(
                      minScaleFactor: 0.8,
                      maxScaleFactor: 2.0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent ? p.textPrimary : p.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: AppFontSize.body,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s2),
                          Row(
                            children: [
                              QueueSlotBadge(
                                activeSlot: state.activeQueueSlot,
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                              Expanded(
                                child: Text(
                                  item.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.label,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!carouselEnabled &&
                      horizontalDragDx < -8 &&
                      swipeLeftIcon != null)
                    PositionedDirectional(
                      end: 0,
                      child: MiniPlayerSwipeActionBadge(
                        icon: swipeLeftIcon!,
                        progress: (horizontalDragDx.abs() / 40.0).clamp(0.0, 1.0),
                        thresholdCrossed: swipeThresholdCrossed,
                        accentColor: activeAccent,
                      ),
                    )
                  else if (horizontalDragDx > 8 && swipeRightIcon != null)
                    PositionedDirectional(
                      start: 0,
                      child: MiniPlayerSwipeActionBadge(
                        icon: swipeRightIcon!,
                        progress: (horizontalDragDx.abs() / 40.0).clamp(0.0, 1.0),
                        thresholdCrossed: swipeThresholdCrossed,
                        accentColor: activeAccent,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
