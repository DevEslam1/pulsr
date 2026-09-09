import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../player/presentation/widgets/tablet_player_bar.dart';
import 'widgets/landscape_sidebar.dart';
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
  final List<int> _tabHistory = [0];
  DateTime? _lastBackPressTime;

  void _onTapNav(int index) {
    if (_tabHistory.isEmpty || _tabHistory.last != index) {
      _tabHistory.add(index);
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
    final isTabletLandscape = isTablet && isLandscape;
    final width = Adaptive.widthOf(context);
    final extendedRail = _isSidebarExtended ?? (width >= 1100);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 1. If any dialog, bottom sheet, or modal route is open on the root navigator, pop it first:
        final rootNav = rootNavigatorKey.currentState;
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
          _tabHistory.add(0);
          widget.navigationShell.goBranch(0);
          setState(() {});
          return;
        }

        // 5. On Home tab: double back press to exit application safely
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          PulsrToast.show(
            context,
            message: 'Press back again to exit',
            icon: Icons.exit_to_app_rounded,
          );
          return;
        }

        await SystemNavigator.pop();
      },
      child: _buildShellContent(
        context,
        isLandscape: isLandscape,
        isTabletLandscape: isTabletLandscape,
        extendedRail: extendedRail,
      ),
    );
  }

  Widget _buildShellContent(
    BuildContext context, {
    required bool isLandscape,
    required bool isTabletLandscape,
    required bool extendedRail,
  }) {

    // ── Portrait Layout (Phone & Tablet Portrait) ──────────────────────
    if (!isLandscape) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(child: widget.navigationShell),
            Positioned(
              left: 0,
              right: 0,
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

    // ── Tablet / Desktop Landscape Layout (Widescreen Music Experience) ─
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
              onToggleSideInspector: isTabletLandscape
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
                        if (_isSideInspectorOpen && isTabletLandscape) ...[
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
                    onToggleSideInspector: isTabletLandscape
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
