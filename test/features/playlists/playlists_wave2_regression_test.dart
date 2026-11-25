// Wave 2 regression tests for Playlists and Playlist Detail: H-34
// (restoreCustomPlaylist persists to Drift, _runSyncOnlineLibraryCache guards
// empty tracks, PlaylistsScreen always shows Smart Playlists CTA and surfaces
// mutation errors via BlocConsumer, SpotifyImportDialog Cancel button aborts
// active import), H-35 (ManagePlaylistScreen transactional rollback on failure,
// OnlinePlaylistDetailScreen didUpdateWidget & reorder lock & custom rename
// preservation, PlaylistDetailScreen reactive metadata via watchPlaylists).
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/app_error.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/network/connectivity_guard.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/services/spotify_importer_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlist_detail/presentation/manage_playlist_screen.dart';
import 'package:pulsr/features/playlist_detail/presentation/online_playlist_detail_screen.dart';
import 'package:pulsr/features/playlist_detail/presentation/playlist_detail_screen.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:pulsr/features/playlists/cubit/playlist_state.dart';
import 'package:pulsr/features/playlists/presentation/playlists_screen.dart';
import 'package:pulsr/features/playlists/presentation/widgets/spotify_import_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart' hide stubPlayerCubit;
import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _PlaylistUseCases extends Mock implements PlaylistUseCases {}

class _MusicRepo extends Mock implements IMusicRepository {}

class _Account extends Mock implements YtmAccountService {}

class _YtmService extends Mock implements YtmService {}

class _Connectivity extends Mock implements Connectivity {}

class _PlaylistCubit extends Mock implements PlaylistCubit {}

class _GetSongs extends Mock implements GetSongsUseCase {}

class _SpotifyImporter extends Mock implements SpotifyImporterService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(<int>[]);
    registerFallbackValue(const <YtmTrack>[]);
    registerFallbackValue(createTestSong());
  });

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({'smart_playlists_seeded': true});
  });

  tearDown(() async {
    await getIt.reset();
  });

  group(
      'H-34: PlaylistCubit Drift restore, empty-track cache guard, Spotify Cancel',
      () {
    test(
        'restoreCustomPlaylist persists entry to IMusicRepository.cacheOnlinePlaylist',
        () async {
      final useCases = _PlaylistUseCases();
      final repo = _MusicRepo();
      when(() => useCases.watchPlaylists())
          .thenAnswer((_) => const Stream.empty());
      when(() => useCases.watchPlaylistSongs(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => repo.cacheOnlinePlaylist(
            playlistId: any(named: 'playlistId'),
            kind: any(named: 'kind'),
            title: any(named: 'title'),
            author: any(named: 'author'),
            artworkUrl: any(named: 'artworkUrl'),
            tracks: any(named: 'tracks'),
            fullSnapshot: any(named: 'fullSnapshot'),
          )).thenAnswer((_) async => const Right(null));
      getIt.registerSingleton<IMusicRepository>(repo);

      final cubit = PlaylistCubit(playlistUseCases: useCases);
      cubit.restoreCustomPlaylist(
        const OnlinePlaylistEntry(
          id: 'PL_RESTORED',
          title: 'Restored Mix',
          uploader: 'DJ',
          tracks: [],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(() => repo.cacheOnlinePlaylist(
            playlistId: 'PL_RESTORED',
            kind: OnlineLibraryKind.custom,
            title: 'Restored Mix',
            author: 'DJ',
            artworkUrl: null,
            tracks: const <YtmTrack>[],
            fullSnapshot: false,
          )).called(1);
      await cubit.close();
    });

    test(
        '_runSyncOnlineLibraryCache skips cacheOnlinePlaylist when fetched tracks are empty',
        () async {
      final useCases = _PlaylistUseCases();
      final repo = _MusicRepo();
      final account = _Account();
      final ytm = _YtmService();
      final connectivity = _Connectivity();

      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      ConnectivityGuard.setMockConnectivity(connectivity);

      when(() => useCases.watchPlaylists())
          .thenAnswer((_) => const Stream.empty());
      when(() => useCases.watchPlaylistSongs(any()))
          .thenAnswer((_) => const Stream.empty());
      when(() => account.isLoggedIn).thenReturn(false);
      when(() => repo.getOnlinePlaylists())
          .thenAnswer((_) async => const Right(<OnlinePlaylistsTableData>[]));
      when(() => ytm.getPlaylistTracks(any(), limit: any(named: 'limit')))
          .thenAnswer((_) async => const <YtmTrack>[]);

      getIt.registerSingleton<IMusicRepository>(repo);
      getIt.registerSingleton<YtmAccountService>(account);
      getIt.registerSingleton<YtmService>(ytm);

      final cubit = PlaylistCubit(playlistUseCases: useCases);
      cubit.restoreCustomPlaylist(
        const OnlinePlaylistEntry(
          id: 'PL_EMPTY',
          title: 'Empty Fetch',
          uploader: 'U',
          tracks: [],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      clearInteractions(repo);

      await cubit.syncOnlineLibraryCacheForTesting(force: true);

      verifyNever(() => repo.cacheOnlinePlaylist(
            playlistId: any(named: 'playlistId'),
            kind: any(named: 'kind'),
            title: any(named: 'title'),
            author: any(named: 'author'),
            artworkUrl: any(named: 'artworkUrl'),
            sortOrder: any(named: 'sortOrder'),
            tracks: any(named: 'tracks'),
          ));
      await cubit.close();
    });

    testWidgets(
        'PlaylistsScreen always renders Smart Playlists CTA and surfaces error toast',
        (tester) async {
      final cubit = _PlaylistCubit();
      final states = StreamController<PlaylistState>.broadcast();
      addTearDown(states.close);

      final pl = PlaylistsTableData(
        id: 1,
        name: 'My Mix',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
        isSmart: false,
      );

      when(() => cubit.state).thenReturn(PlaylistState(playlists: [pl]));
      when(() => cubit.stream).thenAnswer((_) => states.stream);
      when(() => cubit.clearError()).thenReturn(null);
      getIt.registerSingleton<GetSongsUseCase>(_GetSongs());

      useScreenSize(tester, const Size(800, 1400));
      await tester.pumpWidget(
        screenHarness(
          providers: [
            BlocProvider<PlaylistCubit>.value(value: cubit),
            BlocProvider<PlayerCubit>.value(value: stubPlayerCubit()),
          ],
          child: const PlaylistsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Smart Playlists section header & Create CTA visible even with 0 smart playlists
      expect(find.text('SMART PLAYLISTS'), findsOneWidget);

      // Emit an error while playlists are non-empty -> BlocConsumer shows toast and clears error
      states
          .add(PlaylistState(playlists: [pl], error: uiError('Rename failed')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Rename failed'), findsOneWidget);
      verify(() => cubit.clearError()).called(1);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('SpotifyImportDialog Cancel button aborts active import',
        (tester) async {
      final importer = _SpotifyImporter();
      final useCases = _PlaylistUseCases();
      final fetchCompleter = Completer<
          ({String title, List<SpotifyImportTrack> tracks, bool truncated})>();

      when(() => importer.fetchPlaylistTracks(any()))
          .thenAnswer((_) => fetchCompleter.future);
      getIt.registerSingleton<SpotifyImporterService>(importer);
      getIt.registerSingleton<PlaylistUseCases>(useCases);

      useScreenSize(tester, const Size(800, 1400));
      await tester.pumpWidget(
        screenHarness(
          child: Builder(
            builder: (ctx) => FilledButton(
              onPressed: () => SpotifyImportDialog.show(ctx),
              child: const Text('OPEN_SPOTIFY'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN_SPOTIFY'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
      );
      await tester.pump();

      await tester.tap(find.text('Import'));
      await tester.pump();

      // Cancel button is present while loading
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Completing fetch after cancel must NOT create a playlist
      fetchCompleter.complete((
        title: 'Late Playlist',
        tracks: const [SpotifyImportTrack(title: 'T', artist: 'A')],
        truncated: false,
      ));
      await tester.pump();
      verifyNever(() => useCases.createPlaylist(any()));
    });
  });

  group(
      'H-35: PlaylistDetailScreen reactive watchPlaylists & OnlinePlaylistDetailScreen',
      () {
    testWidgets(
        'PlaylistDetailScreen updates title reactively from watchPlaylists',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'pulsr_hint_song_tile_swipe': true,
      });
      final useCases = _PlaylistUseCases();
      final metaController =
          StreamController<Result<List<PlaylistsTableData>>>.broadcast();
      addTearDown(metaController.close);

      final initial = PlaylistsTableData(
        id: 1,
        name: 'Initial Title',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
        isSmart: false,
      );

      when(() => useCases.watchPlaylistSongs(1))
          .thenAnswer((_) => Stream.value(Right([createTestSong(id: 1)])));
      when(() => useCases.watchPlaylists())
          .thenAnswer((_) => metaController.stream);

      await tester.pumpWidget(
        detailHarness(
          child: PlaylistDetailScreen(
            playlist: initial,
            playlistUseCases: useCases,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Initial Title'), findsWidgets);

      metaController.add(Right([
        initial.copyWith(name: 'Renamed Live Title'),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Renamed Live Title'), findsWidgets);
    });

    testWidgets(
        'ManagePlaylistScreen rolls back added songs in transaction when removal fails',
        (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      getIt.registerSingleton<AppDatabase>(db);

      final useCases = _PlaylistUseCases();
      final getSongs = _GetSongs();
      getIt.registerSingleton<PlaylistUseCases>(useCases);
      getIt.registerSingleton<GetSongsUseCase>(getSongs);

      final s1 = createTestSong(id: 1, title: 'KeepOrRemove');
      final s2 = createTestSong(id: 2, title: 'NewAdd');

      when(() => useCases.watchPlaylistSongs(1))
          .thenAnswer((_) => Stream.value(Right([s1])));
      when(() => getSongs.watchSongs(
              excludedFolders: any(named: 'excludedFolders')))
          .thenAnswer((_) => Stream.value(Right([s1, s2])));

      // addSongsToPlaylist inserts a row into db.playlistsTable inside the transaction,
      // then removeSongFromPlaylist returns Left -> transaction rolls back the DB insert!
      when(() => useCases.addSongsToPlaylist(1, [2])).thenAnswer((_) async {
        await db.into(db.playlistsTable).insert(
              PlaylistsTableCompanion.insert(
                id: const Value(99),
                name: 'ShouldRollback',
              ),
            );
        return const Right(null);
      });
      when(() => useCases.removeSongFromPlaylist(1, 1)).thenAnswer(
          (_) async => const Left(DatabaseFailure('Remove failed')));

      useScreenSize(tester, const Size(800, 1400));
      await tester.pumpWidget(
        screenHarness(
          child: ManagePlaylistScreen(
            playlist: PlaylistsTableData(
              id: 1,
              name: 'Road Trip',
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
              isSmart: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Deselect s1 (remove) and select s2 (add)
      await tester.tap(find.text('KeepOrRemove'));
      await tester.tap(find.text('NewAdd'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Apply Changes'));
      await tester.pumpAndSettle();

      final rows = await db.select(db.playlistsTable).get();
      expect(rows, isEmpty,
          reason: 'AppDatabase transaction must roll back when removal fails');
    });

    testWidgets(
        'OnlinePlaylistDetailScreen didUpdateWidget reloads when playlistId changes',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'pulsr_hint_song_tile_swipe': true,
      });
      final ytm = _YtmService();
      when(() => ytm.getPlaylistTracks(any(), limit: any(named: 'limit')))
          .thenAnswer((_) async => const <YtmTrack>[]);
      getIt.registerSingleton<YtmService>(ytm);

      const t1 = YtmTrack(
          videoId: 'v1',
          title: 'Track From PL1',
          artist: 'A1',
          duration: Duration(minutes: 3));
      const t2 = YtmTrack(
          videoId: 'v2',
          title: 'Track From PL2',
          artist: 'A2',
          duration: Duration(minutes: 3));

      useScreenSize(tester, const Size(800, 1600));
      await tester.pumpWidget(
        screenHarness(
          providers: [
            BlocProvider<PlayerCubit>.value(value: stubPlayerCubit()),
          ],
          child: const Scaffold(
            body: OnlinePlaylistDetailScreen(
              args: OnlinePlaylistDetailArgs(
                playlistId: 'PL1',
                title: 'First Online',
                initialTracks: [t1],
              ),
              isEmbedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First Online'), findsWidgets);
      expect(find.text('Track From PL1'), findsOneWidget);

      await tester.pumpWidget(
        screenHarness(
          providers: [
            BlocProvider<PlayerCubit>.value(value: stubPlayerCubit()),
          ],
          child: const Scaffold(
            body: OnlinePlaylistDetailScreen(
              args: OnlinePlaylistDetailArgs(
                playlistId: 'PL2',
                title: 'Second Online',
                initialTracks: [t2],
              ),
              isEmbedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Second Online'), findsWidgets);
      expect(find.text('Track From PL2'), findsOneWidget);
    });
  });
}
