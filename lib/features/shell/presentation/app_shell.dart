import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/errors/error_message_resolver.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/responsive/layout_delegate.dart';
import '../../../core/responsive/pulsr_hinge_gap.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_modal_tracker.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../core/widgets/gesture_hint_overlay.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';
import '../../player/presentation/widgets/tablet_player_bar.dart';
import 'widgets/landscape_sidebar.dart';
import 'widgets/player_shortcut_scope.dart';
import 'widgets/stacked_bottom_dock.dart';
import 'widgets/dock_style_controller.dart';
import 'widgets/tablet_side_inspector.dart';

class AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> with WidgetsBindingObserver {
  bool _isSideInspectorOpen = false;
  bool? _isSidebarExtended;
  // FIX-H9: Cap tab history at 50 entries with O(1) ListQueue trimming
  static const int _maxTabHistory = 50;
  final ListQueue<int> _tabHistory = ListQueue<int>()..add(0);
  int _lastNavMs = 0;
  int _lastPopMs = 0;
  final Stopwatch _backPressStopwatch = Stopwatch();
  Orientation? _lastAppliedOrientation;

  @visibleForTesting
  Stopwatch get backPressStopwatch => _backPressStopwatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreLastShellTab();
    DockStyleController.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (orientation != _lastAppliedOrientation) {
      _lastAppliedOrientation = orientation;
      _syncSystemUiForOrientation(orientation);
    }
  }

  void _syncSystemUiForOrientation(Orientation orientation) {
    if (orientation == Orientation.landscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
          systemStatusBarContrastEnforced: false,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backPressStopwatch
      ..stop()
      ..reset();
    if (state == AppLifecycleState.resumed && _lastAppliedOrientation != null) {
      _syncSystemUiForOrientation(_lastAppliedOrientation!);
    }
  }

  @override
  void dispose() {
    _backPressStopwatch
      ..stop()
      ..reset();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _restoreLastShellTab() {
    SharedPreferences.getInstance().then((prefs) {
      final savedTab = prefs.getInt('setting_last_shell_tab');
      if (savedTab != null &&
          savedTab > 0 &&
          savedTab < 5 &&
          mounted &&
          widget.navigationShell.currentIndex == 0) {
        try {
          widget.navigationShell.goBranch(savedTab);
        } catch (e, st) {
          ErrorLogger.log('Failed to restore last shell tab',
              error: e, stackTrace: st, category: 'Shell');
          try {
            widget.navigationShell.goBranch(0);
          } catch (_) {}
        }
      }
    }).catchError((e, st) {
      ErrorLogger.log('Failed to restore last shell tab',
          error: e, stackTrace: st, category: 'Shell');
    });
  }

  void _onTapNav(int index) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastNavMs < 200) return;
    _lastNavMs = nowMs;
    _backPressStopwatch
      ..stop()
      ..reset();

    final isSameTab = index == widget.navigationShell.currentIndex;

    if (!isSameTab && (_tabHistory.isEmpty || _tabHistory.last != index)) {
      _tabHistory.addLast(index);
      while (_tabHistory.length > _maxTabHistory) {
        _tabHistory.removeFirst();
      }
    }
    try {
      widget.navigationShell.goBranch(
        index,
        initialLocation: isSameTab,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to navigate to branch $index',
          error: e, stackTrace: st, category: 'Shell');
      try {
        widget.navigationShell.goBranch(0);
      } catch (_) {}
    }
    unawaited(SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('setting_last_shell_tab', index);
    }).catchError((e, st) {
      ErrorLogger.log('Failed to persist last shell tab',
          error: e, stackTrace: st, category: 'Shell');
    }));
    if (isSameTab) {
      PrimaryScrollController.maybeOf(context)?.animateTo(
        0.0,
        duration: context.motionMs(300),
        curve: context.motionCurve(Curves.easeOutCubic),
      );
    }
  }

  void _openNowPlaying(BuildContext context) {
    context.pushDebounced('/now-playing');
  }

  @visibleForTesting
  Future<void> handlePop({
    bool didPop = false,
    bool? isInspectorOpenOverride,
    bool ignoreThrottle = false,
  }) async {
    if (didPop) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!ignoreThrottle && nowMs - _lastPopMs < 200) return;
    _lastPopMs = nowMs;

    // 1. If any dialog, bottom sheet, or modal route is open on the root navigator, pop it first:
    final rootNav = rootNavigatorKey.currentState;
    if (PulsrModalTracker.isModalOpen.value &&
        rootNav != null &&
        rootNav.canPop()) {
      _backPressStopwatch
        ..stop()
        ..reset();
      rootNav.pop();
      return;
    }
    if (rootNav != null && rootNav.canPop()) {
      _backPressStopwatch
        ..stop()
        ..reset();
      rootNav.pop();
      return;
    }

    // 2. If side inspector is open in landscape mode, close it first:
    final inspectorOpen = isInspectorOpenOverride ??
        (PulsrLayoutDelegate.of(context).showSideInspector &&
            _isSideInspectorOpen);
    if (inspectorOpen) {
      _backPressStopwatch
        ..stop()
        ..reset();
      setState(() => _isSideInspectorOpen = false);
      return;
    }

    // 3. Back navigation through tab history until Home:
    if (_tabHistory.length > 1) {
      _backPressStopwatch
        ..stop()
        ..reset();
      _tabHistory.removeLast();
      final prevIndex = _tabHistory.last;
      try {
        widget.navigationShell.goBranch(prevIndex);
      } catch (e, st) {
        ErrorLogger.log('Failed to navigate back to branch $prevIndex',
            error: e, stackTrace: st, category: 'Shell');
        try {
          widget.navigationShell.goBranch(0);
        } catch (_) {}
      }
      setState(() {});
      return;
    }

    // 4. If not on the Home tab (0), go back to Home:
    if (widget.navigationShell.currentIndex != 0) {
      _backPressStopwatch
        ..stop()
        ..reset();
      _tabHistory.clear();
      _tabHistory.addLast(0);
      try {
        widget.navigationShell.goBranch(0);
      } catch (_) {}
      setState(() {});
      return;
    }

    // 5. On Home tab: double back press to exit application safely
    if (!_backPressStopwatch.isRunning ||
        _backPressStopwatch.elapsed > const Duration(seconds: 3)) {
      _backPressStopwatch
        ..reset()
        ..start();
      PulsrToast.show(
        context,
        message: context.l10n.pressBackAgainToExit,
        icon: Icons.logout_rounded,
      );
      return;
    }

    _backPressStopwatch
      ..stop()
      ..reset();
    try {
      await SystemNavigator.pop();
    } finally {
      _backPressStopwatch
        ..stop()
        ..reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final layoutDelegate = PulsrLayoutDelegate.of(context);
    final useRail = layoutDelegate.showRail;
    final canShowInspector = layoutDelegate.showSideInspector;
    // Never keep the inspector "open" once the layout no longer supports it
    // (e.g. rotating a tablet to a compact phone layout).
    final inspectorOpen = canShowInspector && _isSideInspectorOpen;
    final extendedRail = _isSidebarExtended ?? layoutDelegate.railExpanded;

    return BlocListener<PlayerCubit, PlayerState>(
      // Playback errors (bot/verification blocks, "multiple tracks failed",
      // stream resolution failures) were only stored in state.errorMessage and
      // never displayed, so playback appeared to stop or skip for no reason.
      listenWhen: (prev, curr) =>
          curr.errorMessage != null && curr.errorMessage != prev.errorMessage,
      listener: (context, state) {
        final message = state.errorMessage;
        if (message == null) return;
        PulsrToast.show(
          context,
          message: resolveUiErrorMessage(context, message),
          icon: Icons.error_outline_rounded,
          isError: true,
        );
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) => handlePop(
          didPop: didPop,
          isInspectorOpenOverride: inspectorOpen,
        ),
        child: PlayerShortcutScope(
          onTogglePlayPause: () =>
              context.read<PlayerCubit>().togglePlayPause(),
          onSeekForward: () => context
              .read<PlayerCubit>()
              .fastForward(const Duration(seconds: 10)),
          onSeekBackward: () =>
              context.read<PlayerCubit>().rewind(const Duration(seconds: 10)),
          onVolumeUp: () => context.read<PlayerCubit>().adjustVolume(0.05),
          onVolumeDown: () => context.read<PlayerCubit>().adjustVolume(-0.05),
          onNext: () => context.read<PlayerCubit>().next(),
          onPrevious: () => context.read<PlayerCubit>().previous(),
          onToggleMute: () => context.read<PlayerCubit>().toggleMute(),
          onToggleLyrics: () => context.read<PlayerCubit>().toggleLyrics(),
          onToggleQueue: () => context.read<PlayerCubit>().toggleQueue(),
          child: _buildShellContent(
            context,
            layoutDelegate: layoutDelegate,
            useRail: useRail,
            canShowInspector: canShowInspector,
            inspectorOpen: inspectorOpen,
            extendedRail: extendedRail,
          ),
        ),
      ),
    );
  }

  Widget _buildShellContent(
    BuildContext context, {
    required PulsrLayoutDelegate layoutDelegate,
    required bool useRail,
    required bool canShowInspector,
    required bool inspectorOpen,
    required bool extendedRail,
  }) {
    // Phone / Compact Layout (bottom dock)
    if (!useRail) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(child: widget.navigationShell),
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: 0,
              child: ValueListenableBuilder<DockStackMode>(
                valueListenable: DockStyleController.mode,
                builder: (context, dockMode, _) => StackedBottomDock(
                  currentIndex: widget.navigationShell.currentIndex,
                  onTapNav: _onTapNav,
                  onOpenNowPlaying: () => _openNowPlaying(context),
                  mode: dockMode,
                  layoutMode: layoutDelegate.layoutMode,
                  onModeChanged: DockStyleController.set,
                ),
              ),
            ),
            // One-time education for the (previously invisible) dock styles.
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: 0,
              child: BlocBuilder<PlayerCubit, PlayerState>(
                buildWhen: (prev, curr) =>
                    (prev.currentSong != null) != (curr.currentSong != null),
                builder: (context, state) => state.currentSong == null
                    ? const SizedBox.shrink()
                    : GestureHintOverlay(
                        hintKey: 'dock_style',
                        message: context.l10n.dockStyleHint,
                        icon: Icons.vertical_align_bottom_rounded,
                        padding: const EdgeInsetsDirectional.only(
                          bottom: 132,
                          start: 16,
                          end: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Tablet Layout (side rail + docked player bar) ──────────────────
    return Scaffold(
      body: Row(
        children: [
          // Left Custom Aura Navigation Sidebar
          LandscapeSidebar(
            currentIndex: widget.navigationShell.currentIndex,
            onDestinationSelected: _onTapNav,
            isExtended: extendedRail,
            onToggleExtended: () =>
                setState(() => _isSidebarExtended = !extendedRail),
            onOpenNowPlaying: () => _openNowPlaying(context),
            onToggleSideInspector: canShowInspector
                ? () =>
                    setState(() => _isSideInspectorOpen = !_isSideInspectorOpen)
                : null,
            isSideInspectorOpen: inspectorOpen,
          ),
          const PulsrHingeGap.horizontal(),

          // Main Content Area with Bottom Docked Player Bar
          Expanded(
            child: SafeArea(
              top: false,
              bottom: false,
              left: false,
              right: true,
              child: Stack(
                children: [
                  // Upper Screen Row: Active Screen + Optional Side Inspector
                  Positioned.fill(
                    child: Row(
                      children: [
                        Expanded(child: widget.navigationShell),
                        if (inspectorOpen) ...[
                          TabletSideInspector(
                            onClose: () =>
                                setState(() => _isSideInspectorOpen = false),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Bottom Docked Tablet Player Bar
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: 0,
                    child: TabletPlayerBar(
                      onOpenNowPlaying: () => _openNowPlaying(context),
                      onToggleSideInspector: canShowInspector
                          ? () => setState(
                              () => _isSideInspectorOpen = !_isSideInspectorOpen)
                          : null,
                      isInspectorOpen: inspectorOpen,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
