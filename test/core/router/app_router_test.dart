// Structural coverage for the app router: route table contents, top-level and
// per-route redirects, page/builder closures (including not-found and extra
// branches) and transition builders. Nothing is pumped beyond a bare
// MaterialApp/Builder context, so no screen state or plugin is exercised.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/router/app_router.dart';
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

  Widget runTransition(Page<dynamic> page, BuildContext ctx) {
    final custom = page as CustomTransitionPage<dynamic>;
    return custom.transitionsBuilder(
      ctx,
      const AlwaysStoppedAnimation<double>(1.0),
      const AlwaysStoppedAnimation<double>(0.0),
      const SizedBox.shrink(),
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
            '/online-playlist',
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

      // YTM routes are compile-time gated off in the default flavor.
      expect(paths, isNot(contains('/ytm-search')));
      expect(paths, isNot(contains('/ytm-explore')));
      expect(paths, isNot(contains('/browse')));
      expect(paths, isNot(contains('/downloads')));

      final names =
          goRoutes.map((route) => route.name).whereType<String>().toList();
      expect(names.toSet().length, names.length,
          reason: 'route names must be unique');
      expect(names, contains('home'));
      expect(names, contains('manage-playlist'));
      expect(names, contains('now-playing'));
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
        expect(redirect(context, stateFor(path)), '/', reason: path);
      }
      expect(redirect(context, stateFor('/library')), isNull);
      expect(redirect(context, stateFor('/')), isNull);
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
    testWidgets('construct their screens without side effects', (tester) async {
      await pumpContext(tester);

      expect(
        routeFor('/splash').builder!(context, stateFor('/splash')),
        isA<SplashScreen>(),
      );
      expect(
        routeFor('/onboarding').builder!(context, stateFor('/onboarding')),
        isA<OnboardingScreen>(),
      );
      expect(
        routeFor('/queue').builder!(context, stateFor('/queue')),
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
        final widget = routeFor(path).builder!(context, stateFor(path));
        expect(widget, isA<Widget>(), reason: path);
      }

      // Extra-optional builders with no extra fall back safely.
      expect(
        routeFor('/proxy-settings').builder!(
            context, stateFor('/proxy-settings')),
        isA<ProxySettingsScreen>(),
      );
      expect(
        routeFor('/folder').builder!(context, stateFor('/folder')),
        isA<Scaffold>(),
      );
      expect(
        routeFor('/tag-editor').builder!(context, stateFor('/tag-editor')),
        isA<Scaffold>(),
      );
      expect(
        routeFor('/playlist/manage').builder!(
            context, stateFor('/playlist/manage')),
        isA<Scaffold>(),
      );
      expect(
        routeFor('/smart-playlist-builder').builder!(
            context, stateFor('/smart-playlist-builder')),
        isA<SmartPlaylistBuilderScreen>(),
      );
      expect(
        routeFor('/online-playlist').builder!(
            context, stateFor('/online-playlist')),
        isA<OnlinePlaylistDetailScreen>(),
      );
    });

    testWidgets('honour typed extra payloads', (tester) async {
      await pumpContext(tester);

      final proxy = routeFor('/proxy-settings').builder!(
          context, stateFor('/proxy-settings', extra: '1.2.3.4:80'));
      expect(proxy, isA<ProxySettingsScreen>());
      expect((proxy as ProxySettingsScreen).initialImportText, '1.2.3.4:80');

      const folder = FolderItem(
        path: '/music',
        name: 'Music',
        songCount: 2,
        isExcluded: false,
      );
      expect(
        routeFor('/folder').builder!(
            context, stateFor('/folder', extra: folder)),
        isA<FolderDetailScreen>(),
      );

      final song = _song(1);
      expect(
        routeFor('/tag-editor').builder!(
            context, stateFor('/tag-editor', extra: song)),
        isA<TagEditorScreen>(),
      );
      expect(
        routeFor('/tag-editor').builder!(
            context, stateFor('/tag-editor', extra: [song])),
        isA<TagEditorScreen>(),
      );

      final playlist = _playlist();
      expect(
        routeFor('/playlist/manage').builder!(
            context, stateFor('/playlist/manage', extra: playlist)),
        isA<ManagePlaylistScreen>(),
      );
      expect(
        routeFor('/smart-playlist-builder').builder!(
            context, stateFor('/smart-playlist-builder', extra: playlist)),
        isA<SmartPlaylistBuilderScreen>(),
      );

      final args = const OnlinePlaylistDetailArgs(playlistId: 'PL1');
      expect(
        routeFor('/online-playlist').builder!(
            context, stateFor('/online-playlist', extra: args)),
        isA<OnlinePlaylistDetailScreen>(),
      );
      const accountPlaylist = YtmAccountPlaylist(
        playlistId: 'VLPL2',
        title: 'Account',
        subtitle: 'Sub',
      );
      expect(
        routeFor('/online-playlist').builder!(
            context, stateFor('/online-playlist', extra: accountPlaylist)),
        isA<OnlinePlaylistDetailScreen>(),
      );
      const entry = OnlinePlaylistEntry(
        id: 'PL3',
        title: 'Entry',
        uploader: 'Uploader',
        tracks: [],
      );
      expect(
        routeFor('/online-playlist').builder!(
            context, stateFor('/online-playlist', extra: entry)),
        isA<OnlinePlaylistDetailScreen>(),
      );
      expect(
        routeFor('/online-playlist').builder!(
            context, stateFor('/online-playlist', extra: 'PL4')),
        isA<OnlinePlaylistDetailScreen>(),
      );
    });
  });

  group('page builders', () {
    testWidgets('shell tabs build tab pages with transition builders',
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
        expect(page, isA<CustomTransitionPage<dynamic>>(), reason: path);
        expect(runTransition(page, context), isA<Widget>(), reason: path);
      }
      // Query parameters feed the tab screens.
      routeFor('/library').pageBuilder!(
          context, stateFor('/library?tab=albums'));
      routeFor('/search').pageBuilder!(context, stateFor('/search?q=beatles'));
    });

    testWidgets('reduced motion short-circuits the tab transition',
        (tester) async {
      await pumpContext(tester, disableAnimations: true);
      final page = routeFor('/').pageBuilder!(context, stateFor('/'));
      final result = runTransition(page, context);
      expect(result, isA<SizedBox>());
    });

    testWidgets('now-playing builds its slide transition', (tester) async {
      await pumpContext(tester);
      final page = routeFor('/now-playing').pageBuilder!(
          context, stateFor('/now-playing'));
      expect(page, isA<CustomTransitionPage<dynamic>>());
      expect(runTransition(page, context), isA<Widget>());
    });

    testWidgets('detail pages use the shared pulsr transition', (tester) async {
      await pumpContext(tester);
      final page = routeFor('/album').pageBuilder!(
          context, stateFor('/album', extra: _album()));
      expect(runTransition(page, context), isA<Widget>());
    });

    testWidgets('reduced motion short-circuits the detail transition',
        (tester) async {
      await pumpContext(tester, disableAnimations: true);
      final page = routeFor('/album').pageBuilder!(
          context, stateFor('/album', extra: _album()));
      expect(runTransition(page, context), isA<Widget>());
    });

    testWidgets('album route honours typed extras, maps and fallbacks',
        (tester) async {
      await pumpContext(tester);
      final builder = routeFor('/album').pageBuilder!;

      final typed = builder(context, stateFor('/album', extra: _album()))
          as CustomTransitionPage<dynamic>;
      expect(typed.child, isA<AlbumDetailScreen>());

      final mapped = builder(
        context,
        stateFor('/album', extra: {'album': _album(), 'heroTag': 'hero'}),
      ) as CustomTransitionPage<dynamic>;
      expect(mapped.child, isA<AlbumDetailScreen>());

      final byId = builder(
        context,
        stateFor('/album', pathParameters: {'id': '5'}),
      ) as CustomTransitionPage<dynamic>;
      expect(byId.child, isA<EntityByIdLoader<AlbumsTableData>>());

      final notFound =
          builder(context, stateFor('/album')) as CustomTransitionPage<dynamic>;
      expect(notFound.child, isA<Scaffold>());
    });

    testWidgets('artist route honours extras, ids and fallbacks',
        (tester) async {
      await pumpContext(tester);
      final builder = routeFor('/artist').pageBuilder!;

      final typed = builder(context, stateFor('/artist', extra: _artist()))
          as CustomTransitionPage<dynamic>;
      expect(typed.child, isA<ArtistDetailScreen>());

      final byId = builder(
        context,
        stateFor('/artist', pathParameters: {'id': '6'}),
      ) as CustomTransitionPage<dynamic>;
      expect(byId.child, isA<EntityByIdLoader<ArtistsTableData>>());

      final notFound = builder(context, stateFor('/artist'))
          as CustomTransitionPage<dynamic>;
      expect(notFound.child, isA<Scaffold>());
    });

    testWidgets('genre route honours extras, path names and fallbacks',
        (tester) async {
      await pumpContext(tester);
      final builder = routeFor('/genre').pageBuilder!;

      final typed = builder(
        context,
        stateFor('/genre', extra: const GenreItem(name: 'Rock', songCount: 2)),
      ) as CustomTransitionPage<dynamic>;
      expect(typed.child, isA<GenreDetailScreen>());

      final byName = builder(
        context,
        stateFor('/genre', pathParameters: {'name': 'Jazz'}),
      ) as CustomTransitionPage<dynamic>;
      expect(byName.child, isA<GenreDetailScreen>());

      final notFound =
          builder(context, stateFor('/genre')) as CustomTransitionPage<dynamic>;
      expect(notFound.child, isA<Scaffold>());
    });

    testWidgets('year route honours extras, path years and fallbacks',
        (tester) async {
      await pumpContext(tester);
      final builder = routeFor('/year').pageBuilder!;

      final typed = builder(
        context,
        stateFor('/year', extra: const YearItem(year: 1999, songCount: 1)),
      ) as CustomTransitionPage<dynamic>;
      expect(typed.child, isA<YearDetailScreen>());

      final byYear = builder(
        context,
        stateFor('/year', pathParameters: {'year': '2020'}),
      ) as CustomTransitionPage<dynamic>;
      expect(byYear.child, isA<YearDetailScreen>());

      final notFound =
          builder(context, stateFor('/year')) as CustomTransitionPage<dynamic>;
      expect(notFound.child, isA<Scaffold>());
    });

    testWidgets('playlist route honours extras, ids and fallbacks',
        (tester) async {
      await pumpContext(tester);
      final builder = routeFor('/playlist').pageBuilder!;

      final typed = builder(context, stateFor('/playlist', extra: _playlist()))
          as CustomTransitionPage<dynamic>;
      expect(typed.child, isA<PlaylistDetailScreen>());

      final byId = builder(
        context,
        stateFor('/playlist', pathParameters: {'id': '7'}),
      ) as CustomTransitionPage<dynamic>;
      expect(byId.child, isA<EntityByIdLoader<PlaylistsTableData>>());

      final notFound = builder(context, stateFor('/playlist'))
          as CustomTransitionPage<dynamic>;
      expect(notFound.child, isA<Scaffold>());
    });
  });

  group('error builder', () {
    testWidgets('renders the page-not-found scaffold', (tester) async {
      await pumpContext(tester);
      final errorBuilder = router.routerDelegate.builder.errorBuilder;
      expect(errorBuilder, isNotNull);
      final widget = errorBuilder!(context, stateFor('/does-not-exist'));
      expect(widget, isA<Scaffold>());
    });
  });
}
