import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/errors/error_message_resolver.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_modal_tracker.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';
import '../../player/presentation/widgets/tablet_player_bar.dart';
import 'widgets/landscape_sidebar.dart';
import 'widgets/player_shortcut_scope.dart';
import 'widgets/stacked_bottom_dock.dart';
import 'widgets/tablet_side_inspector.dart';

class AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _isSideInspectorOpen = false;
  bool? _isSidebarExtended;
  DockStackMode _dockMode = DockStackMode.defaultLayout;
  // FIX-H9: Cap tab history at 50 entries with O(1) ListQueue trimming
  static const int _maxTabHistory = 50;
  final ListQueue<int> _tabHistory = ListQueue<int>()..add(0);
  int _lastNavMs = 0;
  int _lastPopMs = 0;
  DateTime? _lastBackPressTime;

  void _onTapNav(int index) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastNavMs < 200) return;
    _lastNavMs = nowMs;

    if (_tabHistory.isEmpty || _tabHistory.last != index) {
      _tabHistory.addLast(index);
      while (_tabHistory.length > _maxTabHistory) {
        _tabHistory.removeFirst();
      }
    }
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _openNowPlaying(BuildContext context) {
    context.push('/now-playing');
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = Adaptive.isTablet(context);
    final isLandscape = context.isLandscape;
    final width = Adaptive.widthOf(context);
    final height = Adaptive.heightOf(context);
    // Tablets get the side rail in both orientations (iPad-style); phones keep
    // the bottom dock portrait *and* landscape so a wide-but-short landscape
    // phone is never handed a cramped desktop rail.
    final useRail = isTablet && (!isLandscape || height >= 600);
    final canShowInspector = useRail && (isLandscape || width >= 900);
    final extendedRail =
        _isSidebarExtended ?? (width >= Adaptive.railExtendedBreakpoint);

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
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;

          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - _lastPopMs < 200) return;
          _lastPopMs = nowMs;

          // 1. If any dialog, bottom sheet, or modal route is open on the root navigator, pop it first:
          final rootNav = rootNavigatorKey.currentState;
          if (PulsrModalTracker.isModalOpen.value && rootNav != null && rootNav.canPop()) {
            rootNav.pop();
            return;
          }
          if (rootNav != null && rootNav.canPop()) {
            rootNav.pop();
            return;
          }

          // 2. If side inspector is open in landscape mode, close it first:
          if (_isSideInspectorOpen) {
            setState(() => _isSideInspectorOpen = false);
            return;
          }

          // 3. Back navigation through tab history until Home:
          if (_tabHistory.length > 1) {
            _tabHistory.removeLast();
            final prevIndex = _tabHistory.last;
            widget.navigationShell.goBranch(prevIndex);
            setState(() {});
            return;
          }

          // 4. If not on the Home tab (0), go back to Home:
          if (widget.navigationShell.currentIndex != 0) {
            _tabHistory.clear();
            _tabHistory.addLast(0);
            widget.navigationShell.goBranch(0);
            setState(() {});
            return;
          }

          // 5. On Home tab: double back press to exit application safely
          final now = DateTime.now();
          if (_lastBackPressTime == null ||
              now.difference(_lastBackPressTime!) >
                  const Duration(seconds: 3)) {
            _lastBackPressTime = now;
            PulsrToast.show(
              context,
              message: context.l10n.pressBackAgainToExit,
              icon: Icons.exit_to_app_rounded,
            );
            return;
          }

          await SystemNavigator.pop();
        },
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
            useRail: useRail,
            canShowInspector: canShowInspector,
            extendedRail: extendedRail,
          ),
        ),
      ),
    );
  }

  Widget _buildShellContent(
    BuildContext context, {
    required bool useRail,
    required bool canShowInspector,
    required bool extendedRail,
  }) {

    // ── Phone / Compact Layout (bottom dock) ───────────────────────────
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
              child: StackedBottomDock(
                currentIndex: widget.navigationShell.currentIndex,
                onTapNav: _onTapNav,
                onOpenNowPlaying: () => _openNowPlaying(context),
                mode: _dockMode,
                onModeChanged: (newMode) => setState(() => _dockMode = newMode),
              ),
            ),
          ],
        ),
      );
    }

    // ── Tablet Layout (side rail + docked player bar) ──────────────────
    return Scaffold(
      body: SafeArea(
        child: Row(
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
                  ? () => setState(
                      () => _isSideInspectorOpen = !_isSideInspectorOpen)
                  : null,
              isSideInspectorOpen: _isSideInspectorOpen,
            ),

            // Main Content Area with Bottom Docked Player Bar
            Expanded(
              child: Column(
                children: [
                  // Upper Screen Row: Active Screen + Optional Side Inspector
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: widget.navigationShell),
                        if (_isSideInspectorOpen && canShowInspector) ...[
                          TabletSideInspector(
                            onClose: () =>
                                setState(() => _isSideInspectorOpen = false),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Bottom Docked Tablet Player Bar
                  TabletPlayerBar(
                    onOpenNowPlaying: () => _openNowPlaying(context),
                    onToggleSideInspector: canShowInspector
                        ? () => setState(
                            () => _isSideInspectorOpen = !_isSideInspectorOpen)
                        : null,
                    isInspectorOpen: _isSideInspectorOpen,
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
