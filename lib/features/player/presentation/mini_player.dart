import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../core/motion/pulsr_motion.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/list_content_diff.dart';
import '../../../core/utils/pulsr_haptics.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/gesture_hint_overlay.dart';
import '../../../core/widgets/marquee_text.dart';
import '../../../core/widgets/spinning_vinyl_disc.dart';
import '../../../core/widgets/waveform_logo.dart';
import '../../../data/db/app_database.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'themes/player_theme.dart';
import 'widgets/tablet_player_bar.dart';

enum MiniPlayerVariant { auto, compact, horizontal, tablet }

class MiniPlayer extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onSwipeDown;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onLongPress;

  const MiniPlayer({
    super.key,
    required this.onTap,
    this.onSwipeDown,
    this.onSwipeUp,
    this.onLongPress,
  });

  @override
  State<MiniPlayer> createState() => MiniPlayerState();
}

class MiniPlayerState extends State<MiniPlayer> {
  PageController? _pageController;
  bool _controllerDisposed = false;
  int? _pendingSyncIndex;
  int? _pendingQueueLength;
  bool _hasPendingPostFrameSync = false;
  final ValueNotifier<bool> _isInteracting = ValueNotifier<bool>(false);
  @visibleForTesting
  ValueNotifier<bool> get isInteractingNotifier => _isInteracting;
  bool _swipeInFlight = false;

  /// Bounded post-frame retries while the PageView catches up with a queue
  /// whose length just changed. Each retry costs one frame.
  int _pageSyncRetries = 0;
  static const int _maxPageSyncRetries = 4;

  /// Invalidates post-frame retries belonging to an older sync request, so a
  /// rapid skip burst can never drag the carousel back to a previous track.
  int _pageSyncGeneration = 0;

  /// Upper bound for a swipe-triggered transport call. A hung skip used to
  /// leave [_swipeInFlight] set forever, which stopped every later carousel
  /// sync until the app was restarted.
  static const Duration _swipeLatchTimeout = Duration(seconds: 10);
  Timer? _verticalSwipeTimer;
  double _verticalDragDy = 0.0;
  double _horizontalDragDx = 0.0;
  bool _swipeThresholdCrossed = false;
  // AUDIT-FIX: Throttle retry taps on error pill
  DateTime? _lastRetryTime;

  /// The Hero tag used by the full-screen artwork for the active theme, so the
  /// mini -> full shared-element transition actually runs (tags must match).
  String _fullArtworkHeroTag(PlayerThemeMode mode) =>
      nowPlayingArtHeroTag(mode);

  IconData? _iconForSwipeAction(
    MiniPlayerSwipeAction action, {
    required bool swipedLeft,
  }) {
    switch (action) {
      case MiniPlayerSwipeAction.next:
        return Icons.skip_next_rounded;
      case MiniPlayerSwipeAction.prev:
        return Icons.skip_previous_rounded;
      case MiniPlayerSwipeAction.volume:
        return swipedLeft
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;
      case MiniPlayerSwipeAction.none:
        return null;
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
    if (_swipeInFlight || action == MiniPlayerSwipeAction.none) return;
    _swipeInFlight = true;
    try {
      // A transport call that never completes must not latch [_swipeInFlight]
      // and freeze the carousel for the rest of the session.
      switch (action) {
        case MiniPlayerSwipeAction.next:
          PulsrHaptics.selectionClick();
          await cubit.next().timeout(_swipeLatchTimeout);
          break;
        case MiniPlayerSwipeAction.prev:
          PulsrHaptics.selectionClick();
          await cubit.previous().timeout(_swipeLatchTimeout);
          break;
        case MiniPlayerSwipeAction.volume:
          PulsrHaptics.selectionClick();
          await cubit
              .adjustVolume(swipedLeft ? -0.05 : 0.05)
              .timeout(_swipeLatchTimeout);
          break;
        case MiniPlayerSwipeAction.none:
          break;
      }
    } on TimeoutException catch (e, st) {
      ErrorLogger.log('MiniPlayer swipe action timed out',
          error: e, stackTrace: st, category: 'MiniPlayer');
    } catch (e, st) {
      ErrorLogger.log('MiniPlayer swipe action failed',
          error: e, stackTrace: st, category: 'MiniPlayer');
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
    _pageController = PageController(initialPage: safeInitial);
    _isInteracting.addListener(_onInteractionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controllerDisposed) return;
      final playerCubit = context.read<PlayerCubit>();
      final state = playerCubit.state;
      final queue = state.queue.isNotEmpty
          ? state.queue
          : (state.currentSong != null
              ? [state.currentSong!]
              : const <SongsTableData>[]);
      final currentIndex =
          state.currentIndex.clamp(0, math.max(0, queue.length - 1)).toInt();
      _syncPageController(currentIndex, queue.length);
    });
  }

  void _onInteractionChanged() {
    if (!_isInteracting.value && mounted && !_controllerDisposed) {
      _drainPendingSync();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _controllerDisposed) return;
        final cubit = context.read<PlayerCubit>();
        final state = cubit.state;
        final queue = state.queue.isNotEmpty
            ? state.queue
            : (state.currentSong != null
                ? [state.currentSong!]
                : const <SongsTableData>[]);
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
    _pendingSyncIndex = null;
    _pendingQueueLength = null;
    _pageSyncRetries = 0;
    _isInteracting.removeListener(_onInteractionChanged);
    _isInteracting.dispose();
    _verticalSwipeTimer?.cancel();
    _pageController?.dispose();
    _pageController = null;
    super.dispose();
  }

  void _drainPendingSync() {
    if (_controllerDisposed || !mounted) return;
    final target = _pendingSyncIndex;
    final qLen = _pendingQueueLength;
    if (target == null || qLen == null) return;
    final controller = _pageController;
    if (controller != null &&
        controller.hasClients &&
        controller.position.hasContentDimensions) {
      _pendingSyncIndex = null;
      _pendingQueueLength = null;
      _syncPageController(target, qLen);
    }
  }

  void _schedulePostFrameSync() {
    if (_hasPendingPostFrameSync || _controllerDisposed || !mounted) return;
    _hasPendingPostFrameSync = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasPendingPostFrameSync = false;
      if (!mounted || _controllerDisposed) return;
      _drainPendingSync();
    });
  }

  void _syncPageController(int targetIndex, int queueLength) {
    if (_controllerDisposed || !mounted) return;
    final generation = ++_pageSyncGeneration;
    try {
      final controller = _pageController;
      if (queueLength == 0 || controller == null || _controllerDisposed) {
        _pageSyncRetries = 0;
        return;
      }
      final safeIndex = targetIndex.clamp(0, queueLength - 1);
      // Never fight an in-progress user gesture or in-flight skip.
      if (_isInteracting.value || _swipeInFlight) {
        _pageSyncRetries = 0;
        _pendingSyncIndex = safeIndex;
        _pendingQueueLength = queueLength;
        return;
      }
      if (!controller.hasClients || !controller.position.hasContentDimensions) {
        _pendingSyncIndex = safeIndex;
        _pendingQueueLength = queueLength;
        _schedulePostFrameSync();
        return;
      }
      final currentPage = controller.page?.round();

      if (currentPage == safeIndex) {
        _pageSyncRetries = 0;
        _pendingSyncIndex = null;
        _pendingQueueLength = null;
        return;
      }

      _pendingSyncIndex = null;
      _pendingQueueLength = null;

      try {
        if (!_controllerDisposed) {
          controller.jumpToPage(safeIndex);
        }
      } catch (e, st) {
        if (e is! FlutterError) {
          ErrorLogger.log('MiniPlayer PageController jumpToPage failed',
              error: e, stackTrace: st, category: 'MiniPlayer');
        }
      }
      _verifyPageSync(safeIndex, queueLength, generation);
    } catch (e, st) {
      if (e is! FlutterError) {
        ErrorLogger.log('MiniPlayer PageController sync failed',
            error: e, stackTrace: st, category: 'MiniPlayer');
      }
    }
  }

  /// Confirms a carousel jump survived layout and retries a bounded number of
  /// frames otherwise.
  void _verifyPageSync(int targetIndex, int queueLength, int generation) {
    if (_controllerDisposed || !mounted) return;
    if (_pageSyncRetries >= _maxPageSyncRetries) {
      _pageSyncRetries = 0;
      return;
    }
    _pageSyncRetries++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controllerDisposed) return;
      if (generation != _pageSyncGeneration) return;
      final controller = _pageController;
      if (controller == null || !controller.hasClients) return;
      if (controller.page?.round() == targetIndex) {
        _pageSyncRetries = 0;
        return;
      }
      _syncPageController(targetIndex, queueLength);
    });
  }

  /// A swipe landed on [page]: skip to the new item and safely resync
  Future<void> _completeSwipe(int page, PlayerCubit cubit) async {
    try {
      await cubit.skipToQueueItem(page).timeout(_swipeLatchTimeout);
    } on TimeoutException catch (e, st) {
      ErrorLogger.log('MiniPlayer swipe skip timed out',
          error: e, stackTrace: st, category: 'MiniPlayer');
    } catch (e, st) {
      ErrorLogger.log('MiniPlayer swipe failed',
          error: e, stackTrace: st, category: 'MiniPlayer');
    } finally {
      if (!_controllerDisposed) {
        _isInteracting.value = false;
      }
      if (mounted) {
        setState(() {
          _swipeInFlight = false;
        });
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controllerDisposed) return;
      final synced = cubit.state;
      final syncedQueue = synced.queue.isNotEmpty
          ? synced.queue
          : (synced.currentSong != null
              ? [synced.currentSong!]
              : const <SongsTableData>[]);
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
    if (_pendingSyncIndex != null) {
      _schedulePostFrameSync();
    }
    // Ensure the PageView is synced to the active track after build/layout
    final playerState = context.read<PlayerCubit>().state;
    final currentQ = playerState.queue.isNotEmpty
        ? playerState.queue
        : (playerState.currentSong != null
            ? [playerState.currentSong!]
            : const <SongsTableData>[]);
    if (currentQ.isNotEmpty) {
      final targetIdx =
          playerState.currentIndex.clamp(0, currentQ.length - 1).toInt();
      final ctrl = _pageController;
      if (ctrl != null &&
          ctrl.hasClients &&
          !_isInteracting.value &&
          !_swipeInFlight) {
        final curPage = ctrl.page?.round();
        if (curPage != null && curPage != targetIdx) {
          _pendingSyncIndex = targetIdx;
          _pendingQueueLength = currentQ.length;
          _schedulePostFrameSync();
        }
      }
    }

    // Narrow subscription: only the vinyl theme decision is read here, so an
    // unrelated settings change must not rebuild the mini player (A-11).
    final playerThemeMode = context
        .select<SettingsCubit, PlayerThemeMode>((c) => c.state.playerThemeMode);
    // Mini-player swipe actions are user-configurable; the queue carousel can
    // only natively express the next/prev mapping.
    final swipeLeftAction =
        context.select<SettingsCubit, MiniPlayerSwipeAction>(
            (c) => c.state.miniPlayerSwipeLeft);
    final swipeRightAction =
        context.select<SettingsCubit, MiniPlayerSwipeAction>(
            (c) => c.state.miniPlayerSwipeRight);
    final carouselEnabled = swipeLeftAction == MiniPlayerSwipeAction.next &&
        swipeRightAction == MiniPlayerSwipeAction.prev;
    final p = context.palette;

    final content = BlocConsumer<PlayerCubit, PlayerState>(
      listenWhen: (a, b) =>
          a.currentIndex != b.currentIndex ||
          a.currentSong?.id != b.currentSong?.id ||
          listContentDiffers(a.queue, b.queue),
      listener: (context, state) {
        if (!mounted || _controllerDisposed) return;
        final queue = state.queue.isNotEmpty
            ? state.queue
            : (state.currentSong != null
                ? [state.currentSong!]
                : const <SongsTableData>[]);
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
          a.isBuffering != b.isBuffering ||
          a.errorMessage != b.errorMessage ||
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
        final playerRadius = isTablet ? AppRadii.r28All : AppRadii.r24All;

        // Screen readers cannot perform drag gestures, so expose the swipe
        // up/down actions as custom semantics actions (I9).
        final customSemanticsActions = <CustomSemanticsAction, VoidCallback>{
          CustomSemanticsAction(label: context.l10n.expandPlayer):
              widget.onSwipeUp ?? widget.onTap,
          if (widget.onSwipeDown != null)
            CustomSemanticsAction(label: context.l10n.dismissPlayer):
                widget.onSwipeDown!,
        };

        final swipeLeftIcon =
            _iconForSwipeAction(swipeLeftAction, swipedLeft: true);
        final swipeRightIcon =
            _iconForSwipeAction(swipeRightAction, swipedLeft: false);

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
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
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
                  if ((_verticalDragDy > 25 || vy > 120) &&
                      _verticalDragDy >= 0 &&
                      vy >= 0) {
                    _swipeInFlight = true;
                    PulsrHaptics.selectionClick();
                    widget.onSwipeDown?.call();
                    _verticalSwipeTimer?.cancel();
                    _verticalSwipeTimer =
                        Timer(const Duration(milliseconds: 500), () {
                      if (mounted) setState(() => _swipeInFlight = false);
                    });
                  } else if ((_verticalDragDy < -25 || vy < -120) &&
                      _verticalDragDy <= 0 &&
                      vy <= 0) {
                    _swipeInFlight = true;
                    PulsrHaptics.selectionClick();
                    if (widget.onSwipeUp != null) {
                      widget.onSwipeUp!();
                    } else {
                      widget.onTap();
                    }
                    _verticalSwipeTimer?.cancel();
                    _verticalSwipeTimer =
                        Timer(const Duration(milliseconds: 500), () {
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
                        _swipeThresholdCrossed = false;
                        setState(() {});
                      },
                onHorizontalDragUpdate: carouselEnabled
                    ? null
                    : (d) {
                        if (_swipeInFlight) return;
                        _horizontalDragDx += d.delta.dx;
                        const threshold = 40.0;
                        if (!_swipeThresholdCrossed &&
                            _horizontalDragDx.abs() >= threshold) {
                          _swipeThresholdCrossed = true;
                          PulsrHaptics.confirm();
                        } else if (_swipeThresholdCrossed &&
                            _horizontalDragDx.abs() < threshold) {
                          _swipeThresholdCrossed = false;
                        }
                        setState(() {});
                      },
                onHorizontalDragEnd: carouselEnabled
                    ? null
                    : (d) {
                        if (_swipeInFlight) return;
                        final dx = _horizontalDragDx +
                            d.velocity.pixelsPerSecond.dx * 0.05;
                        _horizontalDragDx = 0.0;
                        _swipeThresholdCrossed = false;
                        setState(() {});
                        if (dx.abs() < 24) return;
                        final swipedLeft = dx < 0;
                        unawaited(_applySwipeAction(
                          swipedLeft ? swipeLeftAction : swipeRightAction,
                          cubit,
                          swipedLeft: swipedLeft,
                        ));
                      },
                onHorizontalDragCancel: carouselEnabled
                    ? null
                    : () {
                        if (_horizontalDragDx != 0.0) {
                          setState(() {
                            _horizontalDragDx = 0.0;
                            _swipeThresholdCrossed = false;
                          });
                        }
                      },
                child: Padding(
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
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: p.isDark ? 0.42 : 0.10),
                          blurRadius: 22,
                          spreadRadius: -2,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: activeAccent
                              .withValues(alpha: p.isDark ? 0.08 : 0.04),
                          blurRadius: 16,
                          spreadRadius: -4,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: playerRadius,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: playerRadius,
                          gradient: LinearGradient(
                            begin: AlignmentDirectional.centerStart,
                            end: AlignmentDirectional.centerEnd,
                            colors: [
                              Color.alphaBlend(
                                activeAccent.withValues(
                                    alpha: p.isDark ? 0.09 : 0.06),
                                p.surfaceContainerHigh,
                              ),
                              p.surfaceContainer,
                            ],
                            stops: const [0.0, 0.68],
                          ),
                          border: Border.all(
                            color: p.hairline,
                            width: 1.0,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            // Subtle top inner specular highlight
                            PositionedDirectional(
                              top: 0,
                              start: 20,
                              end: 20,
                              child: IgnorePointer(
                                child: Container(
                                  height: 1,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0.0),
                                        (p.isDark ? Colors.white : Colors.black)
                                            .withValues(
                                                alpha: p.isDark ? 0.12 : 0.04),
                                        Colors.white.withValues(alpha: 0.0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsetsDirectional.fromSTEB(
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
                                          height: 52 *
                                              MediaQuery.textScalerOf(context)
                                                  .scale(1.0)
                                                  .clamp(1.0, 1.5),
                                          child: NotificationListener<
                                              ScrollNotification>(
                                            onNotification: (notification) {
                                              if (notification
                                                      is ScrollStartNotification &&
                                                  notification.dragDetails !=
                                                      null) {
                                                _isInteracting.value = true;
                                              } else if (notification
                                                  is UserScrollNotification) {
                                                if (notification.direction !=
                                                    ScrollDirection.idle) {
                                                  _isInteracting.value = true;
                                                } else if (!_swipeInFlight) {
                                                  _isInteracting.value = false;
                                                }
                                              } else if (notification
                                                  is ScrollEndNotification) {
                                                _isInteracting.value = false;
                                                if (!_swipeInFlight) {
                                                  _drainPendingSync();
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
                                                  if (mounted) {
                                                    setState(() {
                                                      _swipeInFlight = true;
                                                    });
                                                  } else {
                                                    _swipeInFlight = true;
                                                  }
                                                  unawaited(_completeSwipe(
                                                      page, cubit));
                                                }
                                              },
                                              itemBuilder: (context, index) {
                                                final item = queue[index];
                                                final isCurrent =
                                                    index == currentIndex;

                                                return RepaintBoundary(
                                                  child: GestureDetector(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onTap: widget.onTap,
                                                    child: Row(
                                                      children: [
                                                        // Artwork or Vinyl Disc
                                                        Stack(
                                                          alignment:
                                                              Alignment.center,
                                                          children: [
                                                            if (playerThemeMode ==
                                                                PlayerThemeMode
                                                                    .vinyl)
                                                              SpinningVinylDisc(
                                                                id: item.id,
                                                                remoteArtworkUrl:
                                                                    item.remoteArtworkUrl,
                                                                size: 46,
                                                                isPlaying: state
                                                                        .isPlaying &&
                                                                    isCurrent,
                                                              )
                                                            else
                                                              Container(
                                                                decoration:
                                                                    BoxDecoration(
                                                                  borderRadius:
                                                                      AppRadii
                                                                          .r12All,
                                                                  border:
                                                                      Border.all(
                                                                    color: p
                                                                        .hairline,
                                                                    width: 0.75,
                                                                  ),
                                                                  boxShadow: [
                                                                    BoxShadow(
                                                                      color: Colors
                                                                          .black
                                                                          .withValues(
                                                                              alpha: p.isDark ? 0.30 : 0.10),
                                                                      blurRadius:
                                                                          8,
                                                                      offset:
                                                                          const Offset(
                                                                              0,
                                                                              2),
                                                                    ),
                                                                  ],
                                                                ),
                                                                child: Hero(
                                                                  tag: isCurrent
                                                                      ? _fullArtworkHeroTag(
                                                                          playerThemeMode)
                                                                      : 'queue_art_${item.id}_$index',
                                                                  child:
                                                                      CachedArtwork(
                                                                    id: item.id,
                                                                    remoteUrl: item
                                                                        .remoteArtworkUrl,
                                                                    type: ArtworkType
                                                                        .AUDIO,
                                                                    size: 46,
                                                                    borderRadius:
                                                                        12,
                                                                  ),
                                                                ),
                                                              ),
                                                            if (isCurrent &&
                                                                state
                                                                    .isPlaying &&
                                                                playerThemeMode !=
                                                                    PlayerThemeMode
                                                                        .vinyl)
                                                              PositionedDirectional(
                                                                bottom: 2,
                                                                end: 2,
                                                                child:
                                                                    Container(
                                                                  padding:
                                                                      const EdgeInsets
                                                                          .symmetric(
                                                                    horizontal:
                                                                        3.5,
                                                                    vertical:
                                                                        2.0,
                                                                  ),
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: AppColors
                                                                        .scrim,
                                                                    borderRadius:
                                                                        AppRadii
                                                                            .r4All,
                                                                    border: Border
                                                                        .all(
                                                                      color: Colors
                                                                          .white
                                                                          .withValues(
                                                                              alpha: 0.14),
                                                                      width:
                                                                          0.5,
                                                                    ),
                                                                  ),
                                                                  child:
                                                                      WaveformLogo(
                                                                    size: 11,
                                                                    color: p
                                                                        .accent,
                                                                    animate:
                                                                        true,
                                                                  ),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            width:
                                                                AppSpacing.sm),
                                                        // Track title & artist.
                                                        Expanded(
                                                          child: Stack(
                                                            alignment:
                                                                AlignmentDirectional
                                                                    .centerStart,
                                                            children: [
                                                              Transform
                                                                  .translate(
                                                                offset: Offset(
                                                                  _horizontalDragDx !=
                                                                          0.0
                                                                      ? math.pow(_horizontalDragDx.abs(), 0.78) *
                                                                          _horizontalDragDx
                                                                              .sign
                                                                      : 0.0,
                                                                  0,
                                                                ),
                                                                child: MediaQuery
                                                                    .withClampedTextScaling(
                                                                  minScaleFactor:
                                                                      0.8,
                                                                  maxScaleFactor:
                                                                      2.0,
                                                                  child: Column(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .center,
                                                                    children: [
                                                                      Text(
                                                                        item.title,
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style:
                                                                            TextStyle(
                                                                          color: isCurrent
                                                                              ? p.textPrimary
                                                                              : p.textSecondary,
                                                                          fontWeight:
                                                                              FontWeight.w700,
                                                                          fontSize:
                                                                              AppFontSize.body,
                                                                          letterSpacing:
                                                                              -0.2,
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                          height:
                                                                              AppSpacing.s2),
                                                                      Text(
                                                                        item.artist,
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style:
                                                                            TextStyle(
                                                                          color:
                                                                              p.textSecondary,
                                                                          fontSize:
                                                                              AppFontSize.label,
                                                                          fontWeight:
                                                                              FontWeight.w500,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ),
                                                              if (_horizontalDragDx <
                                                                      -8 &&
                                                                  swipeLeftIcon !=
                                                                      null)
                                                                PositionedDirectional(
                                                                  end: 0,
                                                                  child:
                                                                      _SwipeActionBadge(
                                                                    icon:
                                                                        swipeLeftIcon,
                                                                    progress: (_horizontalDragDx.abs() /
                                                                            40.0)
                                                                        .clamp(
                                                                            0.0,
                                                                            1.0),
                                                                    thresholdCrossed:
                                                                        _swipeThresholdCrossed,
                                                                    accentColor:
                                                                        activeAccent,
                                                                  ),
                                                                )
                                                              else if (_horizontalDragDx >
                                                                      8 &&
                                                                  swipeRightIcon !=
                                                                      null)
                                                                PositionedDirectional(
                                                                  start: 0,
                                                                  child:
                                                                      _SwipeActionBadge(
                                                                    icon:
                                                                        swipeRightIcon,
                                                                    progress: (_horizontalDragDx.abs() /
                                                                            40.0)
                                                                        .clamp(
                                                                            0.0,
                                                                            1.0),
                                                                    thresholdCrossed:
                                                                        _swipeThresholdCrossed,
                                                                    accentColor:
                                                                        activeAccent,
                                                                  ),
                                                                ),
                                                            ],
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
                                      const SizedBox(width: AppSpacing.xs),
                                      // Primary Play/Pause Button with tonal capsule
                                      Container(
                                        width: 40,
                                        height: 40,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 2),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: activeAccent.withValues(
                                            alpha: p.isDark ? 0.14 : 0.10,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth:
                                                AppSpacing.minTouchTarget,
                                            minHeight:
                                                AppSpacing.minTouchTarget,
                                          ),
                                          tooltip: state.isPlaying
                                              ? context.l10n.pause
                                              : context.l10n.play,
                                          icon: AnimatedSwitcher(
                                            duration: context
                                                .motion(PulsrMotion.state),
                                            transitionBuilder: (child, anim) =>
                                                ScaleTransition(
                                              scale: anim,
                                              child: child,
                                            ),
                                            child: state.isBuffering
                                                ? SizedBox(
                                                    key: const ValueKey<String>(
                                                        'buffering'),
                                                    width: 22,
                                                    height: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2.3,
                                                      color: activeAccent,
                                                    ),
                                                  )
                                                : Icon(
                                                    state.isPlaying
                                                        ? Icons.pause_rounded
                                                        : Icons
                                                            .play_arrow_rounded,
                                                    key: ValueKey<bool>(
                                                        state.isPlaying),
                                                    color: activeAccent,
                                                    size: 28,
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
                                              : p.textTertiary
                                                  .withValues(alpha: 0.38),
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
                                  child: _MiniPlayerProgressBar(
                                    duration: state.duration,
                                    activeAccent: activeAccent,
                                    hairlineColor: p.textTertiary.withValues(
                                        alpha: p.isDark ? 0.45 : 0.35),
                                    isPlaying: state.isPlaying,
                                    isBuffering: state.isBuffering,
                                    onSeek: (pos) => cubit.seek(pos),
                                  ),
                                ),
                              ],
                            ),
                            // Top grab handle pill
                            Positioned(
                              top: 4.5,
                              child: IgnorePointer(
                                child: AnimatedContainer(
                                  duration: context.motion(PulsrMotion.state),
                                  width: _swipeInFlight ? 34 : 28,
                                  height: 3.0,
                                  decoration: BoxDecoration(
                                    color:
                                        (p.isDark ? Colors.white : Colors.black)
                                            .withValues(alpha: 0.20),
                                    borderRadius: AppRadii.r1_5All,
                                  ),
                                ),
                              ),
                            ),
                            if (state.errorMessage != null)
                              PositionedDirectional(
                                top: 5,
                                start: 6,
                                end: 6,
                                child: _MiniPlayerErrorBar(
                                  message: state.errorMessage!,
                                  accentColor: activeAccent,
                                  onRetry: () {
                                    // AUDIT-FIX: Cooldown to avoid rapid repeated retries on error pill
                                    final now = DateTime.now();
                                    if (_lastRetryTime != null &&
                                        now
                                                .difference(_lastRetryTime!)
                                                .inMilliseconds <
                                            1000) {
                                      return;
                                    }
                                    _lastRetryTime = now;
                                    PulsrHaptics.lightImpact();
                                    cubit.playSong(
                                      song,
                                      queue: queue,
                                      initialPosition: state.position,
                                    );
                                  },
                                  onDismiss: cubit.clearError,
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
            PositionedDirectional(
              top: -48,
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

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: context.motion(PulsrMotion.state),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
      child: content,
    );
  }
}

class _SwipeActionBadge extends StatelessWidget {
  final IconData icon;
  final double progress;
  final bool thresholdCrossed;
  final Color accentColor;

  const _SwipeActionBadge({
    required this.icon,
    required this.progress,
    required this.thresholdCrossed,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Opacity(
      opacity: progress,
      child: Transform.scale(
        scale: thresholdCrossed ? 1.12 : 0.92,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: thresholdCrossed
                ? accentColor.withValues(alpha: 0.18)
                : p.surfaceContainerHigh.withValues(alpha: 0.85),
            border: Border.all(
              color: thresholdCrossed
                  ? accentColor.withValues(alpha: 0.45)
                  : p.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 17,
            color: thresholdCrossed ? accentColor : p.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerProgressBar extends StatefulWidget {
  final Duration duration;
  final Color activeAccent;
  final Color hairlineColor;
  final bool isPlaying;
  final bool isBuffering;
  final void Function(Duration) onSeek;

  const _MiniPlayerProgressBar({
    required this.duration,
    required this.activeAccent,
    required this.hairlineColor,
    required this.isPlaying,
    this.isBuffering = false,
    required this.onSeek,
  });

  @override
  State<_MiniPlayerProgressBar> createState() => _MiniPlayerProgressBarState();
}

class _MiniPlayerProgressBarState extends State<_MiniPlayerProgressBar>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  double? _dragProgress;
  // AUDIT-FIX: Monotonic stopwatch clock for optimistic seek timing
  final Stopwatch _optimisticClock = Stopwatch();
  Duration? _optimisticSeekPosition;
  Duration? _optimisticSeekTime;
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
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    final shouldAnimate = _isAppActive &&
        widget.isPlaying &&
        !widget.isBuffering &&
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
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.isBuffering != widget.isBuffering) {
      _syncWave();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waveController.dispose();
    _optimisticClock.stop();
    super.dispose();
  }

  void _recordSeek(Duration target) {
    _optimisticSeekPosition = target;
    _optimisticClock.reset();
    _optimisticClock.start();
    _optimisticSeekTime = _optimisticClock.elapsed;
    widget.onSeek(target);
  }

  Duration _resolveEffectivePosition(Duration enginePosition) {
    if (_optimisticSeekPosition != null && _optimisticSeekTime != null) {
      final elapsed = _optimisticClock.elapsed;
      final diff = (enginePosition - _optimisticSeekPosition!).abs();
      if (elapsed.inMilliseconds < 350 && diff.inMilliseconds > 400) {
        return _optimisticSeekPosition!;
      } else {
        _optimisticSeekPosition = null;
        _optimisticSeekTime = null;
        _optimisticClock.stop();
      }
    }
    return enginePosition;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return RepaintBoundary(
      child: Directionality(
        textDirection: Directionality.of(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            return BlocSelector<PlayerCubit, PlayerState, Duration>(
              selector: (s) => s.position,
              builder: (context, rawPosition) {
                final position = _resolveEffectivePosition(rawPosition);
                final progress = _dragProgress ??
                    (widget.duration.inMilliseconds > 0
                        ? (position.inMilliseconds /
                                widget.duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0);
                final currentDuration = _dragProgress != null
                    ? Duration(
                        milliseconds:
                            (widget.duration.inMilliseconds * _dragProgress!)
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
                final increasedLabel = labelFor(clampDuration(
                    currentDuration + const Duration(seconds: 10)));
                final decreasedLabel = labelFor(clampDuration(
                    currentDuration - const Duration(seconds: 10)));

                final isDragging = _dragProgress != null;
                final thumbAlignX = (progress * 2 - 1).clamp(-0.94, 0.94);

                return Semantics(
                  slider: true,
                  label: context.l10n.seekLabel,
                  value: valueLabel,
                  increasedValue: increasedLabel,
                  decreasedValue: decreasedLabel,
                  onIncrease: widget.isBuffering
                      ? null
                      : () => _recordSeek(clampDuration(
                          currentDuration + const Duration(seconds: 10))),
                  onDecrease: widget.isBuffering
                      ? null
                      : () => _recordSeek(clampDuration(
                          currentDuration - const Duration(seconds: 10))),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: widget.isBuffering
                        ? null
                        : (details) {
                            if (trackWidth > 0 &&
                                widget.duration.inMilliseconds > 0) {
                              PulsrHaptics.selectionClick();
                              final ratio =
                                  (details.localPosition.dx / trackWidth)
                                      .clamp(0.0, 1.0);
                              setState(() => _dragProgress = null);
                              final seekMs =
                                  (widget.duration.inMilliseconds * ratio)
                                      .round();
                              _recordSeek(Duration(milliseconds: seekMs));
                            }
                          },
                    onHorizontalDragStart: widget.isBuffering
                        ? null
                        : (details) {
                            if (trackWidth > 0 &&
                                widget.duration.inMilliseconds > 0) {
                              PulsrHaptics.selectionClick();
                              final ratio =
                                  (details.localPosition.dx / trackWidth)
                                      .clamp(0.0, 1.0);
                              setState(() => _dragProgress = ratio);
                            }
                          },
                    onHorizontalDragUpdate: widget.isBuffering
                        ? null
                        : (details) {
                            if (trackWidth > 0 &&
                                widget.duration.inMilliseconds > 0) {
                              final ratio =
                                  (details.localPosition.dx / trackWidth)
                                      .clamp(0.0, 1.0);
                              setState(() => _dragProgress = ratio);
                            }
                          },
                    onHorizontalDragEnd: widget.isBuffering
                        ? null
                        : (_) {
                            if (_dragProgress != null &&
                                widget.duration.inMilliseconds > 0) {
                              final seekMs = (widget.duration.inMilliseconds *
                                      _dragProgress!)
                                  .round();
                              _recordSeek(Duration(milliseconds: seekMs));
                              setState(() => _dragProgress = null);
                            }
                          },
                    onHorizontalDragCancel: widget.isBuffering
                        ? null
                        : () {
                            setState(() => _dragProgress = null);
                          },
                    // Generous hit area so the thin wavy bar is easy to grab; the
                    // wave amplitude stays small so the card never grows.
                    child: SizedBox(
                      height: AppSpacing.s24,
                      width: double.infinity,
                      child: AnimatedBuilder(
                        animation: _waveController,
                        builder: (context, _) => Stack(
                          clipBehavior: Clip.none,
                          alignment: AlignmentDirectional.centerStart,
                          children: [
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.s10),
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    painter: _MiniProgressWavePainter(
                                      progress: progress,
                                      phase:
                                          _waveController.value * 2 * math.pi,
                                      activeColor: widget.activeAccent,
                                      inactiveColor: widget.hairlineColor,
                                      isPlaying: widget.isPlaying,
                                      isDragging: isDragging,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Scrub thumb & floating time readout while dragging
                            if (isDragging) ...[
                              PositionedDirectional(
                                top: -24,
                                start: 12,
                                end: 12,
                                child: Align(
                                  alignment: Alignment(
                                      thumbAlignX.clamp(-0.85, 0.85), 0),
                                  child: IgnorePointer(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: p.surfaceContainerHigh,
                                        borderRadius: AppRadii.r8All,
                                        border: Border.all(
                                          color: widget.activeAccent
                                              .withValues(alpha: 0.45),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.25),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        valueLabel,
                                        style: TextStyle(
                                          color: p.textPrimary,
                                          fontSize: AppFontSize.tiny,
                                          fontWeight: FontWeight.w700,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures()
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.s10),
                                child: Align(
                                  alignment: Alignment(thumbAlignX, 0),
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      color: widget.activeAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.85),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: widget.activeAccent
                                              .withValues(alpha: 0.55),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
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

/// Full-width error state for the mini player. It replaces the track row
/// instead of floating tiny 15px action icons over the controls, so retry and
/// dismiss both have a 48dp target.
class _MiniPlayerErrorBar extends StatelessWidget {
  final String message;
  final Color accentColor;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _MiniPlayerErrorBar({
    required this.message,
    required this.accentColor,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Material(
        color: Color.alphaBlend(
          p.error.withValues(alpha: p.isDark ? 0.12 : 0.08),
          p.surfaceContainerHigh,
        ),
        borderRadius: AppRadii.r18All,
        clipBehavior: Clip.antiAlias,
        child: Container(
          height: 52,
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.s10,
            end: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadii.r18All,
            border: Border.all(color: p.error.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.error.withValues(alpha: 0.16),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 17,
                  color: p.error,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              IconButton(
                tooltip: context.l10n.retry,
                onPressed: onRetry,
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                iconSize: 19,
                color: accentColor,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: context.l10n.close,
                onPressed: onDismiss,
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                iconSize: 19,
                color: p.textSecondary,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
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
  final bool isDragging;

  _MiniProgressWavePainter({
    required this.progress,
    required this.phase,
    required this.activeColor,
    required this.inactiveColor,
    required this.isPlaying,
    this.isDragging = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackHeight = isDragging ? 3.8 : 2.8;
    final endX = (progress * size.width).clamp(0.0, size.width);

    if (endX < size.width) {
      final inactivePaint = Paint()
        ..color = inactiveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDragging ? 3.0 : 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(endX, centerY), Offset(size.width, centerY), inactivePaint);
    }
    if (endX <= 0.5) return;

    // Sine-enveloped wave so it leaves/returns to the centerline cleanly.
    final amplitude = (isPlaying && !isDragging) ? 1.8 : 0.0;
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
      ..color = activeColor.withValues(alpha: isDragging ? 0.32 : 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackHeight + 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawPath(wavePath, glowPaint);

    final activePaint = Paint()
      ..shader = LinearGradient(
        colors: [activeColor.withValues(alpha: 0.78), activeColor],
      ).createShader(Rect.fromLTRB(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackHeight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(wavePath, activePaint);

    // Subtle radiant leading glow bead matching activeColor when playing.
    if (isPlaying && !isDragging && endX > 2.0 && endX <= size.width) {
      final beadCenter = Offset(endX, centerY);
      final haloPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawCircle(beadCenter, 4.0, haloPaint);

      final corePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(beadCenter, 2.5, corePaint);

      final specularPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.90)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(beadCenter, 1.0, specularPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniProgressWavePainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.isPlaying != isPlaying ||
      old.isDragging != isDragging;
}

/// Horizontal single-row mini player designed for landscape phones and medium breakpoint wide dock.
/// Height: 48dp, [artwork 40dp] [title • artist] [play/pause] [next]
class MiniPlayerHorizontal extends StatelessWidget {
  final VoidCallback onTap;

  const MiniPlayerHorizontal({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<PlayerCubit>();
    final activeAccent = p.accent;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.currentSong != curr.currentSong ||
          prev.isPlaying != curr.isPlaying ||
          prev.isBuffering != curr.isBuffering ||
          prev.duration != curr.duration,
      builder: (context, state) {
        final song = state.currentSong;
        if (song == null) return const SizedBox.shrink();

        return Semantics(
          label: '${song.title}, ${song.artist}',
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: AppRadii.r8All,
                          border: Border.all(
                            color: p.hairline,
                            width: 0.75,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: AppRadii.r8All,
                          child: CachedArtwork(
                            id: song.id,
                            albumId: song.albumId,
                            remoteUrl: song.remoteArtworkUrl,
                            type: ArtworkType.AUDIO,
                            size: 40,
                            borderRadius: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: MediaQuery.withClampedTextScaling(
                          minScaleFactor: 0.8,
                          maxScaleFactor: 2.0,
                          child: AnimatedSwitcher(
                            duration: context.motionMs(220),
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.0, 0.15),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                  parent: anim,
                                  curve: Curves.easeOutCubic,
                                )),
                                child: child,
                              ),
                            ),
                            child: KeyedSubtree(
                              key: ValueKey('song_meta_${song.id}'),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  MarqueeText(
                                    text: song.title,
                                    textAlign: TextAlign.start,
                                    allowUserPause: false,
                                    velocity: 28.0,
                                    blankSpace: 36.0,
                                    style: TextStyle(
                                      fontSize: AppFontSize.bodySmall,
                                      fontWeight: FontWeight.w700,
                                      color: p.textPrimary,
                                      letterSpacing: -0.15,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  MarqueeText(
                                    text: song.artist,
                                    textAlign: TextAlign.start,
                                    allowUserPause: false,
                                    velocity: 24.0,
                                    blankSpace: 32.0,
                                    style: TextStyle(
                                      fontSize: AppFontSize.tiny,
                                      fontWeight: FontWeight.w500,
                                      color: p.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: state.isPlaying
                            ? context.l10n.pause
                            : context.l10n.play,
                        iconSize: 26,
                        visualDensity: VisualDensity.compact,
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: state.isBuffering
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: activeAccent,
                                ),
                              )
                            : Icon(
                                state.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: activeAccent,
                              ),
                        onPressed: () {
                          PulsrHaptics.lightImpact();
                          cubit.togglePlayPause();
                        },
                      ),
                      IconButton(
                        tooltip: context.l10n.next,
                        iconSize: 24,
                        visualDensity: VisualDensity.compact,
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: Icon(
                          Icons.skip_next_rounded,
                          color: state.hasNextNeighbour
                              ? p.textPrimary
                              : p.textTertiary.withValues(alpha: 0.38),
                        ),
                        onPressed: state.hasNextNeighbour
                            ? () {
                                PulsrHaptics.selectionClick();
                                cubit.next();
                              }
                            : null,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ),
                  // Subtle bottom progress hairline for horizontal dock
                  PositionedDirectional(
                    start: AppSpacing.xs,
                    end: AppSpacing.xs,
                    bottom: 0,
                    child: IgnorePointer(
                      child: BlocSelector<PlayerCubit, PlayerState, Duration>(
                        selector: (s) => s.position,
                        builder: (context, pos) {
                          final frac = state.duration.inMilliseconds > 0
                              ? (pos.inMilliseconds /
                                      state.duration.inMilliseconds)
                                  .clamp(0.0, 1.0)
                              : 0.0;
                          return ClipRRect(
                            borderRadius: AppRadii.r1_5All,
                            child: LinearProgressIndicator(
                              value: frac,
                              minHeight: 2.0,
                              backgroundColor:
                                  p.textTertiary.withValues(alpha: 0.20),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(activeAccent),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tablet-optimized player bar variant.
class MiniPlayerTablet extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onToggleSideInspector;
  final bool isInspectorOpen;

  const MiniPlayerTablet({
    super.key,
    required this.onTap,
    this.onToggleSideInspector,
    this.isInspectorOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    return TabletPlayerBar(
      onOpenNowPlaying: onTap,
      onToggleSideInspector: onToggleSideInspector,
      isInspectorOpen: isInspectorOpen,
    );
  }
}

/// Compact portrait mini player (alias for standard MiniPlayer in compact mode).
typedef MiniPlayerCompact = MiniPlayer;