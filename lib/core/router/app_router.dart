// lib/core/router/app_router.dart
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import '../config/app_config.dart';
import '../errors/failures.dart';
import '../theme/pulsr_page_transitions.dart';
import '../utils/l10n_extensions.dart';
import '../widgets/ticker_gated_branch_container.dart';
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
import '../../features/party/presentation/party_screen.dart';
import '../../features/player/presentation/now_playing_screen.dart';
import '../../features/player/presentation/abx_screen.dart';
import '../../features/player/presentation/widgets/karaoke_mode_screen.dart';
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
  // A MaterialPage (not a CustomTransitionPage) is what lets
  // PageTransitionsTheme run: Android gets the predictive-back preview,
  // iOS/macOS keep the interactive edge-swipe, desktop keeps Pulsr's tuned
  // slide via PulsrPageTransitionsBuilder.
  return MaterialPage<void>(
    key: key,
    child: child,
    // Route-derived keys (ValueKey('/album/42')) are stable across relaunches,
    // so the navigator can restore the stack after process death.
    restorationId: key is ValueKey<String> ? key.value : null,
  );
}

/// A calm cross-fade + lift between the five shell tabs. Unlike the instant
/// [NoTransitionPage] this makes switching Home ⇄ Library ⇄ Search feel
/// intentional; it honours Reduce Motion by returning the child directly.
Page<dynamic> _buildTabPage({
  required LocalKey key,
  required Widget child,
}) {
  return MaterialPage<void>(
    key: key,
    child: child,
    restorationId: key is ValueKey<String> ? key.value : null,
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

/// Checks whether an incoming URI or location path corresponds to an external
/// audio file opened via an Android intent or external file manager.
///
/// Matches locations starting with 'file:', 'content:', '/sdcard/', '/storage/',
/// or ending in common audio extensions (.wav, .mp3, .ogg, .flac, .m4a).
bool isExternalAudioLocation(Uri uri) {
  final full = uri.toString().toLowerCase();
  final path = uri.path.toLowerCase();

  if (uri.scheme == 'file' || uri.scheme == 'content') {
    return true;
  }

  const prefixes = [
    'file:',
    'content:',
    '/sdcard/',
    '/storage/',
    'sdcard/',
    'storage/',
  ];

  for (final prefix in prefixes) {
    if (full.startsWith(prefix) || path.startsWith(prefix)) {
      return true;
    }
  }

  const audioExtensions = [
    '.wav',
    '.mp3',
    '.ogg',
    '.flac',
    '.m4a',
  ];

  for (final ext in audioExtensions) {
    if (path.endsWith(ext) || full.endsWith(ext)) {
      return true;
    }
  }

  return false;
}

Page<dynamic> _buildAlbumRoute(
  BuildContext context,
  GoRouterState state,
  IMusicRepository repo,
) {
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
  final id = state.pathParameters['id'] ?? state.uri.queryParameters['id'];
  final parsedId = int.tryParse(id ?? '');
  return _resolveById<AlbumsTableData>(
    pageKey: state.pageKey,
    id: id,
    fetchSingle: parsedId != null ? () => repo.getAlbumById(parsedId) : null,
    watch: () => repo.watchAlbums(),
    match: (a) => a.id.toString() == id,
    builder: (context, a) => AlbumDetailScreen(album: a, heroTag: heroTag),
    notFoundMessage: context.l10n.albumNotFoundHint,
  );
}

Page<dynamic> _buildArtistRoute(
  BuildContext context,
  GoRouterState state,
  IMusicRepository repo,
) {
  final artist =
      state.extra is ArtistsTableData ? state.extra as ArtistsTableData : null;
  if (artist != null) {
    return _buildPulsrPageRoute(
      key: state.pageKey,
      child: ArtistDetailScreen(artist: artist),
    );
  }
  final id = state.pathParameters['id'] ?? state.uri.queryParameters['id'];
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
}

Page<dynamic> _buildGenreRoute(
  BuildContext context,
  GoRouterState state,
) {
  GenreItem? genre = state.extra is GenreItem ? state.extra as GenreItem : null;
  final name =
      state.pathParameters['name'] ?? state.uri.queryParameters['name'];
  if (genre == null && name != null && name.isNotEmpty) {
    genre = GenreItem(name: name, songCount: 0);
  }
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
}

Page<dynamic> _buildYearRoute(
  BuildContext context,
  GoRouterState state,
) {
  YearItem? year = state.extra is YearItem ? state.extra as YearItem : null;
  final yearParam =
      state.pathParameters['year'] ?? state.uri.queryParameters['year'];
  final parsedYear = int.tryParse(yearParam ?? '');
  if (year == null && parsedYear != null) {
    year = YearItem(year: parsedYear, songCount: 0);
  }
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
}

Page<dynamic> _buildPlaylistRoute(
  BuildContext context,
  GoRouterState state,
  IMusicRepository repo,
) {
  final playlist = state.extra is PlaylistsTableData
      ? state.extra as PlaylistsTableData
      : null;
  if (playlist != null) {
    return _buildPulsrPageRoute(
      key: state.pageKey,
      child: PlaylistDetailScreen(playlist: playlist),
    );
  }
  final id = state.pathParameters['id'] ?? state.uri.queryParameters['id'];
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
}

GoRouter createRouter(MediaScannerService scannerService,
    [IMusicRepository? musicRepository]) {
  final repo = musicRepository ?? getIt<IMusicRepository>();
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    restorationScopeId: 'pulsr-router',
    observers: [PulsrModalObserver()],
    initialLocation: '/splash',
    redirect: (context, state) {
      if (isExternalAudioLocation(state.uri)) {
        return '/';
      }
      if (!AppConfig.ytmEnabled) {
        const ytmPaths = {
          '/ytm-search',
          '/ytm-explore',
          '/downloads',
          '/online-playlist',
        };
        if (ytmPaths.any(
            (p) => state.uri.path == p || state.uri.path.startsWith('$p/'))) {
          return '/';
        }
      }
      if (AppConfig.isPure) {
        const purePaths = {
          '/radio',
          '/proxy-settings',
          '/party',
          '/scrobble-stats',
        };
        if (purePaths.any(
            (p) => state.uri.path == p || state.uri.path.startsWith('$p/'))) {
          return '/';
        }
      }
      return null;
    },
    errorBuilder: (context, state) {
      if (isExternalAudioLocation(state.uri)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            context.go('/');
          }
        });
        return const Scaffold(
          body: Center(
            child: SizedBox.shrink(),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.pageNotFoundTitle)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_off_outlined,
                  size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: AppSpacing.md),
              Text(context.l10n.pageNotFoundMessage(state.uri.toString()),
                  style: const TextStyle(fontSize: AppFontSize.bodyLarge)),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => context.go('/'),
                child: Text(context.l10n.goHome),
              ),
            ],
          ),
        ),
      );
    },
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const SplashScreen(),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: OnboardingScreen(scannerService: scannerService),
        ),
      ),
      StatefulShellRoute(
        // Branch container is built here (instead of .indexedStack) so hidden
        // tabs can be wrapped in TickerMode: IndexedStack keeps every branch
        // mounted, and without this any endless animation in an invisible tab
        // keeps ticking (battery/GPU waste).
        navigatorContainerBuilder: (context, navigationShell, children) =>
            TickerGatedBranchContainer(
          currentIndex: navigationShell.currentIndex,
          children: children,
        ),
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
                pageBuilder: (context, state) => _buildTabPage(
                  key: state.pageKey,
                  child: const HomeScreen(),
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
                pageBuilder: (context, state) => _buildTabPage(
                  key: state.pageKey,
                  child: LibraryScreen(
                    initialTabName: state.uri.queryParameters['tab'] ??
                        (state.extra is String ? state.extra as String : null),
                  ),
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
                pageBuilder: (context, state) => _buildTabPage(
                  key: state.pageKey,
                  child: SearchScreen(
                    initialQuery: state.uri.queryParameters['q'],
                  ),
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
                pageBuilder: (context, state) => _buildTabPage(
                  key: state.pageKey,
                  child: const PlaylistsScreen(),
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
                pageBuilder: (context, state) => _buildTabPage(
                  key: state.pageKey,
                  child: SettingsScreen(
                    initialCategoryId: state.uri.queryParameters['category'],
                    initialSectionId: state.uri.queryParameters['section'],
                    initialSearchQuery: state.uri.queryParameters['q'],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/party',
        name: 'party',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const PartyScreen(),
        ),
      ),
      GoRoute(
        path: '/now-playing',
        name: 'now-playing',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => PulsrNowPlayingPage<void>(
          key: state.pageKey,
          name: state.name,
          restorationId: state.name,
          child: const NowPlayingScreen(),
        ),
      ),
      GoRoute(
        path: '/album',
        name: 'album',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildAlbumRoute(context, state, repo),
      ),
      GoRoute(
        path: '/album/:id',
        name: 'album-detail',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildAlbumRoute(context, state, repo),
      ),
      GoRoute(
        path: '/artist',
        name: 'artist',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _buildArtistRoute(context, state, repo),
      ),
      GoRoute(
        path: '/artist/:id',
        name: 'artist-detail',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _buildArtistRoute(context, state, repo),
      ),
      GoRoute(
        path: '/genre',
        name: 'genre',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildGenreRoute(context, state),
      ),
      GoRoute(
        path: '/genre/:name',
        name: 'genre-detail',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildGenreRoute(context, state),
      ),
      GoRoute(
        path: '/year',
        name: 'year',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildYearRoute(context, state),
      ),
      GoRoute(
        path: '/year/:year',
        name: 'year-detail',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildYearRoute(context, state),
      ),
      GoRoute(
        path: '/playlist',
        name: 'playlist',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _buildPlaylistRoute(context, state, repo),
      ),
      GoRoute(
        path: '/playlist/manage',
        name: 'manage-playlist',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final playlist = state.extra is PlaylistsTableData
              ? state.extra as PlaylistsTableData
              : null;
          if (playlist != null) {
            return _buildPulsrPageRoute(
              key: state.pageKey,
              child: ManagePlaylistScreen(playlist: playlist),
            );
          }
          final id = state.uri.queryParameters['id'];
          final parsedId = int.tryParse(id ?? '');
          return _resolveById<PlaylistsTableData>(
            pageKey: state.pageKey,
            id: id,
            fetchSingle:
                parsedId != null ? () => repo.getPlaylistById(parsedId) : null,
            watch: () => repo.watchPlaylists(),
            match: (p) => p.id.toString() == id,
            builder: (context, p) => ManagePlaylistScreen(playlist: p),
            notFoundMessage: context.l10n.playlistNotFoundHint,
          );
        },
      ),
      GoRoute(
        path: '/playlist/:id',
        name: 'playlist-detail',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _buildPlaylistRoute(context, state, repo),
      ),

      GoRoute(
        path: '/recents',
        name: 'recents',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const RecentsScreen(),
        ),
      ),
      GoRoute(
        path: '/smart-playlist-builder',
        name: 'smart-playlist-builder',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final initial = state.extra;
          return _buildPulsrPageRoute(
            key: state.pageKey,
            child: SmartPlaylistBuilderScreen(
              initialPlaylist: initial is PlaylistsTableData ? initial : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/queue',
        name: 'queue',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const QueueScreen(),
        ),
      ),
      GoRoute(
        path: '/radio',
        name: 'radio',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const RadioScreen(),
        ),
      ),
      GoRoute(
        path: '/folder',
        name: 'folder',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          var folder =
              state.extra is FolderItem ? state.extra as FolderItem : null;
          if (folder == null) {
            final folderPath = state.uri.queryParameters['path'];
            if (folderPath != null && folderPath.isNotEmpty) {
              final folderName = state.uri.queryParameters['name'] ??
                  folderPath
                      .split(RegExp(r'[/\\]'))
                      .lastWhere((s) => s.isNotEmpty, orElse: () => folderPath);
              folder = FolderItem(
                path: folderPath,
                name: folderName,
                songCount: 0,
                isExcluded: false,
              );
            }
          }
          if (folder == null) {
            return _buildPulsrPageRoute(
              key: state.pageKey,
              child: Scaffold(
                appBar: AppBar(),
                body: Center(child: Text(context.l10n.folderNotFound)),
              ),
            );
          }
          return _buildPulsrPageRoute(
            key: state.pageKey,
            child: FolderDetailScreen(folder: folder),
          );
        },
      ),
      GoRoute(
        path: '/tag-editor',
        name: 'tag-editor',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is List<SongsTableData> && extra.isNotEmpty) {
            return _buildPulsrPageRoute(
              key: state.pageKey,
              child: TagEditorScreen(song: extra.first, batchSongs: extra),
            );
          }
          final song = extra is SongsTableData ? extra : null;
          if (song == null) {
            return _buildPulsrPageRoute(
              key: state.pageKey,
              child: Scaffold(
                appBar: AppBar(),
                body: Center(child: Text(context.l10n.songNotFound)),
              ),
            );
          }
          return _buildPulsrPageRoute(
            key: state.pageKey,
            child: TagEditorScreen(song: song),
          );
        },
      ),
      GoRoute(
        path: '/proxy-settings',
        name: 'proxy-settings',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: ProxySettingsScreen(
            initialImportText:
                state.extra is String ? state.extra as String : null,
          ),
        ),
      ),
      GoRoute(
        path: '/browse',
        name: 'browse',
        redirect: (context, state) =>
            AppConfig.ytmEnabled ? '/ytm-search' : '/search',
      ),
      // Gated: only reachable in an ENABLE_YTM build. In prod this collection-if
      // is const-false, so the route and YtmSearchScreen tree-shake away.
      if (AppConfig.ytmEnabled) ...[
        GoRoute(
          path: '/ytm-search',
          name: 'ytm-search',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (context, state) => _buildPulsrPageRoute(
            key: state.pageKey,
            child: const YtmSearchScreen(),
          ),
        ),
        GoRoute(
          path: '/ytm-explore',
          name: 'ytm-explore',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (context, state) => _buildPulsrPageRoute(
            key: state.pageKey,
            child: const YtmBrowseScreen(),
          ),
        ),
        GoRoute(
          path: '/downloads',
          name: 'downloads',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (context, state) => _buildPulsrPageRoute(
            key: state.pageKey,
            child: const DownloadsScreen(),
          ),
        ),
        GoRoute(
          path: '/online-playlist',
          name: 'online-playlist',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (context, state) {
            final extra = state.extra;
            Widget content;
            if (extra is OnlinePlaylistDetailArgs) {
              content = OnlinePlaylistDetailScreen(args: extra);
            } else if (extra is YtmAccountPlaylist) {
              content = OnlinePlaylistDetailScreen(
                args: OnlinePlaylistDetailArgs(
                  playlistId: extra.playlistId,
                  title: extra.title,
                  subtitle: extra.subtitle,
                  artworkUrl: extra.artworkUrl,
                  kind: OnlineLibraryKind.account,
                ),
              );
            } else if (extra is OnlinePlaylistEntry) {
              content = OnlinePlaylistDetailScreen(
                args: OnlinePlaylistDetailArgs(
                  playlistId: extra.id,
                  title: extra.title,
                  subtitle: extra.uploader,
                  initialTracks: extra.tracks,
                  kind: OnlineLibraryKind.custom,
                ),
              );
            } else {
              final id = state.uri.queryParameters['id'] ??
                  (extra is String ? extra : '');
              final title = state.uri.queryParameters['title'];
              final subtitle = state.uri.queryParameters['subtitle'];
              final artworkUrl = state.uri.queryParameters['artworkUrl'];
              final kind =
                  state.uri.queryParameters['kind'] ?? OnlineLibraryKind.custom;
              content = OnlinePlaylistDetailScreen(
                args: OnlinePlaylistDetailArgs(
                  playlistId: id,
                  title: title,
                  subtitle: subtitle,
                  artworkUrl: artworkUrl,
                  kind: kind,
                ),
              );
            }
            return _buildPulsrPageRoute(
              key: state.pageKey,
              child: content,
            );
          },
        ),
      ],
      GoRoute(
        path: '/artwork-grid',
        name: 'artwork-grid',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const ArtworkGridScreen(),
        ),
      ),
      GoRoute(
        path: '/duplicate-finder',
        name: 'duplicate-finder',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const DuplicateFinderScreen(),
        ),
      ),
      GoRoute(
        path: '/library-stats',
        name: 'library-stats',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const LibraryStatsScreen(),
        ),
      ),
      GoRoute(
        path: '/theme-studio',
        name: 'theme-studio',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const CustomThemeBuilderScreen(),
        ),
      ),
      GoRoute(
        path: '/scrobble-stats',
        name: 'scrobble-stats',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const ScrobbleStatsScreen(),
        ),
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
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const CloudBackupDashboardScreen(),
        ),
      ),
      GoRoute(
        path: '/quran-mode',
        name: 'quran-mode',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const QuranModeScreen(),
        ),
      ),
      GoRoute(
        path: '/karaoke',
        name: 'karaoke',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const KaraokeModeScreen(),
        ),
      ),
      GoRoute(
        path: '/abx',
        name: 'abx',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const AbxScreen(),
        ),
      ),

      GoRoute(
        path: '/favorites',
        name: 'favorites',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const FavoritesScreen(),
        ),
      ),
      GoRoute(
        path: '/hidden-folders',
        name: 'hidden-folders',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _buildPulsrPageRoute(
          key: state.pageKey,
          child: const HiddenFoldersScreen(),
        ),
      ),
    ],
  );
}

