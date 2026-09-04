import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/widgets/pulsr_logo.dart';
import '../../player/presentation/mini_player.dart';
import '../../player/presentation/widgets/tablet_player_bar.dart';
import 'bottom_nav_bar.dart';
import 'widgets/tablet_side_inspector.dart';

class AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _isSideInspectorOpen = false;

  void _onTapNav(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _openNowPlaying(BuildContext context) {
    context.push('/now-playing');
  }

  static const _destinations = [
    (icon: Icons.home_outlined, selected: Icons.home_rounded, label: 'Home'),
    (
      icon: Icons.library_music_outlined,
      selected: Icons.library_music_rounded,
      label: 'Library'
    ),
    (
      icon: Icons.search_rounded,
      selected: Icons.search_rounded,
      label: 'Search'
    ),
    (
      icon: Icons.queue_music_outlined,
      selected: Icons.queue_music_rounded,
      label: 'Playlists'
    ),
    (
      icon: Icons.settings_outlined,
      selected: Icons.settings_rounded,
      label: 'Settings'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final isLandscape = context.isLandscape;
    final isTabletLandscape = isTablet && isLandscape;
    final width = Adaptive.widthOf(context);
    final extendedRail = width >= 1100;

    // ── Portrait Layout (Phone & Tablet Portrait) ──────────────────────
    if (!isLandscape) {
      final double maxPlayerWidth = isTablet ? 640.0 : 560.0;
      return Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: widget.navigationShell),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxPlayerWidth),
                  child: MiniPlayer(onTap: () => _openNowPlaying(context)),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: PulsrBottomNavBar(
          currentIndex: widget.navigationShell.currentIndex,
          onTap: _onTapNav,
        ),
      );
    }

    // ── Tablet Landscape Layout (Widescreen Music Experience) ───────────
    final railWidth = extendedRail ? 220.0 : 84.0;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // Left Navigation Rail
            Container(
              width: railWidth,
              color: p.surface,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      extendedRail ? 20 : 0,
                      22,
                      extendedRail ? 20 : 0,
                      18,
                    ),
                    child: extendedRail
                        ? Row(
                            children: [
                              PulsrLogo(
                                size: 30,
                                color: p.accent,
                                glowColor: p.glow,
                                animate: false,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'PULSR',
                                style: TextStyle(
                                  color: p.accent,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.2,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          )
                        : PulsrLogo(
                            size: 30,
                            color: p.accent,
                            glowColor: p.glow,
                            animate: false,
                          ),
                  ),
                  Expanded(
                    child: NavigationRail(
                      selectedIndex: widget.navigationShell.currentIndex,
                      onDestinationSelected: _onTapNav,
                      extended: extendedRail,
                      backgroundColor: Colors.transparent,
                      labelType: extendedRail
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      destinations: [
                        for (final d in _destinations)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selected),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: p.hairline),

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
