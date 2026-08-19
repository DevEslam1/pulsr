// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/scanner/media_scanner_service.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/playlists/presentation/playlists_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/player/presentation/now_playing_screen.dart';
import '../../features/shell/presentation/app_shell.dart';

import '../../features/tag_editor/tag_editor_screen.dart';
import '../../data/db/app_database.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter createRouter(MediaScannerService scannerService) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => OnboardingScreen(scannerService: scannerService),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // Tab 1: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                name: 'home',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: HomeScreen(),
                ),
              ),
            ],
          ),

          // Tab 2: Library
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                name: 'library',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: LibraryScreen(),
                ),
              ),
            ],
          ),

          // Tab 3: Search
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                name: 'search',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: SearchScreen(),
                ),
              ),
            ],
          ),

          // Tab 4: Playlists
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/playlists',
                name: 'playlists',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: PlaylistsScreen(),
                ),
              ),
            ],
          ),

          // Tab 5: Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: SettingsScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/now-playing',
        name: 'now-playing',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const NowPlayingScreen(),
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
      ),
      GoRoute(
        path: '/tag-editor',
        name: 'tag-editor',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final song = state.extra as SongsTableData;
          return TagEditorScreen(song: song);
        },
      ),
    ],
  );
}

