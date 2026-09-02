// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import '../config/app_config.dart';
import '../utils/l10n_extensions.dart';
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
import '../../features/settings/presentation/proxy_settings_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/smart_playlist_builder/presentation/smart_playlist_builder_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/tag_editor/presentation/tag_editor_screen.dart';
import '../../features/year_detail/presentation/year_detail_screen.dart';
import '../../features/ytm_search/presentation/ytm_search_screen.dart';
import '../../features/ytm_browse/presentation/ytm_browse_screen.dart';
import '../../features/library/presentation/artwork_grid_screen.dart';
import '../../features/library/presentation/duplicate_finder_screen.dart';
import '../../features/library/presentation/library_stats_screen.dart';
import '../../features/player/presentation/themes/custom_theme_builder_screen.dart';
import '../../features/settings/presentation/scrobble_stats_screen.dart';
import '../../features/settings/presentation/cloud_backup_dashboard_screen.dart';
import '../../features/downloads/presentation/downloads_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

GoRouter createRouter(MediaScannerService scannerService) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      if (!AppConfig.ytmEnabled) {
        final path = state.uri.path;
        if (path.startsWith('/ytm-search') ||
            path.startsWith('/ytm-explore') ||
            path.startsWith('/downloads')) {
          return '/';
        }
      }
      return null;
    },
    errorBuilder:
        (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Page Not Found')),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.music_off_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  'No page found at ${state.uri}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/'),
                  child: Text(context.l10n.navHome),
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
        builder:
            (context, state) =>
                OnboardingScreen(scannerService: scannerService),
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
                pageBuilder:
                    (context, state) =>
                        const NoTransitionPage(child: HomeScreen()),
              ),
            ],
          ),

          // Tab 2: Library
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                name: 'library',
                pageBuilder:
                    (context, state) =>
                        const NoTransitionPage(child: LibraryScreen()),
              ),
            ],
          ),

          // Tab 3: Search
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                name: 'search',
                pageBuilder:
                    (context, state) =>
                        const NoTransitionPage(child: SearchScreen()),
              ),
            ],
          ),

          // Tab 4: Playlists
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/playlists',
                name: 'playlists',
                pageBuilder:
                    (context, state) =>
                        const NoTransitionPage(child: PlaylistsScreen()),
              ),
            ],
          ),

          // Tab 5: Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                pageBuilder:
                    (context, state) =>
                        const NoTransitionPage(child: SettingsScreen()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/now-playing',
        name: 'now-playing',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder:
            (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const NowPlayingScreen(),
              transitionsBuilder: (
                context,
                animation,
                secondaryAnimation,
                child,
              ) {
                const begin = Offset(0.0, 1.0);
                const end = Offset.zero;
                const curve = Curves.easeOutCubic;
                final tween = Tween(
                  begin: begin,
                  end: end,
                ).chain(CurveTween(curve: curve));
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
          final album =
              state.extra is AlbumsTableData
                  ? state.extra as AlbumsTableData
                  : null;
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
          final artist =
              state.extra is ArtistsTableData
                  ? state.extra as ArtistsTableData
                  : null;
          if (artist == null) {
            return const Scaffold(
              body: Center(child: Text('Artist not found')),
            );
          }
          return ArtistDetailScreen(artist: artist);
        },
      ),
      GoRoute(
        path: '/genre',
        name: 'genre',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final genre =
              state.extra is GenreItem ? state.extra as GenreItem : null;
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
          final year = state.extra is YearItem ? state.extra as YearItem : null;
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
          final playlist =
              state.extra is PlaylistsTableData
                  ? state.extra as PlaylistsTableData
                  : null;
          if (playlist == null) {
            return const Scaffold(
              body: Center(child: Text('Playlist not found')),
            );
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
          final folder =
              state.extra is FolderItem ? state.extra as FolderItem : null;
          if (folder == null) {
            return const Scaffold(
              body: Center(child: Text('Folder not found')),
            );
          }
          return FolderDetailScreen(folder: folder);
        },
      ),
      GoRoute(
        path: '/tag-editor',
        name: 'tag-editor',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final song =
              state.extra is SongsTableData
                  ? state.extra as SongsTableData
                  : null;
          if (song == null) {
            return const Scaffold(body: Center(child: Text('Song not found')));
          }
          return TagEditorScreen(song: song);
        },
      ),
      GoRoute(
        path: '/proxy-settings',
        name: 'proxy-settings',
        parentNavigatorKey: rootNavigatorKey,
        builder:
            (context, state) => ProxySettingsScreen(
              initialImportText:
                  state.extra is String ? state.extra as String : null,
            ),
      ),
      // Gated: only reachable in an ENABLE_YTM build. In prod this collection-if
      // is const-false, so the route and YtmSearchScreen tree-shake away.
      if (AppConfig.ytmEnabled) ...[
        GoRoute(
          path: '/ytm-search',
          name: 'ytm-search',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const YtmSearchScreen(),
        ),
        GoRoute(
          path: '/ytm-explore',
          name: 'ytm-explore',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const YtmBrowseScreen(),
        ),
        GoRoute(
          path: '/downloads',
          name: 'downloads',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const DownloadsScreen(),
        ),
      ],
      GoRoute(
        path: '/artwork-grid',
        name: 'artwork-grid',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ArtworkGridScreen(),
      ),
      GoRoute(
        path: '/duplicate-finder',
        name: 'duplicate-finder',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const DuplicateFinderScreen(),
      ),
      GoRoute(
        path: '/library-stats',
        name: 'library-stats',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const LibraryStatsScreen(),
      ),
      GoRoute(
        path: '/theme-studio',
        name: 'theme-studio',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CustomThemeBuilderScreen(),
      ),
      GoRoute(
        path: '/scrobble-stats',
        name: 'scrobble-stats',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ScrobbleStatsScreen(),
      ),
      GoRoute(
        path: '/cloud-backup-dashboard',
        name: 'cloud-backup-dashboard',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CloudBackupDashboardScreen(),
      ),
    ],
  );
}
