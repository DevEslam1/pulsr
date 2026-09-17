import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/list_content_diff.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/spinning_vinyl_disc.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';

class MiniPlayer extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onSwipeDown;
  final VoidCallback? onSwipeUp;

  const MiniPlayer({
    super.key,
    required this.onTap,
    this.onSwipeDown,
    this.onSwipeUp,
  });

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  PageController? _pageController;
  int _lastKnownIndex = -1;
  bool _isUserDragging = false;
  bool _swipeInFlight = false;
  double _verticalDragDy = 0.0;
  double _horizontalDragDx = 0.0;

  /// The Hero tag used by the full-screen artwork for the active theme, so the
  /// mini -> full shared-element transition actually runs (tags must match).
  String _fullArtworkHeroTag(PlayerThemeMode mode) {
    switch (mode) {
      case PlayerThemeMode.minimal:
        return 'now_playing_art_minimal';
      default:
        return 'now_playing_art_full';
    }
  }

  /// Honors the user's configured mini-player swipe actions
  /// (next / prev / volume / none) for the directions the carousel does not
  /// already handle natively.
  void _applySwipeAction(
    MiniPlayerSwipeAction action,
    PlayerCubit cubit, {
    required bool swipedLeft,
  }) {
    switch (action) {
      case MiniPlayerSwipeAction.next:
        HapticFeedback.selectionClick();
        unawaited(cubit.next());
        break;
      case MiniPlayerSwipeAction.prev:
        HapticFeedback.selectionClick();
        unawaited(cubit.previous());
        break;
      case MiniPlayerSwipeAction.volume:
        HapticFeedback.selectionClick();
        unawaited(cubit.adjustVolume(swipedLeft ? 0.05 : -0.05));
        break;
      case MiniPlayerSwipeAction.none:
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    // Created eagerly so the PageView is always driven by this controller and
    // synchronisation never has to run inside build (A-9).
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _syncPageController(int targetIndex, int queueLength) {
    final controller = _pageController;
    if (queueLength == 0 || controller == null) return;
    final safeIndex = targetIndex.clamp(0, queueLength - 1);
    // Never fight an in-progress user gesture; the page-change handler releases
    // the latch once the skip it triggered has completed.
    if (_isUserDragging) return;
    if (_lastKnownIndex != safeIndex) {
      _lastKnownIndex = safeIndex;
      if (controller.hasClients && controller.page?.round() != safeIndex) {
        controller.jumpToPage(safeIndex);
      }
    }
  }

  /// A swipe landed on [page]: latch the intent and release it only after the
  /// skip has actually been applied, so a notification that arrives mid-skip
  /// (e.g. ScrollEnd before the state update) can no longer snap the carousel
  /// back to the old track.
  Future<void> _completeSwipe(int page, PlayerCubit cubit) async {
    try {
      await cubit.skipToQueueItem(page);
    } catch (_) {
      // Failure is already surfaced by PlayerCubit; just release the latch.
    }
    if (!mounted) return;
    setState(() {
      _isUserDragging = false;
      _swipeInFlight = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Narrow subscription: only the vinyl theme decision is read here, so an
    // unrelated settings change must not rebuild the mini player (A-11).
    final playerThemeMode = context
        .select<SettingsCubit, PlayerThemeMode>((c) => c.state.playerThemeMode);
    // Mini-player swipe actions are user-configurable; the queue carousel can
    // only natively express the next/prev mapping.
    final swipeLeftAction = context.select<SettingsCubit, MiniPlayerSwipeAction>(
        (c) => c.state.miniPlayerSwipeLeft);
    final swipeRightAction =
        context.select<SettingsCubit, MiniPlayerSwipeAction>(
            (c) => c.state.miniPlayerSwipeRight);
    final carouselEnabled = swipeLeftAction == MiniPlayerSwipeAction.next &&
        swipeRightAction == MiniPlayerSwipeAction.prev;
    final p = context.palette;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (a, b) =>
          a.currentSong?.id != b.currentSong?.id ||
          a.currentSong?.title != b.currentSong?.title ||
          a.currentSong?.artist != b.currentSong?.artist ||
          a.currentSong?.remoteArtworkUrl != b.currentSong?.remoteArtworkUrl ||
          a.isPlaying != b.isPlaying ||
          a.duration != b.duration ||
          a.currentIndex != b.currentIndex ||
          listContentDiffers(a.queue, b.queue),
      builder: (context, state) {
        final song = state.currentSong;
        if (song == null) return const SizedBox.shrink();

        final cubit = context.read<PlayerCubit>();
        final activeAccent = p.accent;
        final queue = state.queue.isNotEmpty ? state.queue : [song];
        final currentIndex = state.currentIndex.clamp(0, queue.length - 1);

        // Page synchronisation must not run during build: defer the jump to the
        // end of the frame, after the PageView has laid out (A-9).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncPageController(currentIndex, queue.length);
        });

        final isTablet = Adaptive.isTablet(context);
        final playerRadius = BorderRadius.circular(isTablet ? 28 : 24);

        return Semantics(
          label: context.l10n.nowPlayingSemantics(song.title, song.artist),
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) {
              _verticalDragDy = 0.0;
            },
            onVerticalDragUpdate: (d) {
              _verticalDragDy += d.delta.dy;
            },
            onVerticalDragEnd: (d) {
              final vy = d.velocity.pixelsPerSecond.dy;
              if (_verticalDragDy > 25 || vy > 120) {
                HapticFeedback.selectionClick();
                widget.onSwipeDown?.call();
              } else if (_verticalDragDy < -25 || vy < -120) {
                HapticFeedback.selectionClick();
                if (widget.onSwipeUp != null) {
                  widget.onSwipeUp!();
                } else {
                  widget.onTap();
                }
              }
              _verticalDragDy = 0.0;
            },
            onHorizontalDragStart: carouselEnabled
                ? null
                : (_) {
                    _horizontalDragDx = 0.0;
                  },
            onHorizontalDragUpdate: carouselEnabled
                ? null
                : (d) {
                    _horizontalDragDx += d.delta.dx;
                  },
            onHorizontalDragEnd: carouselEnabled
                ? null
                : (d) {
                    final dx = _horizontalDragDx + d.velocity.pixelsPerSecond.dx * 0.05;
                    _horizontalDragDx = 0.0;
                    if (dx.abs() < 24) return;
                    final swipedLeft = dx < 0;
                    _applySwipeAction(
                      swipedLeft ? swipeLeftAction : swipeRightAction,
                      cubit,
                      swipedLeft: swipedLeft,
                    );
                  },
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                isTablet ? 24 : 10,
                0,
                isTablet ? 24 : 10,
                0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: playerRadius,
                  boxShadow: [
                    BoxShadow(
                      color: activeAccent.withValues(
                          alpha: p.isDark ? 0.22 : 0.15),
                      blurRadius: 18,
                      spreadRadius: -2,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: p.isDark ? 0.45 : 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: GlassContainer(
                  blur: 20,
                  opacity: p.isDark ? 0.93 : 0.97,
                  borderRadius: playerRadius,
                  color: Color.alphaBlend(
                    activeAccent.withValues(alpha: p.isDark ? 0.12 : 0.08),
                    p.surface,
                  ),
                  border: Border.all(
                    color: activeAccent.withValues(alpha: 0.26),
                    width: 1.2,
                  ),
                  child: ClipRRect(
                    borderRadius: playerRadius,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 8, 0),
                            child: Row(
                              children: [
                                // Interactive Swipeable Track Info Carousel
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: NotificationListener<ScrollNotification>(
                                      onNotification: (notification) {
                                        if (notification is ScrollStartNotification &&
                                            notification.dragDetails != null) {
                                          // Latch the swipe intent at drag start.
                                          _isUserDragging = true;
                                          _swipeInFlight = false;
                                        } else if (notification is UserScrollNotification) {
                                          _isUserDragging =
                                              notification.direction != ScrollDirection.idle;
                                        } else if (notification is ScrollEndNotification) {
                                          // Only release immediately when no skip is
                                          // pending; otherwise the page-change handler
                                          // releases it after the skip completes.
                                          if (!_swipeInFlight) {
                                            _isUserDragging = false;
                                          }
                                        }
                                        return false;
                                      },
                                      child: PageView.builder(
                                        controller: _pageController,
                                        physics: carouselEnabled
                                            ? const BouncingScrollPhysics()
                                            : const NeverScrollableScrollPhysics(),
                                        itemCount: queue.length,
                                        onPageChanged: (page) {
                                          if (_isUserDragging &&
                                              page != currentIndex) {
                                            _lastKnownIndex = page;
                                            _swipeInFlight = true;
                                            unawaited(_completeSwipe(page, cubit));
                                          }
                                        },
                                      itemBuilder: (context, index) {
                                        final item = queue[index];
                                        final isCurrent = index == currentIndex;

                                        return GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: widget.onTap,
                                          child: Row(
                                            children: [
                                              // Artwork or Vinyl Disc
                                              if (playerThemeMode ==
                                                  PlayerThemeMode.vinyl)
                                                SpinningVinylDisc(
                                                  id: item.id,
                                                  remoteArtworkUrl:
                                                      item.remoteArtworkUrl,
                                                  size: 46,
                                                  isPlaying: state.isPlaying &&
                                                      isCurrent,
                                                )
                                              else
                                                Hero(
                                                  tag: isCurrent
                                                      ? _fullArtworkHeroTag(
                                                          playerThemeMode)
                                                      : 'queue_art_${item.id}_$index',
                                                  child: CachedArtwork(
                                                    id: item.id,
                                                    remoteUrl:
                                                        item.remoteArtworkUrl,
                                                    type: ArtworkType.AUDIO,
                                                    size: 46,
                                                    borderRadius: 12,
                                                  ),
                                                ),
                                              const SizedBox(width: 12),
                                              // Track title & artist.
                                              // Dense fixed-height chrome: clamp
                                              // Dynamic Type here so the 52px
                                              // row can never clip, while
                                              // content areas scale to 2.0x.
                                              Expanded(
                                                child: MediaQuery.withClampedTextScaling(
                                                  minScaleFactor: 0.8,
                                                  maxScaleFactor: 1.3,
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.center,
                                                    children: [
                                                      Text(
                                                        item.title,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          color: isCurrent
                                                              ? p.textPrimary
                                                              : p.textSecondary,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 14.5,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        item.artist,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          color: p.textSecondary,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Controls
                                IconButton(
                                  tooltip: state.isPlaying
                                      ? context.l10n.pause
                                      : context.l10n.play,
                                  icon: Icon(
                                    state.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: activeAccent,
                                    size: 32,
                                  ),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    cubit.togglePlayPause();
                                  },
                                ),
                                IconButton(
                                  tooltip: context.l10n.next,
                                  icon: Icon(
                                    Icons.skip_next_rounded,
                                    color: p.textPrimary,
                                    size: 28,
                                  ),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    cubit.next();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        _MiniPlayerProgressBar(
                          duration: state.duration,
                          activeAccent: activeAccent,
                          hairlineColor: p.hairline,
                          onSeek: (pos) => cubit.seek(pos),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniPlayerProgressBar extends StatefulWidget {
  final Duration duration;
  final Color activeAccent;
  final Color hairlineColor;
  final void Function(Duration) onSeek;

  const _MiniPlayerProgressBar({
    required this.duration,
    required this.activeAccent,
    required this.hairlineColor,
    required this.onSeek,
  });

  @override
  State<_MiniPlayerProgressBar> createState() => _MiniPlayerProgressBarState();
}

class _MiniPlayerProgressBarState extends State<_MiniPlayerProgressBar> {
  double? _dragProgress;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          return BlocSelector<PlayerCubit, PlayerState, Duration>(
            selector: (s) => s.position,
            builder: (context, position) {
              final progress = _dragProgress ??
                  (widget.duration.inMilliseconds > 0
                      ? (position.inMilliseconds / widget.duration.inMilliseconds)
                          .clamp(0.0, 1.0)
                      : 0.0);
              final currentDuration = _dragProgress != null
                  ? Duration(
                      milliseconds: (widget.duration.inMilliseconds *
                              _dragProgress!)
                          .round())
                  : position;
              final valueLabel =
                  '${Formatters.formatDuration(currentDuration)} / ${Formatters.formatDuration(widget.duration)}';

              Duration clampDuration(Duration d) {
                if (d < Duration.zero) return Duration.zero;
                if (d > widget.duration) return widget.duration;
                return d;
              }

              String labelFor(Duration d) =>
                  '${Formatters.formatDuration(d)} / ${Formatters.formatDuration(widget.duration)}';
              final increasedLabel = labelFor(
                  clampDuration(currentDuration + const Duration(seconds: 10)));
              final decreasedLabel = labelFor(
                  clampDuration(currentDuration - const Duration(seconds: 10)));

              return Semantics(
                slider: true,
                label: context.l10n.seekLabel,
                value: valueLabel,
                increasedValue: increasedLabel,
                decreasedValue: decreasedLabel,
                onIncrease: () => widget.onSeek(
                    clampDuration(currentDuration + const Duration(seconds: 10))),
                onDecrease: () => widget.onSeek(
                    clampDuration(currentDuration - const Duration(seconds: 10))),
                child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  if (trackWidth > 0 && widget.duration.inMilliseconds > 0) {
                    final ratio =
                        (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                    setState(() => _dragProgress = null);
                    final seekMs =
                        (widget.duration.inMilliseconds * ratio).round();
                    widget.onSeek(Duration(milliseconds: seekMs));
                  }
                },
                onHorizontalDragStart: (details) {
                  if (trackWidth > 0 && widget.duration.inMilliseconds > 0) {
                    final ratio =
                        (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                    setState(() => _dragProgress = ratio);
                  }
                },
                onHorizontalDragUpdate: (details) {
                  if (trackWidth > 0 && widget.duration.inMilliseconds > 0) {
                    final ratio =
                        (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                    setState(() => _dragProgress = ratio);
                  }
                },
                onHorizontalDragEnd: (_) {
                  if (_dragProgress != null &&
                      widget.duration.inMilliseconds > 0) {
                    final seekMs =
                        (widget.duration.inMilliseconds * _dragProgress!)
                            .round();
                    widget.onSeek(Duration(milliseconds: seekMs));
                    setState(() => _dragProgress = null);
                  }
                },
                onHorizontalDragCancel: () {
                  setState(() => _dragProgress = null);
                },
                // 18px-tall hit area so the thin 4.5px progress bar is actually
                // grabbable; the visual track stays centered and thin.
                child: SizedBox(
                  height: 18,
                  width: double.infinity,
                  child: Center(
                    child: SizedBox(
                      height: 4.5,
                      width: double.infinity,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Positioned.fill(
                            child: ColoredBox(
                                color: widget.hairlineColor
                                    .withValues(alpha: 0.35)),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress,
                              alignment: Alignment.centerLeft,
                              child: Container(
                                height: 4.5,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      widget.activeAccent
                                          .withValues(alpha: 0.7),
                                      widget.activeAccent,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: widget.activeAccent
                                          .withValues(alpha: 0.45),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            },
          );
        },
      ),
    );
  }
}
