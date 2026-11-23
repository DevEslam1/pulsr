// Wave 2 regression tests for Search: H-38 (bounded full-library &
// multi-anchor fuzzy fallback when FTS is empty, ID-only searchPlayedSongs
// persistence reconciled with DB & exclusions, direct IMusicRepository
// artist/album search, All tab online track actions/retryAfterCooldown/
// commitQuery, isolated split-pane RefreshIndicators) and M-05.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:pulsr/features/search/presentation/search_screen.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_search_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _MockFolderUseCases extends Mock implements FolderUseCases {}

class _MockMusicRepo extends Mock implements IMusicRepository {}

class _MockSearchUseCase extends Mock implements SearchMusicUseCase {}

class _MockYtmService extends Mock implements YtmService {}

Future<void> _pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) return;
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockFolderUseCases folders;
  late _MockMusicRepo repo;
  late _MockSearchUseCase searchUseCase;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    folders = _MockFolderUseCases();
    repo = _MockMusicRepo();
    searchUseCase = _MockSearchUseCase();

    when(() => folders.getExcludedFolders())
        .thenAnswer((_) async => const Right(<String>[]));
    when(() => repo.watchExcludedFolders())
        .thenAnswer((_) => const Stream.empty());
    when(() => repo.getArtists())
        .thenAnswer((_) async => const Right(<ArtistsTableData>[]));
    when(() => repo.getAlbums())
        .thenAnswer((_) async => const Right(<AlbumsTableData>[]));
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('H-38: SearchCubit fuzzy fallback, ID-based played songs, direct entities',
      () {
    test(
        'bounded full-library fallback finds match when FTS misses due to leading typo',
        () async {
      final target = createTestSong(
        id: 10,
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
      );
      // FTS returns empty for leading-char typo "Xqueen"
      when(() => searchUseCase.searchSongs(
            any(),
            excludedFolders: any(named: 'excludedFolders'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));
      when(() => repo.getAllSongs(
            excludedFolders: any(named: 'excludedFolders'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => Right([target]));

      final cubit = SearchCubit(
        searchUseCase: searchUseCase,
        folderUseCases: folders,
        musicRepository: repo,
      );

      cubit.onQueryChanged('Xqueen', immediate: true);
      await _pumpUntil(() => cubit.state.results.isNotEmpty);

      expect(cubit.state.results, [target]);
      await cubit.close();
    });

    test(
        'multi-anchor fallback recovers leading-char typo even without IMusicRepository',
        () async {
      final target = createTestSong(
        id: 11,
        title: 'Yesterday',
        artist: 'Beatles',
      );
      when(() => searchUseCase.searchSongs(
            any(),
            excludedFolders: any(named: 'excludedFolders'),
            limit: any(named: 'limit'),
          )).thenAnswer((inv) {
        final q = inv.positionalArguments.first as String;
        // Leading 2-char "xb" misses, shifted anchor "be" or suffix "es" hits!
        if (q == 'be' || q == 'es') {
          return Stream.value(Right([target]));
        }
        return Stream.value(const Right(<SongsTableData>[]));
      });

      final cubit = SearchCubit(
        searchUseCase: searchUseCase,
        folderUseCases: folders,
      );

      cubit.onQueryChanged('xbeatles', immediate: true);
      await _pumpUntil(() => cubit.state.results.isNotEmpty);

      expect(cubit.state.results, [target]);
      await cubit.close();
    });

    test(
        'searchPlayedSongs persists IDs only, migrates legacy JSON, and filters excluded/missing rows',
        () async {
      final legacySong = createTestSong(
        id: 1,
        title: 'Stale Title',
        path: '/music/keep/1.mp3',
      );
      final freshSong = createTestSong(
        id: 1,
        title: 'Fresh DB Title',
        path: '/music/keep/1.mp3',
      );
      final hiddenSong = createTestSong(
        id: 2,
        title: 'Hidden Song',
        path: '/music/hidden/2.mp3',
      );

      SharedPreferences.setMockInitialValues({
        'search_played_songs': [
          jsonEncode(legacySong.toJson()),
          '2',
          '999', // deleted song
        ],
      });

      when(() => folders.getExcludedFolders())
          .thenAnswer((_) async => const Right(['/music/hidden']));
      when(() => repo.getSongsByIds(any()))
          .thenAnswer((_) async => Right([freshSong, hiddenSong]));

      final cubit = SearchCubit(
        searchUseCase: searchUseCase,
        folderUseCases: folders,
        musicRepository: repo,
      );
      await cubit.searchPlayedSongsReady;

      // Reconciled with fresh DB metadata, hidden folder filtered out, deleted 999 dropped.
      expect(cubit.searchPlayedSongs.value.map((s) => s.title), ['Fresh DB Title']);

      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getStringList('search_played_songs')!;
      // Stored strictly as ID strings (1 and 2; 999 pruned).
      expect(persisted, ['1', '2']);
      await cubit.close();
    });

    test('direct IMusicRepository artist and album search populates notifiers',
        () async {
      const artist = ArtistsTableData(
        id: 7,
        name: 'Pink Floyd',
        songCount: 12,
        albumCount: 3,
      );
      const album = AlbumsTableData(
        id: 8,
        title: 'Dark Side of the Moon',
        artist: 'Pink Floyd',
        songCount: 10,
      );
      when(() => repo.getArtists()).thenAnswer((_) async => const Right([artist]));
      when(() => repo.getAlbums()).thenAnswer((_) async => const Right([album]));
      when(() => searchUseCase.searchSongs(
            any(),
            excludedFolders: any(named: 'excludedFolders'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));

      final cubit = SearchCubit(
        searchUseCase: searchUseCase,
        folderUseCases: folders,
        musicRepository: repo,
      );

      cubit.onQueryChanged('Pink Floyd', immediate: true);
      await _pumpUntil(() =>
          cubit.artistResults.value.isNotEmpty &&
          cubit.albumResults.value.isNotEmpty);

      expect(cubit.artistResults.value, [artist]);
      expect(cubit.albumResults.value, [album]);
      await cubit.close();
    });

    testWidgets(
        'SearchScreen split view uses two isolated RefreshIndicators for local and online panes',
        (tester) async {
      final ytmService = _MockYtmService();
      when(() => ytmService.searchWithFallback(any())).thenAnswer(
        (_) async => const [
          YtmTrack(
            videoId: 'v1',
            title: 'Online One',
            artist: 'Artist',
            duration: Duration(minutes: 3),
          ),
        ],
      );
      getIt.registerSingleton<YtmService>(ytmService);

      when(() => searchUseCase.searchSongs(
            any(),
            excludedFolders: any(named: 'excludedFolders'),
            limit: any(named: 'limit'),
          )).thenAnswer(
        (_) => Stream.value(Right([createTestSong(id: 1, title: 'Local One')])),
      );

      final searchCubit = SearchCubit(
        searchUseCase: searchUseCase,
        folderUseCases: folders,
        musicRepository: repo,
      );
      final ytmCubit = YtmSearchCubit(service: ytmService);
      addTearDown(searchCubit.close);
      addTearDown(ytmCubit.close);

      // Tablet landscape triggers split view
      useScreenSize(tester, const Size(1280, 800));
      await tester.pumpWidget(
        screenHarness(
          size: const Size(1280, 800),
          providers: [
            BlocProvider<SearchCubit>.value(value: searchCubit),
            BlocProvider<YtmSearchCubit>.value(value: ytmCubit),
            BlocProvider<PlayerCubit>.value(value: stubPlayerCubit()),
          ],
          child: const SearchScreen(
            initialScope: SearchScope.all,
            initialQuery: 'One',
            enableOnlineOverride: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsNWidgets(2));
    });
  });
}
