import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/adaptive.dart';
import '../../player/presentation/mini_player.dart';
import '../../player/presentation/widgets/tablet_player_bar.dart';
import 'bottom_nav_bar.dart';
import 'widgets/landscape_sidebar.dart';
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

  void _onTapNav(int index) {
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

    // ── Portrait Layout (Phone & Tablet Portrait) ──────────────────────
    if (!isLandscape) {
      final double maxPlayerWidth = isTablet ? 640.0 : 560.0;
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(child: widget.navigationShell),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxPlayerWidth),
                      child: MiniPlayer(onTap: () => _openNowPlaying(context)),
                    ),
                  ),
                  PulsrBottomNavBar(
                    currentIndex: widget.navigationShell.currentIndex,
                    onTap: _onTapNav,
                  ),
                ],
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
