// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import '../../domain/models/genre_item.dart';
import '../../domain/models/year_item.dart';
import '../../domain/usecases/folder_usecases.dart';
import '../../features/album_detail/presentation/album_detail_screen.dart';
import '../../features/artist_detail/presentation/artist_detail_screen.dart';
import '../../features/folder_detail/presentation/folder_detail_screen.dart';
import '../../features/genre_detail/presentation/genre_detail_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/player/presentation/now_playing_screen.dart';
import '../../features/playlist_detail/presentation/playlist_detail_screen.dart';
import '../../features/playlists/presentation/playlists_screen.dart';
import '../../features/queue/presentation/queue_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/smart_playlist_builder/smart_playlist_builder_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/tag_editor/tag_editor_screen.dart';
import '../../features/year_detail/presentation/year_detail_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter createRouter(MediaScannerService scannerService) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page Not Found')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_off_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No page found at ${state.uri}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
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
        path: '/album',
        name: 'album',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final album = state.extra as AlbumsTableData?;
          if (album == null) {
            return const Scaffold(body: Center(child: Text('Album not found')));
          }
          return AlbumDetailScreen(album: album);
        },
      ),
      GoRoute(
        path: '/artist',
        name: 'artist',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final artist = state.extra as ArtistsTableData?;
          if (artist == null) {
            return const Scaffold(body: Center(child: Text('Artist not found')));
          }
          return ArtistDetailScreen(artist: artist);
        },
      ),
      GoRoute(
        path: '/genre',
        name: 'genre',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final genre = state.extra as GenreItem?;
          if (genre == null) {
            return const Scaffold(body: Center(child: Text('Genre not found')));
          }
          return GenreDetailScreen(genreItem: genre);
        },
      ),
      GoRoute(
        path: '/year',
        name: 'year',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final year = state.extra as YearItem?;
          if (year == null) {
            return const Scaffold(body: Center(child: Text('Year not found')));
          }
          return YearDetailScreen(yearItem: year);
        },
      ),
      GoRoute(
        path: '/playlist',
        name: 'playlist',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final playlist = state.extra as PlaylistsTableData?;
          if (playlist == null) {
            return const Scaffold(body: Center(child: Text('Playlist not found')));
          }
          return PlaylistDetailScreen(playlist: playlist);
        },
      ),
      GoRoute(
        path: '/smart-playlist-builder',
        name: 'smart-playlist-builder',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final initial = state.extra;
          return SmartPlaylistBuilderScreen(
            initialPlaylist: initial is PlaylistsTableData ? initial : null,
          );
        },
      ),
      GoRoute(
        path: '/queue',
        name: 'queue',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const QueueScreen(),
      ),
      GoRoute(
        path: '/folder',
        name: 'folder',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final folder = state.extra as FolderItem?;
          if (folder == null) {
            return const Scaffold(body: Center(child: Text('Folder not found')));
          }
          return FolderDetailScreen(folder: folder);
        },
      ),
      GoRoute(
        path: '/tag-editor',
        name: 'tag-editor',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final song = state.extra as SongsTableData?;
          if (song == null) {
            return const Scaffold(body: Center(child: Text('Song not found')));
          }
          return TagEditorScreen(song: song);
        },
      ),
    ],
  );
}
