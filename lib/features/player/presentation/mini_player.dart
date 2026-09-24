import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/list_content_diff.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/gesture_hint_overlay.dart';
import '../../../core/widgets/spinning_vinyl_disc.dart';
import '../../../core/widgets/waveform_logo.dart';
import '../../../data/db/app_database.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import '../../../core/utils/error_logger.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
  bool _controllerDisposed = false;
  int _lastKnownIndex = -1;
  final ValueNotifier<bool> _isInteracting = ValueNotifier<bool>(false);
  bool _swipeInFlight = false;
  Timer? _verticalSwipeTimer;
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
  Future<void> _applySwipeAction(
    MiniPlayerSwipeAction action,
    PlayerCubit cubit, {
    required bool swipedLeft,
  }) async {
    if (_swipeInFlight) return;
    _swipeInFlight = true;
    try {
      switch (action) {
        case MiniPlayerSwipeAction.next:
          HapticFeedback.selectionClick();
          await cubit.next();
          break;
        case MiniPlayerSwipeAction.prev:
          HapticFeedback.selectionClick();
          await cubit.previous();
          break;
        case MiniPlayerSwipeAction.volume:
          HapticFeedback.selectionClick();
          await cubit.adjustVolume(swipedLeft ? 0.05 : -0.05);
          break;
        case MiniPlayerSwipeAction.none:
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _swipeInFlight = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final initialIndex = context.read<PlayerCubit>().state.currentIndex;
    final safeInitial = initialIndex >= 0 ? initialIndex : 0;
    _lastKnownIndex = safeInitial;
    _pageController = PageController(initialPage: safeInitial);
    _isInteracting.addListener(_onInteractionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controllerDisposed) return;
      final playerCubit = context.read<PlayerCubit>();
      final state = playerCubit.state;
      final queue = state.queue.isNotEmpty
          ? state.queue
          : (state.currentSong != null ? [state.currentSong!] : const <SongsTableData>[]);
      final currentIndex =
          state.currentIndex.clamp(0, math.max(0, queue.length - 1)).toInt();
      _syncPageController(currentIndex, queue.length);
    });
  }

  void _onInteractionChanged() {
    if (!_isInteracting.value && mounted && !_controllerDisposed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _controllerDisposed) return;
        final cubit = context.read<PlayerCubit>();
        final state = cubit.state;
        final queue = state.queue.isNotEmpty
            ? state.queue
            : (state.currentSong != null ? [state.currentSong!] : const <SongsTableData>[]);
        if (queue.isNotEmpty) {
          final target = state.currentIndex.clamp(0, queue.length - 1);
          if (_pageController != null &&
              _pageController!.hasClients &&
              _pageController!.page?.round() != target) {
            _syncPageController(target, queue.length);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _controllerDisposed = true;
    _isInteracting.removeListener(_onInteractionChanged);
    _isInteracting.dispose();
    _verticalSwipeTimer?.cancel();
    _pageController?.dispose();
    _pageController = null;
    super.dispose();
  }

  void _syncPageController(int targetIndex, int queueLength) {
    if (_controllerDisposed || !mounted) return;
    try {
      final controller = _pageController;
      if (queueLength == 0 || controller == null || _controllerDisposed) return;
      final safeIndex = targetIndex.clamp(0, queueLength - 1);
      // Never fight an in-progress user gesture or in-flight skip.
      if (_isInteracting.value || _swipeInFlight) return;
      if (_lastKnownIndex != safeIndex) {
        if (!controller.hasClients || !controller.position.hasContentDimensions) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_controllerDisposed) {
              _syncPageController(targetIndex, queueLength);
            }
          });
          return;
        }
        if (controller.page?.round() != safeIndex) {
          try {
            final maxPage = controller.position.viewportDimension > 0
                ? (controller.position.maxScrollExtent / controller.position.viewportDimension).round()
                : queueLength - 1;
            if (safeIndex <= maxPage && !_controllerDisposed) {
              controller.jumpToPage(safeIndex);
              _lastKnownIndex = safeIndex;
            }
          } catch (e, st) {
            if (e is! FlutterError) {
              ErrorLogger.log('MiniPlayer PageController jumpToPage failed',
                  error: e, stackTrace: st, category: 'MiniPlayer');
            }
          }
        } else {
          _lastKnownIndex = safeIndex;
        }
      }
    } catch (e, st) {
      if (e is! FlutterError) {
        ErrorLogger.log('MiniPlayer PageController sync failed',
            error: e, stackTrace: st, category: 'MiniPlayer');
      }
    }
  }

  /// A swipe landed on [page]: skip to the new item and safely resync
  Future<void> _completeSwipe(int page, PlayerCubit cubit) async {
    try {
      await cubit.skipToQueueItem(page);
    } catch (e, st) {
      ErrorLogger.log('MiniPlayer swipe failed',
          error: e, stackTrace: st, category: 'MiniPlayer');
    } finally {
      if (mounted) {
        setState(() {
          _swipeInFlight = false;
        });
      }
    }
    // Schedule re-sync in post-frame callback so carousel state and layout
    // have settled, preventing desync or frame-gap jumps.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controllerDisposed) return;
      final synced = cubit.state;
      final syncedQueue = synced.queue.isNotEmpty
          ? synced.queue
          : (synced.currentSong != null ? [synced.currentSong!] : const <SongsTableData>[]);
      if (syncedQueue.isNotEmpty) {
        _syncPageController(
          synced.currentIndex.clamp(0, syncedQueue.length - 1).toInt(),
          syncedQueue.length,
        );
      }
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

    return BlocConsumer<PlayerCubit, PlayerState>(
      listenWhen: (a, b) =>
          a.currentIndex != b.currentIndex ||
          listContentDiffers(a.queue, b.queue),
      listener: (context, state) {
        if (!mounted || _controllerDisposed) return;
        final queue = state.queue.isNotEmpty
            ? state.queue
            : (state.currentSong != null ? [state.currentSong!] : const <SongsTableData>[]);
        final currentIndex =
            state.currentIndex.clamp(0, math.max(0, queue.length - 1)).toInt();
        _syncPageController(currentIndex, queue.length);
      },
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

        final isTablet = Adaptive.isTablet(context);
        final playerRadius = BorderRadius.circular(isTablet ? 28 : 24);

        // Screen readers cannot perform drag gestures, so expose the swipe
        // up/down actions as custom semantics actions (I9).
        final customSemanticsActions = <CustomSemanticsAction, VoidCallback>{
          CustomSemanticsAction(label: context.l10n.expandPlayer):
              widget.onSwipeUp ?? widget.onTap,
          if (widget.onSwipeDown != null)
            CustomSemanticsAction(label: context.l10n.dismissPlayer):
                widget.onSwipeDown!,
        };

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Semantics(
              label: context.l10n.nowPlayingSemantics(song.title, song.artist),
              button: true,
              customSemanticsActions: customSemanticsActions,
              child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) {
              if (_swipeInFlight) return;
              _verticalDragDy = 0.0;
            },
            onVerticalDragUpdate: (d) {
              if (_swipeInFlight) return;
              _verticalDragDy += d.delta.dy;
            },
            onVerticalDragEnd: (d) {
              if (_swipeInFlight) return;
              final vy = d.velocity.pixelsPerSecond.dy;
              if (_verticalDragDy > 25 || vy > 120) {
                _swipeInFlight = true;
                HapticFeedback.selectionClick();
                widget.onSwipeDown?.call();
                _verticalSwipeTimer?.cancel();
                _verticalSwipeTimer = Timer(const Duration(milliseconds: 500), () {
                  if (mounted) setState(() => _swipeInFlight = false);
                });
              } else if (_verticalDragDy < -25 || vy < -120) {
                _swipeInFlight = true;
                HapticFeedback.selectionClick();
                if (widget.onSwipeUp != null) {
                  widget.onSwipeUp!();
                } else {
                  widget.onTap();
                }
                _verticalSwipeTimer?.cancel();
                _verticalSwipeTimer = Timer(const Duration(milliseconds: 500), () {
                  if (mounted) setState(() => _swipeInFlight = false);
                });
              }
              _verticalDragDy = 0.0;
            },
            onHorizontalDragStart: carouselEnabled
                ? null
                : (_) {
                    if (_swipeInFlight) return;
                    _horizontalDragDx = 0.0;
                  },
            onHorizontalDragUpdate: carouselEnabled
                ? null
                : (d) {
                    if (_swipeInFlight) return;
                    _horizontalDragDx += d.delta.dx;
                  },
            onHorizontalDragEnd: carouselEnabled
                ? null
                : (d) {
                    if (_swipeInFlight) return;
                    final dx = _horizontalDragDx + d.velocity.pixelsPerSecond.dx * 0.05;
                    _horizontalDragDx = 0.0;
                    if (dx.abs() < 24) return;
                    final swipedLeft = dx < 0;
                    unawaited(_applySwipeAction(
                      swipedLeft ? swipeLeftAction : swipeRightAction,
                      cubit,
                      swipedLeft: swipedLeft,
                    ));
                  },
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                isTablet ? 24 : 14,
                0,
                isTablet ? 24 : 14,
                0,
              ),
              // Same glass recipe as the bottom navigation bar so the two dock
              // cards read as one surface family.
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: playerRadius,
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: p.isDark ? 0.40 : 0.12),
                      blurRadius: 24,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color:
                          p.accent.withValues(alpha: p.isDark ? 0.10 : 0.05),
                      blurRadius: 18,
                      spreadRadius: -2,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: playerRadius,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: playerRadius,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            p.surface
                                .withValues(alpha: p.isDark ? 0.78 : 0.88),
                            p.surfaceContainer
                                .withValues(alpha: p.isDark ? 0.72 : 0.84),
                          ],
                        ),
                        border: Border.all(
                          color: p.isDark
                              ? Colors.white.withValues(alpha: 0.14)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 1.2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: playerRadius,
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s10, AppSpacing.xs, AppSpacing.xs, 0),
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
                                          _isInteracting.value = true;
                                        } else if (notification is UserScrollNotification) {
                                          if (notification.direction != ScrollDirection.idle) {
                                            _isInteracting.value = true;
                                          } else if (!_swipeInFlight) {
                                            _isInteracting.value = false;
                                          }
                                        } else if (notification is ScrollEndNotification) {
                                          if (!_swipeInFlight) {
                                            _isInteracting.value = false;
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
                                          if (!_swipeInFlight &&
                                              _isInteracting.value &&
                                              page != currentIndex) {
                                            _lastKnownIndex = page;
                                            _swipeInFlight = true;
                                            unawaited(_completeSwipe(page, cubit));
                                          }
                                        },
                                       itemBuilder: (context, index) {
                                        final item = queue[index];
                                        final isCurrent = index == currentIndex;

                                        return RepaintBoundary(
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: widget.onTap,
                                            child: Row(
                                            children: [
                                              // Artwork or Vinyl Disc
                                              Stack(
                                                alignment: Alignment.center,
                                                children: [
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
                                                  if (isCurrent && state.isPlaying && playerThemeMode != PlayerThemeMode.vinyl)
                                                    PositionedDirectional(
                                                      bottom: 2,
                                                      end: 2,
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.black.withValues(alpha: 0.65),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: WaveformLogo(
                                                          size: 11,
                                                          color: p.accent,
                                                          animate: true,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(width: AppSpacing.sm),
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
                                                          fontSize: AppFontSize.body,
                                                        ),
                                                      ),
                                                      const SizedBox(height: AppSpacing.s2),
                                                      Text(
                                                        item.artist,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          color: p.textSecondary,
                                                          fontSize: AppFontSize.label,
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
                                           ),
                                         );
                                       },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.s6),
                                // Controls
                                IconButton(
                                  tooltip: state.isPlaying
                                      ? context.l10n.pause
                                      : context.l10n.play,
                                  icon: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    transitionBuilder: (child, anim) =>
                                        ScaleTransition(scale: anim, child: child),
                                    child: Icon(
                                      state.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      key: ValueKey<bool>(state.isPlaying),
                                      color: activeAccent,
                                      size: 32,
                                    ),
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
                        RepaintBoundary(
                          child: _MiniPlayerProgressBar(
                            duration: state.duration,
                            activeAccent: activeAccent,
                            hairlineColor: p.hairline,
                            isPlaying: state.isPlaying,
                            onSeek: (pos) => cubit.seek(pos),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 2.5,
                      child: IgnorePointer(
                        child: Container(
                          width: 28,
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: (p.isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(1.5),
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
          ),
        ),
      ),
    ),
    PositionedDirectional(
          top: -38,
          start: 16,
          end: 16,
          child: GestureHintOverlay(
            hintKey: 'mini_player_swipe',
            message: context.l10n.miniPlayerSwipeHint,
            padding: EdgeInsets.zero,
            icon: Icons.swipe_rounded,
          ),
        ),
      ],
    );
      },
    );
  }
}

class _MiniPlayerProgressBar extends StatefulWidget {
  final Duration duration;
  final Color activeAccent;
  final Color hairlineColor;
  final bool isPlaying;
  final void Function(Duration) onSeek;

  const _MiniPlayerProgressBar({
    required this.duration,
    required this.activeAccent,
    required this.hairlineColor,
    required this.isPlaying,
    required this.onSeek,
  });

  @override
  State<_MiniPlayerProgressBar> createState() => _MiniPlayerProgressBarState();
}

class _MiniPlayerProgressBarState extends State<_MiniPlayerProgressBar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  double? _dragProgress;
  bool _isAppActive = true;
  late final AnimationController _waveController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _isAppActive = false;
      _waveController.stop();
    } else {
      _isAppActive = true;
      _syncWave();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _waveController.duration = context.motionMs(2600);
    _syncWave();
  }

  void _syncWave() {
    final isTest = const bool.fromEnvironment('FLUTTER_TEST') ||
        (WidgetsBinding.instance is! WidgetsFlutterBinding);
    final shouldAnimate = _isAppActive &&
        widget.isPlaying &&
        context.motionEnabled &&
        !isTest;
    if (shouldAnimate) {
      if (!_waveController.isAnimating) _waveController.repeat();
    } else if (_waveController.isAnimating) {
      _waveController.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _MiniPlayerProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) _syncWave();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Directionality(
        textDirection: Directionality.of(context),
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
                      HapticFeedback.selectionClick();
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
                      HapticFeedback.selectionClick();
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
                  // Generous hit area so the thin wavy bar is easy to grab; the
                  // wave amplitude stays small so the card never grows.
                  child: SizedBox(
                    height: AppSpacing.lg,
                    width: double.infinity,
                    child: AnimatedBuilder(
                      animation: _waveController,
                      builder: (context, _) => Stack(
                        clipBehavior: Clip.none,
                        alignment: AlignmentDirectional.centerStart,
                        children: [
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _MiniProgressWavePainter(
                                  progress: progress,
                                  phase: _waveController.value * 2 * math.pi,
                                  activeColor: widget.activeAccent,
                                  inactiveColor: widget.hairlineColor
                                      .withValues(alpha: 0.35),
                                  isPlaying: widget.isPlaying,
                                ),
                              ),
                            ),
                          ),
                        // Scrub thumb, shown while dragging.
                        if (_dragProgress != null)
                          Align(
                            alignment: Alignment(
                                (progress * 2 - 1).clamp(-0.94, 0.94), 0),
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: widget.activeAccent,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: widget.activeAccent
                                        .withValues(alpha: 0.5),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            },
          );
        },
      ),
    ),
  );
}
}


/// Draws the mini-player progress as the app's signature animated wave:
/// a thin inactive remainder plus a sine-enveloped active line with a soft glow,
/// matched to [PulsrSlider] so the mini player and seek bar feel like one system.
class _MiniProgressWavePainter extends CustomPainter {
  final double progress;
  final double phase;
  final Color activeColor;
  final Color inactiveColor;
  final bool isPlaying;

  _MiniProgressWavePainter({
    required this.progress,
    required this.phase,
    required this.activeColor,
    required this.inactiveColor,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const trackHeight = 3.0;
    final endX = (progress * size.width).clamp(0.0, size.width);

    if (endX < size.width) {
      final inactivePaint = Paint()
        ..color = inactiveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackHeight
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(endX, centerY), Offset(size.width, centerY), inactivePaint);
    }
    if (endX <= 0.5) return;

    // Sine-enveloped wave so it leaves/returns to the centerline cleanly.
    final amplitude = isPlaying ? 2.0 : 0.0;
    const wavelength = 16.0;
    const fade = 10.0;
    const step = 2.0;
    final wavePath = Path()..moveTo(0, centerY);
    for (double x = 0; x <= endX; x += step) {
      double env = 1.0;
      if (x < fade) {
        env = x / fade;
      } else if (endX - x < fade) {
        env = ((endX - x) / fade).clamp(0.0, 1.0);
      }
      final y = centerY +
          amplitude * env * math.sin((x / wavelength) * 2 * math.pi - phase);
      wavePath.lineTo(x, y);
    }
    wavePath.lineTo(endX, centerY);

    final glowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackHeight + 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawPath(wavePath, glowPaint);

    final activePaint = Paint()
      ..shader = LinearGradient(
        colors: [activeColor.withValues(alpha: 0.75), activeColor],
      ).createShader(Rect.fromLTRB(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackHeight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(wavePath, activePaint);
  }

  @override
  bool shouldRepaint(covariant _MiniProgressWavePainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.isPlaying != isPlaying;
}
