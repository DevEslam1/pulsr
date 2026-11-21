import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/prefs_keys.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/list_content_diff.dart';
import '../../../core/utils/pulsr_haptics.dart';
import '../../../core/widgets/gesture_hint_overlay.dart';
import '../../../data/db/app_database.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'widgets/mini_player/mini_player_compact_card.dart';
import 'widgets/mini_player/mini_player_horizontal_bar.dart';

export 'widgets/mini_player/mini_player_compact_card.dart';
export 'widgets/mini_player/mini_player_horizontal_bar.dart';
export 'widgets/mini_player/mini_player_progress_bar.dart';
export 'widgets/mini_player/mini_player_tablet_bar.dart';

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
  final ValueNotifier<double> _carouselDragDelta = ValueNotifier<double>(0.0);
  bool _showGrabChevron = false;
  static const int _maxGrabChevronSessions = 5;
  static bool _chevronSessionCounted = false;
  @visibleForTesting
  static void resetSessionTrackingForTest() {
    _chevronSessionCounted = false;
  }

  bool _swipeInFlight = false;

  /// Bounded post-frame retries while the PageView catches up with a queue
  /// whose length just changed. Each retry costs one frame.
  int _pageSyncRetries = 0;
  static const int _maxPageSyncRetries = 4;

  /// Invalidates post-frame retries belonging to an older sync request, so a
  /// rapid skip burst can never drag the carousel back to a previous track.
  int _pageSyncGeneration = 0;

  Timer? _verticalSwipeTimer;
  double _verticalDragDy = 0.0;
  double _horizontalDragDx = 0.0;
  bool _swipeThresholdCrossed = false;
  // AUDIT-FIX: Throttle retry taps on error pill
  DateTime? _lastRetryTime;

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
      await MiniPlayerSwipeActions.execute(
        action,
        cubit,
        swipedLeft: swipedLeft,
      );
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
    unawaited(_loadGrabChevronState());
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

  Future<void> _loadGrabChevronState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(PrefsKeys.dockGrabChevronSessions) ?? 0;
      if (!mounted) return;
      final show = count < _maxGrabChevronSessions;
      if (show != _showGrabChevron) {
        setState(() => _showGrabChevron = show);
      }
      if (!_chevronSessionCounted) {
        _chevronSessionCounted = true;
        await prefs.setInt(PrefsKeys.dockGrabChevronSessions, count + 1);
      }
    } catch (e, st) {
      ErrorLogger.log('MiniPlayer grab chevron prefs load failed',
          error: e, stackTrace: st, category: 'MiniPlayer');
    }
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
    _carouselDragDelta.dispose();
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

  /// A swipe landed on [page]: skip to the new item and safely resync.
  Future<void> _completeSwipe(int page, PlayerCubit cubit) async {
    try {
      await cubit
          .skipToQueueItem(page)
          .timeout(MiniPlayerSwipeActions.latchTimeout);
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

  void _handleVerticalDragEnd(DragEndDetails d) {
    if (_swipeInFlight) return;
    final vy = d.velocity.pixelsPerSecond.dy;
    if ((_verticalDragDy > 25 || vy > 120) &&
        _verticalDragDy >= 0 &&
        vy >= 0) {
      _swipeInFlight = true;
      PulsrHaptics.selectionClick();
      widget.onSwipeDown?.call();
      _verticalSwipeTimer?.cancel();
      _verticalSwipeTimer = Timer(const Duration(milliseconds: 500), () {
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
      _verticalSwipeTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _swipeInFlight = false);
      });
    }
    _verticalDragDy = 0.0;
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
    final allowMotion = PulsrMotion.shouldAnimate(context);

    final content = BlocConsumer<PlayerCubit, PlayerState>(
      listenWhen: (a, b) =>
          a.currentIndex != b.currentIndex ||
          a.activeQueueSlot != b.activeQueueSlot ||
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
      buildWhen: (a, b) => a.differsForMiniPlayer(b),
      builder: (context, state) {
        final song = state.currentSong;
        if (song == null) return const SizedBox.shrink();

        final cubit = context.read<PlayerCubit>();
        final queue = state.queue.isNotEmpty ? state.queue : [song];
        final currentIndex = state.currentIndex.clamp(0, queue.length - 1);

        // Screen readers cannot perform drag gestures, so expose the swipe
        // up/down actions as custom semantics actions (I9).
        final customSemanticsActions = <CustomSemanticsAction, VoidCallback>{
          CustomSemanticsAction(label: context.l10n.expandPlayer):
              widget.onSwipeUp ?? widget.onTap,
          if (widget.onSwipeDown != null)
            CustomSemanticsAction(label: context.l10n.dismissPlayer):
                widget.onSwipeDown!,
        };

        final swipeLeftIcon = MiniPlayerSwipeActions.iconFor(
          swipeLeftAction,
          swipedLeft: true,
        );
        final swipeRightIcon = MiniPlayerSwipeActions.iconFor(
          swipeRightAction,
          swipedLeft: false,
        );

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
                onVerticalDragEnd: _handleVerticalDragEnd,
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
                child: MiniPlayerCompactCard(
                  state: state,
                  cubit: cubit,
                  song: song,
                  queue: queue,
                  currentIndex: currentIndex,
                  playerThemeMode: playerThemeMode,
                  pageController: _pageController,
                  carouselEnabled: carouselEnabled,
                  swipeInFlight: _swipeInFlight,
                  showGrabChevron: _showGrabChevron,
                  horizontalDragDx: _horizontalDragDx,
                  swipeThresholdCrossed: _swipeThresholdCrossed,
                  swipeLeftIcon: swipeLeftIcon,
                  swipeRightIcon: swipeRightIcon,
                  isInteracting: _isInteracting,
                  carouselDragDelta: _carouselDragDelta,
                  onTap: widget.onTap,
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
                      unawaited(_completeSwipe(page, cubit));
                    }
                  },
                  onDrainPendingSync: _drainPendingSync,
                  onRetryError: () {
                    // AUDIT-FIX: Cooldown to avoid rapid repeated retries on error pill
                    final now = DateTime.now();
                    if (_lastRetryTime != null &&
                        now.difference(_lastRetryTime!).inMilliseconds < 1000) {
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

    if (!allowMotion) return content;

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

/// Horizontal single-row mini player designed for landscape phones and medium
/// breakpoint wide dock.
class MiniPlayerHorizontal extends StatelessWidget {
  final VoidCallback onTap;

  const MiniPlayerHorizontal({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PlayerCubit>();

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) => prev.differsForMiniPlayerHorizontal(curr),
      builder: (context, state) {
        final song = state.currentSong;
        if (song == null) return const SizedBox.shrink();

        return MiniPlayerHorizontalBar(
          state: state,
          song: song,
          cubit: cubit,
          onTap: onTap,
        );
      },
    );
  }
}

/// Compact portrait mini player (alias for standard MiniPlayer in compact mode).
typedef MiniPlayerCompact = MiniPlayer;
