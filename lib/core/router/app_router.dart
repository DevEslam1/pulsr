// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import '../config/app_config.dart';
import '../errors/failures.dart';
import '../utils/l10n_extensions.dart';
import '../../domain/models/genre_item.dart';
import '../../domain/models/year_item.dart';
import '../../domain/usecases/folder_usecases.dart';
import '../di/injection.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../widgets/entity_by_id_loader.dart';
import '../../features/album_detail/presentation/album_detail_screen.dart';
import '../../features/artist_detail/presentation/artist_detail_screen.dart';
import '../../features/folder_detail/presentation/folder_detail_screen.dart';
import '../../features/genre_detail/presentation/genre_detail_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/player/presentation/now_playing_screen.dart';
import '../../features/playlist_detail/presentation/playlist_detail_screen.dart';
import '../../features/playlist_detail/presentation/manage_playlist_screen.dart';
import '../../features/library/presentation/recents_screen.dart';
import '../../features/playlists/presentation/playlists_screen.dart';
import '../../features/queue/presentation/queue_screen.dart';
import '../../features/radio/presentation/radio_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/presentation/proxy_settings_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/smart_playlist_builder/smart_playlist_builder_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/tag_editor/tag_editor_screen.dart';
import '../../features/year_detail/presentation/year_detail_screen.dart';
import '../../features/ytm_search/presentation/ytm_search_screen.dart';
import '../../features/ytm_browse/presentation/ytm_browse_screen.dart';
import '../../features/library/presentation/artwork_grid_screen.dart';
import '../../features/library/presentation/duplicate_finder_screen.dart';
import '../../features/library/presentation/library_stats_screen.dart';
import '../../features/player/presentation/themes/custom_theme_builder_screen.dart';
import '../../features/settings/presentation/hidden_folders_screen.dart';
import '../../features/settings/presentation/scrobble_stats_screen.dart';
import '../../features/settings/presentation/cloud_backup_dashboard_screen.dart';
import '../../features/downloads/presentation/downloads_screen.dart';
import '../../features/library/presentation/favorites_screen.dart';
import '../../features/playlist_detail/presentation/online_playlist_detail_screen.dart';
import '../../features/playlists/cubit/playlist_cubit.dart';
import '../../features/quran_mode/presentation/quran_mode_screen.dart';
import '../motion/pulsr_motion.dart';
import '../services/ytm_account_service.dart';
import '../widgets/pulsr_modal_tracker.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

Page<dynamic> _buildPulsrPageRoute({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (!context.motionEnabled) {
        return child;
      }

      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.fastEaseInToSlowEaseOut,
        reverseCurve: Curves.easeInCubic,
      );
      final secondaryCurved = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.fastEaseInToSlowEaseOut,
        reverseCurve: Curves.easeInCubic,
      );

      // Primary entrance: smooth slide in from right with fade
      final slide = Tween<Offset>(
        begin: const Offset(0.12, 0.0),
        end: Offset.zero,
      ).animate(curved);
      final fade = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
      ));

      // Secondary exit: subtle Apple-style parallax recession
      final secondarySlide = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.04, 0.0),
      ).animate(secondaryCurved);
      final secondaryFade = Tween<double>(
        begin: 1.0,
        end: 0.92,
      ).animate(secondaryCurved);

      return SlideTransition(
        position: secondarySlide,
        child: FadeTransition(
          opacity: secondaryFade,
          child: SlideTransition(
            position: slide,
            child: FadeTransition(
              opacity: fade,
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// A calm cross-fade + lift between the five shell tabs. Unlike the instant
/// [NoTransitionPage] this makes switching Home ⇄ Library ⇄ Search feel
/// intentional; it honours Reduce Motion by returning the child directly.
Page<dynamic> _buildTabPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (!context.motionEnabled) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 0.012),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Resolves a detail screen either from a typed route `extra` or, when absent,
/// from an `?id=` query parameter so album/artist/playlist pages can be
/// deep-linked, restored and shared.
Page<dynamic> _resolveById<T>({
  required LocalKey pageKey,
  required String? id,
  Future<Result<T?>> Function()? fetchSingle,
  Stream<Result<List<T>>> Function()? watch,
  bool Function(T item)? match,
  required Widget Function(BuildContext context, T item) builder,
  required String notFoundMessage,
}) {
  if (id == null || id.isEmpty) {
    return _buildPulsrPageRoute(
      key: pageKey,
      child: Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(notFoundMessage)),
      ),
    );
  }
  return _buildPulsrPageRoute(
    key: pageKey,
    child: EntityByIdLoader<T>(
      fetchSingle: fetchSingle,
      watch: watch,
      match: match,
      builder: builder,
      notFoundMessage: notFoundMessage,
    ),
  );
}

GoRouter createRouter(MediaScannerService scannerService, [IMusicRepository? musicRepository]) {
  final repo = musicRepository ?? getIt<IMusicRepository>();
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    observers: [PulsrModalObserver()],
    initialLocation: '/splash',
    redirect: (context, state) {
      if (!AppConfig.ytmEnabled) {
        const ytmPaths = {
          '/ytm-search',
          '/ytm-explore',
          '/downloads',
          '/online-playlist',
        };
        if (ytmPaths.contains(state.uri.path)) return '/';
      }
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: Text(context.l10n.pageNotFoundTitle)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_off_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: AppSpacing.md),
            Text(
                context.l10n.pageNotFoundMessage(state.uri.toString()),
                style: const TextStyle(fontSize: AppFontSize.bodyLarge)),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => context.go('/'),
              child: Text(context.l10n.goHome),
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
        builder: (context, state) =>
            OnboardingScreen(scannerService: scannerService),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // Tab 1: Home
          StatefulShellBranch(
            observers: [PulsrModalObserver()],
            routes: [
              GoRoute(
                path: '/',
                name: 'home',
                pageBuilder: (context, state) => _buildTabPage(
                  key: state.pageKey,
                  child: const HomeScreen(),
                ),
              ),
            ],
          ),

          // Tab 2: Library
          StatefulShellBranch(
            observers: [PulsrModalObserver()],
            routes: [
              GoRoute(
                path: '/library',
                name: 'library',
                pageBuilder: (context, state) => _buildTabPage(
                  key: state.pageKey,
                  child: const LibraryScreen(),
                ),
              ),
            ],
          ),

          // Tab 3: Search
          StatefulShellBranch(
            observers: [PulsrModalObserver()],
            routes: [
              GoRoute(
                path: '/search',
                name: 'search',
                pageBuilder: (context, state) => _buildTabPage(
                  key: state.pageKey,
                  child: const SearchScreen(),
                ),
              ),
            ],
          ),

          // Tab 4: Playlists
          StatefulShellBranch(
            observers: [PulsrModalObserver()],
            routes: [
              GoRoute(
                path: '/playlists',
                name: 'playlists',
                pageBuilder: (context, state) => _buildTabPage(
                  key: state.pageKey,
                  child: const PlaylistsScreen(),
                ),
              ),
            ],
          ),

          // Tab 5: Settings
          StatefulShellBranch(
            observers: [PulsrModalObserver()],
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                pageBuilder: (context, state) => _buildTabPage(
                  key: state.pageKey,
                  child: const SettingsScreen(),
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
          transitionDuration: const Duration(milliseconds: 340),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (!context.motionEnabled) return child;
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.fastEaseInToSlowEaseOut,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween(begin: const Offset(0.0, 1.0), end: Offset.zero)
                  .animate(curved),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: '/album',
        name: 'album',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          AlbumsTableData? album;
          String? heroTag = state.uri.queryParameters['heroTag'];
          if (state.extra is AlbumsTableData) {
            album = state.extra as AlbumsTableData;
          } else if (state.extra is Map) {
            final map = state.extra as Map;
            if (map['album'] is AlbumsTableData) {
              album = map['album'] as AlbumsTableData;
            }
            if (map['heroTag'] is String) {
              heroTag = map['heroTag'] as String;
            }
          }
          if (album != null) {
            return _buildPulsrPageRoute(
              key: state.pageKey,
              child: AlbumDetailScreen(album: album, heroTag: heroTag),
            );
          }
          final id = state.uri.queryParameters['id'];
          final parsedId = int.tryParse(id ?? '');
          return _resolveById<AlbumsTableData>(
            pageKey: state.pageKey,
            id: id,
            fetchSingle: parsedId != null ? () => repo.getAlbumById(parsedId) : null,
            watch: () => repo.watchAlbums(),
            match: (a) => a.id.toString() == id,
            builder: (context, a) =>
                AlbumDetailScreen(album: a, heroTag: heroTag),
            notFoundMessage: context.l10n.albumNotFoundHint,
          );
        },
      ),
      GoRoute(
        path: '/artist',
        name: 'artist',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final artist = state.extra is ArtistsTableData
              ? state.extra as ArtistsTableData
              : null;
          if (artist != null) {
            return _buildPulsrPageRoute(
               key: state.pageKey,
               child: ArtistDetailScreen(artist: artist),
            );
          }
          final id = state.uri.queryParameters['id'];
          final parsedId = int.tryParse(id ?? '');
          return _resolveById<ArtistsTableData>(
            pageKey: state.pageKey,
            id: id,
            fetchSingle: parsedId != null ? () => repo.getArtistById(parsedId) : null,
            watch: () => repo.watchArtists(),
            match: (a) => a.id.toString() == id,
            builder: (context, a) => ArtistDetailScreen(artist: a),
            notFoundMessage: context.l10n.artistNotFoundHint,
          );
        },
      ),
      GoRoute(
        path: '/genre',
        name: 'genre',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final genre =
              state.extra is GenreItem ? state.extra as GenreItem : null;
          if (genre == null) {
            return _buildPulsrPageRoute(
              key: state.pageKey,
              child: Scaffold(
                appBar: AppBar(),
                body: Center(child: Text(context.l10n.genreNotFoundHint)),
              ),
            );
          }
          return _buildPulsrPageRoute(
            key: state.pageKey,
            child: GenreDetailScreen(genreItem: genre),
          );
        },
      ),
      GoRoute(
        path: '/year',
        name: 'year',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final year = state.extra is YearItem ? state.extra as YearItem : null;
          if (year == null) {
            return _buildPulsrPageRoute(
              key: state.pageKey,
              child: Scaffold(
                appBar: AppBar(),
                body: Center(child: Text(context.l10n.yearNotFoundHint)),
              ),
            );
          }
          return _buildPulsrPageRoute(
            key: state.pageKey,
            child: YearDetailScreen(yearItem: year),
          );
        },
      ),
      GoRoute(
        path: '/playlist',
        name: 'playlist',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final playlist = state.extra is PlaylistsTableData
              ? state.extra as PlaylistsTableData
              : null;
          if (playlist != null) {
            return _buildPulsrPageRoute(
              key: state.pageKey,
              child: PlaylistDetailScreen(playlist: playlist),
            );
          }
          final id = state.uri.queryParameters['id'];
          final parsedId = int.tryParse(id ?? '');
          return _resolveById<PlaylistsTableData>(
            pageKey: state.pageKey,
            id: id,
            fetchSingle: parsedId != null ? () => repo.getPlaylistById(parsedId) : null,
            watch: () => repo.watchPlaylists(),
            match: (p) => p.id.toString() == id,
            builder: (context, p) => PlaylistDetailScreen(playlist: p),
            notFoundMessage: context.l10n.playlistNotFoundHint,
          );
        },
      ),
      GoRoute(
        path: '/playlist/manage',
        name: 'manage-playlist',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final playlist = state.extra is PlaylistsTableData
              ? state.extra as PlaylistsTableData
              : null;
          if (playlist == null) {
            return Scaffold(
                body: Center(child: Text(context.l10n.playlistNotFoundHint)));
          }
          return ManagePlaylistScreen(playlist: playlist);
        },
      ),
      GoRoute(
        path: '/online-playlist',
        name: 'online-playlist',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is OnlinePlaylistDetailArgs) {
            return OnlinePlaylistDetailScreen(args: extra);
          }
          if (extra is YtmAccountPlaylist) {
            return OnlinePlaylistDetailScreen(
              args: OnlinePlaylistDetailArgs(
                playlistId: extra.playlistId,
                title: extra.title,
                subtitle: extra.subtitle,
                artworkUrl: extra.artworkUrl,
              ),
            );
          }
          if (extra is OnlinePlaylistEntry) {
            return OnlinePlaylistDetailScreen(
              args: OnlinePlaylistDetailArgs(
                playlistId: extra.id,
                title: extra.title,
                subtitle: extra.uploader,
                initialTracks: extra.tracks,
              ),
            );
          }
          final id = state.uri.queryParameters['id'] ??
              (extra is String ? extra : '');
          return OnlinePlaylistDetailScreen(
            args: OnlinePlaylistDetailArgs(playlistId: id),
          );
        },
      ),
      GoRoute(
        path: '/recents',
        name: 'recents',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const RecentsScreen(),
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
        path: '/radio',
        name: 'radio',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const RadioScreen(),
      ),
      GoRoute(
        path: '/folder',
        name: 'folder',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final folder =
              state.extra is FolderItem ? state.extra as FolderItem : null;
          if (folder == null) {
            return Scaffold(
                body: Center(child: Text(context.l10n.folderNotFound)));
          }
          return FolderDetailScreen(folder: folder);
        },
      ),
      GoRoute(
        path: '/tag-editor',
        name: 'tag-editor',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is List<SongsTableData> && extra.isNotEmpty) {
            return TagEditorScreen(song: extra.first, batchSongs: extra);
          }
          final song = extra is SongsTableData ? extra : null;
          if (song == null) {
            return Scaffold(body: Center(child: Text(context.l10n.songNotFound)));
          }
          return TagEditorScreen(song: song);
        },
      ),
      GoRoute(
        path: '/proxy-settings',
        name: 'proxy-settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ProxySettingsScreen(
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
          path: '/browse',
          name: 'browse',
          redirect: (context, state) =>
              AppConfig.ytmEnabled ? '/ytm-search' : '/search',
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
        // Spec F-49/F-56 marks cloud backup SKIPPED: block the route in Pure
        // builds and when cloud sync is disallowed instead of shipping a dead
        // surface (defects 03-02/22-01/20-03).
        redirect: (context, state) =>
            AppConfig.isCloudSyncAllowed ? null : '/settings',
        builder: (context, state) => const CloudBackupDashboardScreen(),
      ),
      GoRoute(
        path: '/quran-mode',
        name: 'quran-mode',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const QuranModeScreen(),
      ),

      GoRoute(
        path: '/favorites',
        name: 'favorites',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: '/hidden-folders',
        name: 'hidden-folders',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const HiddenFoldersScreen(),
      ),
    ],
  );
}
