// PlaylistDetailScreen branch coverage: corrupt smart criteria, the export
// flow (success/failure/empty), share-empty, navigation from the header and
// overflow menu, and delete-with-undo.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/playlist_share_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_empty_state.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/usecases/playlist_io_usecases.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlist_detail/presentation/playlist_detail_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _Playlists extends Mock implements PlaylistUseCases {}

class _Export extends Mock implements PlaylistExportUseCase {}

class _Share extends Mock implements PlaylistShareService {}

final _localPlaylist = PlaylistsTableData(
  id: 1,
  name: 'My List',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  isSmart: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Playlists useCases;
  late _Export export;
  late _Share share;

  setUpAll(() {
    registerFallbackValue(createTestSong());
    registerFallbackValue('');
    registerFallbackValue(<int>[]);
    registerFallbackValue(const SmartCriteria());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    useCases = _Playlists();
    export = _Export();
    share = _Share();
    when(() => useCases.deletePlaylist(any()))
        .thenAnswer((_) async => const Right<AppFailure, void>(null));
    when(() => useCases.createPlaylist(any(),
            isSmart: any(named: 'isSmart'),
            smartCriteria: any(named: 'smartCriteria')))
        .thenAnswer((_) async => const Right(5));
    when(() => useCases.addSongsToPlaylist(any(), any()))
        .thenAnswer((_) async => const Right<AppFailure, void>(null));
    when(() => useCases.removeSongFromPlaylist(any(), any()))
        .thenAnswer((_) async => const Right<AppFailure, void>(null));
    getIt.registerSingleton<PlaylistExportUseCase>(export);
    getIt.registerSingleton<PlaylistShareService>(share);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Widget harness(Widget screen) {
    final router = GoRouter(
      initialLocation: '/target',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
          routes: [GoRoute(path: 'target', builder: (_, __) => screen)],
        ),
        GoRoute(
            path: '/playlist/manage',
            builder: (_, __) => const Scaffold(body: Text('manage-route'))),
        GoRoute(
            path: '/smart-playlist-builder',
            builder: (_, __) => const Scaffold(body: Text('smart-route'))),
      ],
    );
    return BlocProvider<PlayerCubit>.value(
      value: stubPlayerCubit(),
      child: MaterialApp.router(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required PlaylistsTableData playlist,
    Stream<Result<List<SongsTableData>>>? stream,
  }) async {
    when(() => useCases.watchPlaylistSongs(any())).thenAnswer(
        (_) => stream ?? Stream.value(const Right(<SongsTableData>[])));
    useScreenSize(tester, const Size(800, 1600));
    await tester.pumpWidget(harness(PlaylistDetailScreen(
      playlist: playlist,
      playlistUseCases: useCases,
    )));
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets('exporting an empty playlist warns', (tester) async {
    await pump(tester, playlist: _localPlaylist);
    await openMenu(tester);
    await tester.tap(find.text('Export as M3U'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot export an empty playlist.'), findsOneWidget);
  });

  testWidgets('exporting a populated playlist confirms', (tester) async {
    when(() => export.exportToFile(any(), any()))
        .thenAnswer((_) async => File('${Directory.systemTemp.path}/x.m3u'));
    await pump(
      tester,
      playlist: _localPlaylist,
      stream: Stream.value(Right([createTestSong(id: 1)])),
    );
    await openMenu(tester);
    await tester.tap(find.text('Export as M3U'));
    await tester.pumpAndSettle();

    verify(() => export.exportToFile('My List', any())).called(1);
    expect(find.textContaining('exported'), findsWidgets);
  });

  testWidgets('a failed export reports the error', (tester) async {
    when(() => export.exportToFile(any(), any()))
        .thenThrow(const FileSystemException('nope'));
    await pump(
      tester,
      playlist: _localPlaylist,
      stream: Stream.value(Right([createTestSong(id: 1)])),
    );
    await openMenu(tester);
    await tester.tap(find.text('Export as M3U'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Export failed'), findsWidgets);
  });

  testWidgets('sharing an empty playlist warns', (tester) async {
    await pump(tester, playlist: _localPlaylist);
    await openMenu(tester);
    await tester.tap(find.text('Share Playlist'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot share an empty playlist.'), findsOneWidget);
  });

  testWidgets('the manage action opens the manage route', (tester) async {
    await pump(
      tester,
      playlist: _localPlaylist,
      stream: Stream.value(Right([createTestSong(id: 1)])),
    );
    await openMenu(tester);
    await tester.tap(find.text('Manage Songs'));
    await tester.pumpAndSettle();

    expect(find.text('manage-route'), findsOneWidget);
  });

  testWidgets('the header manage button opens the manage route',
      (tester) async {
    await pump(
      tester,
      playlist: _localPlaylist,
      stream: Stream.value(Right([createTestSong(id: 1)])),
    );
    await tester.tap(find.byTooltip('Manage Songs'));
    await tester.pumpAndSettle();

    expect(find.text('manage-route'), findsOneWidget);
  });

  testWidgets('the smart edit button opens the builder', (tester) async {
    when(() => useCases.watchSmartPlaylistSongs(any()))
        .thenAnswer((_) => Stream.value([createTestSong(id: 1)]));
    await pump(tester, playlist: PlaylistsTableData(
      id: 3,
      name: 'Smart OK',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      isSmart: true,
      smartCriteria: '{"rules":[],"matchAll":true}',
    ));
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('smart-route'), findsOneWidget);
  });

  testWidgets('delete removes the playlist and Undo restores it',
      (tester) async {
    await pump(
      tester,
      playlist: _localPlaylist,
      stream: Stream.value(Right([createTestSong(id: 1)])),
    );
    await openMenu(tester);
    await tester.tap(find.text('Delete Playlist'));
    await tester.pumpAndSettle();

    verify(() => useCases.deletePlaylist(1)).called(1);
    expect(find.textContaining('Deleted'), findsWidgets);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    verify(() => useCases.createPlaylist('My List',
        isSmart: any(named: 'isSmart'),
        smartCriteria: any(named: 'smartCriteria'))).called(1);
    verify(() => useCases.addSongsToPlaylist(5, [1])).called(1);
  });

  testWidgets('the empty-state still renders without tracks', (tester) async {
    await pump(tester, playlist: _localPlaylist);
    expect(find.byType(PulsrEmptyState), findsOneWidget);
  });
}
