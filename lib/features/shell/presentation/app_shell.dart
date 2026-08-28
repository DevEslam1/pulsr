import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/widgets/pulsr_logo.dart';
import '../../player/presentation/mini_player.dart';
import 'bottom_nav_bar.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  void _onTapNav(int index) {
    navigationShell.goBranch(index,
        initialLocation: index == navigationShell.currentIndex);
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
    final extendedRail =
        Adaptive.widthOf(context) >= Adaptive.railExtendedBreakpoint;

    final content = Stack(
      children: [
        Positioned.fill(child: navigationShell),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: MiniPlayer(onTap: () => _openNowPlaying(context)),
            ),
          ),
        ),
      ],
    );

    if (!isTablet) {
      return Scaffold(
        body: content,
        bottomNavigationBar: PulsrBottomNavBar(
          currentIndex: navigationShell.currentIndex,
          onTap: _onTapNav,
        ),
      );
    }

    // ---- Tablet / desktop: side rail layout ----
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: extendedRail ? 232 : 92,
              color: p.surface,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        extendedRail ? 22 : 0, 26, extendedRail ? 22 : 0, 22),
                    child: extendedRail
                        ? Row(
                            children: [
                              PulsrLogo(
                                  size: 32,
                                  color: p.accent,
                                  glowColor: p.glow,
                                  animate: false),
                              const SizedBox(width: 12),
                              Text(
                                'PULSR',
                                style: TextStyle(
                                  color: p.accent,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.4,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          )
                        : PulsrLogo(
                            size: 32,
                            color: p.accent,
                            glowColor: p.glow,
                            animate: false),
                  ),
                  Expanded(
                    child: NavigationRail(
                      selectedIndex: navigationShell.currentIndex,
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
                  const SizedBox(height: 96), // clears mini player
                ],
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: p.hairline),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
