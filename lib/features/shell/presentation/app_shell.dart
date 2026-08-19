// lib/features/shell/presentation/app_shell.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../player/presentation/mini_player.dart';
import '../../player/presentation/now_playing_screen.dart';
import 'bottom_nav_bar.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({
    super.key,
    required this.navigationShell,
  });

  void _onTapNav(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _openNowPlaying(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const NowPlayingScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Child screen
          Positioned.fill(
            child: navigationShell,
          ),

          // Persistent Mini Player above Bottom Nav
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(
              onTap: () => _openNowPlaying(context),
            ),
          ),
        ],
      ),
      bottomNavigationBar: PulsrBottomNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: _onTapNav,
      ),
    );
  }
}
