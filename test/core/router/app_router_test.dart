// Structural coverage for the app router: route table contents, top-level and
// per-route redirects, page/builder closures (including not-found and extra
// branches) and transition builders. Nothing is pumped beyond a bare
// MaterialApp/Builder context, so no screen state or plugin is exercised.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/config/app_config.dart';
import 'package:pulsr/core/router/app_router.dart';
import 'package:pulsr/core/theme/pulsr_page_transitions.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/widgets/entity_by_id_loader.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/genre_item.dart';
import 'package:pulsr/domain/models/year_item.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/features/album_detail/presentation/album_detail_screen.dart';
import 'package:pulsr/features/artist_detail/presentation/artist_detail_screen.dart';
import 'package:pulsr/features/folder_detail/presentation/folder_detail_screen.dart';
import 'package:pulsr/features/genre_detail/presentation/genre_detail_screen.dart';
import 'package:pulsr/features/onboarding/presentation/onboarding_screen.dart';
import 'package:pulsr/features/party/presentation/party_screen.dart';
import 'package:pulsr/features/playlist_detail/presentation/manage_playlist_screen.dart';
import 'package:pulsr/features/playlist_detail/presentation/online_playlist_detail_screen.dart';
import 'package:pulsr/features/playlist_detail/presentation/playlist_detail_screen.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:pulsr/features/queue/presentation/queue_screen.dart';
import 'package:pulsr/features/settings/presentation/proxy_settings_screen.dart';
import 'package:pulsr/features/smart_playlist_builder/smart_playlist_builder_screen.dart';
import 'package:pulsr/features/splash/presentation/splash_screen.dart';
import 'package:pulsr/features/tag_editor/tag_editor_screen.dart';
import 'package:pulsr/features/year_detail/presentation/year_detail_screen.dart';

class _MockRepository extends Mock implements IMusicRepository {}

class _MockScanner extends Mock implements MediaScannerService {}

AlbumsTableData _album() => const AlbumsTableData(
      id: 5,
      title: 'Album',
      artist: 'Artist',
      songCount: 2,
    );

ArtistsTableData _artist() => const ArtistsTableData(
      id: 6,
      name: 'Artist',
      songCount: 2,
      albumCount: 1,
    );

PlaylistsTableData _playlist() => PlaylistsTableData(
      id: 7,
      name: 'Playlist',
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 2),
      isSmart: false,
    );

SongsTableData _song(int id) => SongsTableData(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      album: 'Album',
      albumId: 1,
      durationMs: 1000,
      path: '/music/$id.mp3',
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      source: 'local',
      isDownloaded: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GoRouter router;
  late List<GoRoute> goRoutes;
  late StatefulShellRoute shell;
  late BuildContext context;

  setUpAll(() {
    router = createRouter(_MockScanner(), _MockRepository());
    goRoutes = <GoRoute>[];
    shell = router.configuration.routes.whereType<StatefulShellRoute>().single;

    void walk(List<RouteBase> routes) {
      for (final route in routes) {
        if (route is GoRoute) {
          goRoutes.add(route);
          walk(route.routes);
        } else if (route is StatefulShellRoute) {
          for (final branch in route.branches) {
            walk(branch.routes);
          }
        }
      }
    }

    walk(router.configuration.routes);
  });

  GoRoute routeFor(String path) =>
      goRoutes.firstWhere((route) => route.path == path);

  GoRouterState stateFor(
    String location, {
    Object? extra,
    Map<String, String> pathParameters = const {},
  }) {
    final uri = Uri.parse(location);
    return GoRouterState(
      router.configuration,
      uri: uri,
      matchedLocation: uri.path,
      fullPath: uri.path,
      pathParameters: pathParameters,
      extra: extra,
      pageKey: ValueKey<String>(uri.path),
    );
  }

  Future<void> pumpContext(WidgetTester tester,
      {bool disableAnimations = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  group('route table', () {
    test('contains every non-YTM route with unique names', () {
      final paths = goRoutes.map((route) => route.path).toSet();
      expect(
          paths,
          containsAll(<String>[
            '/splash',
            '/onboarding',
            '/',
            '/library',
            '/search',
            '/playlists',
            '/settings',
            '/now-playing',
            '/album',
            '/artist',
            '/genre',
            '/year',
            '/playlist',
            '/playlist/manage',
            '/recents',
            '/smart-playlist-builder',
            '/queue',
            '/radio',
            '/folder',
            '/tag-editor',
            '/proxy-settings',
            '/artwork-grid',
            '/duplicate-finder',
            '/library-stats',
            '/theme-studio',
            '/scrobble-stats',
            '/cloud-backup-dashboard',
            '/quran-mode',
            '/favorites',
            '/hidden-folders',
          ]));

      // YTM routes are compile-time gated; /browse always redirects.
      if (AppConfig.ytmEnabled) {
        expect(
            paths,
            containsAll(<String>[
              '/ytm-search',
              '/ytm-explore',
              '/online-playlist',
              '/downloads',
              '/browse',
            ]));
      } else {
        expect(paths, isNot(contains('/ytm-search')));
        expect(paths, isNot(contains('/ytm-explore')));
        expect(paths, isNot(contains('/online-playlist')));
        expect(paths, isNot(contains('/downloads')));
        expect(paths, contains('/browse'));
      }

      final names =
          goRoutes.map((route) => route.name).whereType<String>().toList();
      expect(names.toSet().length, names.length,
          reason: 'route names must be unique');
      expect(names, contains('home'));
      expect(names, contains('manage-playlist'));
      expect(names, contains('now-playing'));
      expect(names, contains('browse'));
    });

    test('shell exposes the five expected tab branches', () {
      expect(shell.branches, hasLength(5));
      final tabPaths = shell.branches
          .expand((branch) => branch.routes)
          .whereType<GoRoute>()
          .map((route) => route.path)
          .toList();
      expect(tabPaths, ['/', '/library', '/search', '/playlists', '/settings']);
      for (final route in shell.branches
          .expand((branch) => branch.routes)
          .whereType<GoRoute>()) {
        expect(route.parentNavigatorKey, isNull);
      }
    });

    test('root-level detail routes attach to the root navigator', () {
      for (final path in [
        '/now-playing',
        '/album',
        '/artist',
        '/genre',
        '/year',
        '/playlist',
        '/queue',
        '/radio',
      ]) {
        expect(routeFor(path).parentNavigatorKey, same(rootNavigatorKey),
            reason: path);
      }
      expect(routeFor('/splash').parentNavigatorKey, isNull);
      expect(routeFor('/onboarding').parentNavigatorKey, isNull);
    });

    test('every route has a builder, page builder or redirect', () {
      for (final route in goRoutes) {
        expect(
          route.builder != null ||
              route.pageBuilder != null ||
              route.redirect != null,
          isTrue,
          reason: 'route ${route.path} is not buildable',
        );
      }
    });
  });

  group('redirects', () {
    testWidgets('top-level redirect hides YTM paths in non-YTM builds',
        (tester) async {
      await pumpContext(tester);
      final redirect = router.configuration.topRedirect;
      for (final path in [
        '/ytm-search',
        '/ytm-explore',
        '/downloads',
        '/online-playlist',
      ]) {
        expect(redirect(context, stateFor(path)),
            AppConfig.ytmEnabled ? null : '/',
            reason: path);
      }
      expect(redirect(context, stateFor('/library')), isNull);
      expect(redirect(context, stateFor('/')), isNull);
    });

    testWidgets('top-level redirect redirects external audio intents to home',
        (tester) async {
      await pumpContext(tester);
      final redirect = router.configuration.topRedirect;
      const externalLocations = [
        'file:///storage/emulated/0/Music/track.mp3',
        'content://media/external/audio/media/42',
        '/sdcard/Music/song.wav',
        '/storage/emulated/0/Download/song.flac',
        '/storage/audio/song.ogg',
        '/music/sample.m4a',
        '/music/TRACK.MP3',
      ];
      for (final loc in externalLocations) {
        expect(redirect(context, stateFor(loc)), '/', reason: loc);
      }
    });

    testWidgets('/browse redirect follows the YTM build gate', (tester) async {
      await pumpContext(tester);
      final redirect = routeFor('/browse').redirect;
      expect(redirect, isNotNull);
      expect(redirect!(context, stateFor('/browse')),
          AppConfig.ytmEnabled ? '/ytm-search' : '/search');
    });

    testWidgets('cloud backup redirect follows AppConfig.isCloudSyncAllowed',
        (tester) async {
      await pumpContext(tester);
      final redirect = routeFor('/cloud-backup-dashboard').redirect;
      expect(redirect, isNotNull);
      expect(
        redirect!(context, stateFor('/cloud-backup-dashboard')),
        isNull,
      );
    });
  });

  group('simple widget builders', () {
    Widget buildRouteWidget(
        GoRoute route, BuildContext context, GoRouterState state) {
      if (route.pageBuilder != null) {
        final page = route.pageBuilder!(context, state);
        if (page is CustomTransitionPage) return page.child;
        if (page is MaterialPage) return page.child;
      }
      if (route.builder != null) {
        return route.builder!(context, state);
      }
      throw StateError(
          'Route ${route.path} has neither builder nor pageBuilder');
    }

    testWidgets('construct their screens without side effects', (tester) async {
      await pumpContext(tester);

      expect(
        buildRouteWidget(routeFor('/splash'), context, stateFor('/splash')),
        isA<SplashScreen>(),
      );
      expect(
        buildRouteWidget(
            routeFor('/onboarding'), context, stateFor('/onboarding')),
        isA<OnboardingScreen>(),
      );
      expect(
        buildRouteWidget(routeFor('/queue'), context, stateFor('/queue')),
        isA<QueueScreen>(),
      );

      for (final path in [
        '/recents',
        '/radio',
        '/artwork-grid',
        '/duplicate-finder',
        '/library-stats',
        '/theme-studio',
        '/scrobble-stats',
        '/cloud-backup-dashboard',
        '/quran-mode',
        '/favorites',
        '/hidden-folders',
      ]) {
        final widget =
            buildRouteWidget(routeFor(path), context, stateFor(path));
        expect(widget, isA<Widget>(), reason: path);
      }

      // Extra-optional builders with no extra fall back safely with an AppBar.
      expect(
        buildRouteWidget(
            routeFor('/proxy-settings'), context, stateFor('/proxy-settings')),
        isA<ProxySettingsScreen>(),
      );
      final folderFallback =
          buildRouteWidget(routeFor('/folder'), context, stateFor('/folder'));
      expect(folderFallback, isA<Scaffold>());
      expect((folderFallback as Scaffold).appBar, isNotNull);

      final tagFallback = buildRouteWidget(
          routeFor('/tag-editor'), context, stateFor('/tag-editor'));
      expect(tagFallback, isA<Scaffold>());
      expect((tagFallback as Scaffold).appBar, isNotNull);

      final playlistFallback = buildRouteWidget(
          routeFor('/playlist/manage'), context, stateFor('/playlist/manage'));
      expect(playlistFallback, isA<Scaffold>());
      expect((playlistFallback as Scaffold).appBar, isNotNull);

      expect(
        buildRouteWidget(routeFor('/smart-playlist-builder'), context,
            stateFor('/smart-playlist-builder')),
        isA<SmartPlaylistBuilderScreen>(),
      );
      if (AppConfig.ytmEnabled) {
        expect(
          buildRouteWidget(routeFor('/online-playlist'), context,
              stateFor('/online-playlist')),
          isA<OnlinePlaylistDetailScreen>(),
        );
      }
    });

    testWidgets('honour typed extra payloads', (tester) async {
      await pumpContext(tester);

      final proxy = buildRouteWidget(routeFor('/proxy-settings'), context,
          stateFor('/proxy-settings', extra: '1.2.3.4:80'));
      expect(proxy, isA<ProxySettingsScreen>());
      expect((proxy as ProxySettingsScreen).initialImportText, '1.2.3.4:80');

      const folder = FolderItem(
        path: '/music',
        name: 'Music',
        songCount: 2,
        isExcluded: false,
      );
      expect(
        buildRouteWidget(
            routeFor('/folder'), context, stateFor('/folder', extra: folder)),
        isA<FolderDetailScreen>(),
      );

      final song = _song(1);
      expect(
        buildRouteWidget(routeFor('/tag-editor'), context,
            stateFor('/tag-editor', extra: song)),
        isA<TagEditorScreen>(),
      );
      expect(
        buildRouteWidget(routeFor('/tag-editor'), context,
            stateFor('/tag-editor', extra: [song])),
        isA<TagEditorScreen>(),
      );

      final playlist = _playlist();
      expect(
        buildRouteWidget(routeFor('/playlist/manage'), context,
            stateFor('/playlist/manage', extra: playlist)),
        isA<ManagePlaylistScreen>(),
      );
      expect(
        buildRouteWidget(routeFor('/smart-playlist-builder'), context,
            stateFor('/smart-playlist-builder', extra: playlist)),
        isA<SmartPlaylistBuilderScreen>(),
      );

      if (AppConfig.ytmEnabled) {
        final args = const OnlinePlaylistDetailArgs(playlistId: 'PL1');
        expect(
          buildRouteWidget(routeFor('/online-playlist'), context,
              stateFor('/online-playlist', extra: args)),
          isA<OnlinePlaylistDetailScreen>(),
        );
        const accountPlaylist = YtmAccountPlaylist(
          playlistId: 'VLPL2',
          title: 'Account',
          subtitle: 'Sub',
        );
        expect(
          buildRouteWidget(routeFor('/online-playlist'), context,
              stateFor('/online-playlist', extra: accountPlaylist)),
          isA<OnlinePlaylistDetailScreen>(),
        );
        const entry = OnlinePlaylistEntry(
          id: 'PL3',
          title: 'Entry',
          uploader: 'Uploader',
          tracks: [],
        );
        expect(
          buildRouteWidget(routeFor('/online-playlist'), context,
              stateFor('/online-playlist', extra: entry)),
          isA<OnlinePlaylistDetailScreen>(),
        );
        expect(
          buildRouteWidget(routeFor('/online-playlist'), context,
              stateFor('/online-playlist', extra: 'PL4')),
          isA<OnlinePlaylistDetailScreen>(),
        );
      }
    });
  });

  group('page builders', () {
    testWidgets('shell tabs build tab pages with MaterialPage',
        (tester) async {
      await pumpContext(tester);
      for (final path in [
        '/',
        '/library',
        '/search',
        '/playlists',
        '/settings'
      ]) {
        final page = routeFor(path).pageBuilder!(context, stateFor(path));
        expect(page, isA<MaterialPage<void>>(), reason: path);
        expect((page as MaterialPage<void>).child, isA<Widget>(), reason: path);
      }
      // Query parameters feed the tab screens.
      routeFor('/library').pageBuilder!(
          context, stateFor('/library?tab=albums'));
      routeFor('/search').pageBuilder!(context, stateFor('/search?q=beatles'));
    });

    testWidgets('now-playing builds its route with PulsrNowPlayingPage', (tester) async {
      await pumpContext(tester);
      final page = routeFor('/now-playing').pageBuilder!(
          context, stateFor('/now-playing'));
      expect(page, isA<PulsrNowPlayingPage<void>>());
      final route = (page as PulsrNowPlayingPage<void>).createRoute(context);
      expect(route, isA<Route<void>>());
    });

    testWidgets('detail pages use MaterialPage with restorationId', (tester) async {
      await pumpContext(tester);
      final page = routeFor('/album').pageBuilder!(
          context, stateFor('/album', extra: _album()));
      expect(page, isA<MaterialPage<void>>());
      expect((page as MaterialPage<void>).restorationId, isNotNull);
    });

    testWidgets('album route honours typed extras, maps and fallbacks',
        (tester) async {
      await pumpContext(tester);
      final builder = routeFor('/album').pageBuilder!;

      final typed = builder(context, stateFor('/album', extra: _album()))
          as MaterialPage<void>;
      expect(typed.child, isA<AlbumDetailScreen>());

      final mapped = builder(
        context,
        stateFor('/album', extra: {'album': _album(), 'heroTag': 'hero'}),
      ) as MaterialPage<void>;
      expect(mapped.child, isA<AlbumDetailScreen>());

      final byId = builder(
        context,
        stateFor('/album', pathParameters: {'id': '5'}),
      ) as MaterialPage<void>;
      expect(byId.child, isA<EntityByIdLoader<AlbumsTableData>>());

      final notFound =
          builder(context, stateFor('/album')) as MaterialPage<void>;
      expect(notFound.child, isA<Scaffold>());
    });

    testWidgets('artist route honours extras, ids and fallbacks',
        (tester) async {
      await pumpContext(tester);
      final builder = routeFor('/artist').pageBuilder!;

      final typed = builder(context, stateFor('/artist', extra: _artist()))
          as MaterialPage<void>;
      expect(typed.child, isA<ArtistDetailScreen>());

      final byId = builder(
        context,
        stateFor('/artist', pathParameters: {'id': '6'}),
      ) as MaterialPage<void>;
      expect(byId.child, isA<EntityByIdLoader<ArtistsTableData>>());

      final notFound = builder(context, stateFor('/artist'))
          as MaterialPage<void>;
      expect(notFound.child, isA<Scaffold>());
    });

    testWidgets('genre route honours extras, path names and fallbacks',
        (tester) async {
      await pumpContext(tester);
      final builder = routeFor('/genre').pageBuilder!;

      final typed = builder(
        context,
        stateFor('/genre', extra: const GenreItem(name: 'Rock', songCount: 2)),
      ) as MaterialPage<void>;
      expect(typed.child, isA<GenreDetailScreen>());

      final byName = builder(
        context,
        stateFor('/genre', pathParameters: {'name': 'Jazz'}),
      ) as MaterialPage<void>;
      expect(byName.child, isA<GenreDetailScreen>());

      final notFound =
          builder(context, stateFor('/genre')) as MaterialPage<void>;
      expect(notFound.child, isA<Scaffold>());
    });

    testWidgets('year route honours extras, path years and fallbacks',
        (tester) async {
      await pumpContext(tester);
      final builder = routeFor('/year').pageBuilder!;

      final typed = builder(
        context,
        stateFor('/year', extra: const YearItem(year: 1999, songCount: 1)),
      ) as MaterialPage<void>;
      expect(typed.child, isA<YearDetailScreen>());

      final byYear = builder(
        context,
        stateFor('/year', pathParameters: {'year': '2020'}),
      ) as MaterialPage<void>;
      expect(byYear.child, isA<YearDetailScreen>());

      final notFound =
          builder(context, stateFor('/year')) as MaterialPage<void>;
      expect(notFound.child, isA<Scaffold>());
    });

    testWidgets('playlist route honours extras, ids and fallbacks',
        (tester) async {
      await pumpContext(tester);
      final builder = routeFor('/playlist').pageBuilder!;

      final typed = builder(context, stateFor('/playlist', extra: _playlist()))
          as MaterialPage<void>;
      expect(typed.child, isA<PlaylistDetailScreen>());

      final byId = builder(
        context,
        stateFor('/playlist', pathParameters: {'id': '7'}),
      ) as MaterialPage<void>;
      expect(byId.child, isA<EntityByIdLoader<PlaylistsTableData>>());

      final notFound = builder(context, stateFor('/playlist'))
          as MaterialPage<void>;
      expect(notFound.child, isA<Scaffold>());
    });

    testWidgets('/party/:code passes code and server query param to PartyScreen',
        (tester) async {
      await pumpContext(tester);
      final route = routeFor('/party/:code');
      expect(route.parentNavigatorKey, same(rootNavigatorKey));
      final page = route.pageBuilder!(
        context,
        stateFor(
          '/party/ABC123?server=https%3A%2F%2Fparty.example.com',
          pathParameters: const {'code': 'ABC123'},
        ),
      ) as MaterialPage<void>;
      expect(page.child, isA<PartyScreen>());
      final screen = page.child as PartyScreen;
      expect(screen.initialCode, 'ABC123');
      expect(screen.initialServerUrl, 'https://party.example.com');
    });
  });

  group('error builder', () {
    testWidgets('renders the page-not-found scaffold', (tester) async {
      await pumpContext(tester);
      final errorBuilder = router.routerDelegate.builder.errorBuilder;
      expect(errorBuilder, isNotNull);
      final widget = errorBuilder!(context, stateFor('/does-not-exist'));
      expect(widget, isA<Scaffold>());
      final scaffold = widget as Scaffold;
      expect(scaffold.appBar, isNotNull);
    });

    testWidgets('falls back silently without 404 page for external audio',
        (tester) async {
      await pumpContext(tester);
      final errorBuilder = router.routerDelegate.builder.errorBuilder;
      expect(errorBuilder, isNotNull);
      final widget = errorBuilder!(
          context, stateFor('file:///storage/emulated/0/Music/song.mp3'));
      expect(widget, isA<Scaffold>());
      final scaffold = widget as Scaffold;
      expect(scaffold.appBar, isNull);
    });
  });

  group('isExternalAudioLocation', () {
    test('matches file and content schemes', () {
      expect(
          isExternalAudioLocation(
              Uri.parse('file:///storage/emulated/0/track.mp3')),
          isTrue);
      expect(
          isExternalAudioLocation(
              Uri.parse('content://media/external/audio/media/123')),
          isTrue);
    });

    test('matches /sdcard/ and /storage/ prefixes', () {
      expect(isExternalAudioLocation(Uri.parse('/sdcard/Music/test.wav')),
          isTrue);
      expect(
          isExternalAudioLocation(
              Uri.parse('/storage/emulated/0/Download/song.flac')),
          isTrue);
    });

    test('matches audio extensions', () {
      expect(isExternalAudioLocation(Uri.parse('/music/track.wav')), isTrue);
      expect(isExternalAudioLocation(Uri.parse('/music/track.mp3')), isTrue);
      expect(isExternalAudioLocation(Uri.parse('/music/track.ogg')), isTrue);
      expect(isExternalAudioLocation(Uri.parse('/music/track.flac')), isTrue);
      expect(isExternalAudioLocation(Uri.parse('/music/track.m4a')), isTrue);
      expect(isExternalAudioLocation(Uri.parse('/music/TRACK.MP3')), isTrue);
    });

    test('returns false for regular internal routes', () {
      expect(isExternalAudioLocation(Uri.parse('/')), isFalse);
      expect(isExternalAudioLocation(Uri.parse('/library')), isFalse);
      expect(isExternalAudioLocation(Uri.parse('/search')), isFalse);
      expect(isExternalAudioLocation(Uri.parse('/settings')), isFalse);
      expect(isExternalAudioLocation(Uri.parse('/album/42')), isFalse);
      expect(isExternalAudioLocation(Uri.parse('/does-not-exist')), isFalse);
    });
  });
}
