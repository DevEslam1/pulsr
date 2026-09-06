import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';

class MockSearchMusicUseCase implements SearchMusicUseCase {
  final List<SongsTableData> mockSongs;

  MockSearchMusicUseCase({this.mockSongs = const []});

  @override
  Stream<Result<List<SongsTableData>>> searchSongs(String query,
      {List<String> excludedFolders = const []}) {
    return Stream.value(Right(mockSongs));
  }
}

class MockFolderUseCases extends Mock implements FolderUseCases {}

/// Waits until [predicate] holds, instead of sleeping for a fixed margin over
/// the cubit's 250 ms debounce.
///
/// A flat `Future.delayed(300ms)` left 50 ms of slack, which is enough on an idle
/// machine and not enough when the whole suite runs its files concurrently — the
/// debounce timer fires late and the assertion reads a state that has not been
/// emitted yet. These tests then failed only in a full run and passed on their
/// own, which reads like a real intermittent bug in search.
Future<void> pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) return; // let the expect() report it
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late MockFolderUseCases mockFolderUseCases;

  setUp(() {
    mockFolderUseCases = MockFolderUseCases();
    when(() => mockFolderUseCases.getExcludedFolders())
        .thenAnswer((_) async => const Right([]));
  });

  group('SearchCubit Tests', () {
    test('Initial state has empty query and results', () {
      final cubit = SearchCubit(
        searchUseCase: MockSearchMusicUseCase(),
        folderUseCases: mockFolderUseCases,
      );
      expect(cubit.state.query, isEmpty);
      expect(cubit.state.results, isEmpty);
      expect(cubit.state.isLoading, isFalse);
    });

    test('onQueryChanged updates query and fetches results', () async {
      final List<SongsTableData> mockSongs = [
        const SongsTableData(
          id: 1,
          title: 'Beat Flow',
          artist: 'Artist A',
          album: 'Album A',
          durationMs: 180000,
          path: '/path/1',
          source: SongSource.local,
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
        ),
      ];
      final useCase = MockSearchMusicUseCase(mockSongs: mockSongs);
      final cubit = SearchCubit(
        searchUseCase: useCase,
        folderUseCases: mockFolderUseCases,
      );

      cubit.onQueryChanged('Beat');
      await pumpUntil(() => cubit.state.results.isNotEmpty);

      expect(cubit.state.query, equals('Beat'));
      expect(cubit.state.results.length, equals(1));
      expect(cubit.state.results.first.title, equals('Beat Flow'));

      await cubit.close();
    });

    test('clearQuery resets query and results', () async {
      final List<SongsTableData> mockSongs = [
        const SongsTableData(
          id: 1,
          title: 'Beat Flow',
          artist: 'Artist A',
          album: 'Album A',
          durationMs: 180000,
          path: '/path/1',
          source: SongSource.local,
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
        ),
      ];
      final cubit = SearchCubit(
        searchUseCase: MockSearchMusicUseCase(mockSongs: mockSongs),
        folderUseCases: mockFolderUseCases,
      );

      cubit.onQueryChanged('Beat');
      await pumpUntil(() => cubit.state.results.isNotEmpty);

      cubit.clearQuery();
      expect(cubit.state.query, isEmpty);
      expect(cubit.state.results, isEmpty);

      await cubit.close();
    });

    test('setFilter applies filter override to results', () async {
      final List<SongsTableData> mockSongs = [
        const SongsTableData(
          id: 1,
          title: 'Beat Flow',
          artist: 'Rihanna',
          album: 'Album A',
          durationMs: 180000,
          path: '/path/1',
          source: SongSource.local,
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
        ),
        const SongsTableData(
          id: 2,
          title: 'Another Song',
          artist: 'Beat Maker',
          album: 'Beats Vol 2',
          durationMs: 200000,
          path: '/path/2',
          source: SongSource.local,
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
        ),
      ];
      final cubit = SearchCubit(
        searchUseCase: MockSearchMusicUseCase(mockSongs: mockSongs),
        folderUseCases: mockFolderUseCases,
      );

      cubit.onQueryChanged('Beat');
      await pumpUntil(() => cubit.state.results.length == 2);

      // Both songs match "beat" somewhere
      expect(cubit.state.results.length, equals(2));

      // Filter by Artists only: only "Beat Maker" matches
      cubit.setFilter('Artists');
      await pumpUntil(() => cubit.state.results.length == 1);
      expect(cubit.state.selectedFilter, equals('Artists'));
      expect(cubit.state.results.length, equals(1));
      expect(cubit.state.results.first.artist, equals('Beat Maker'));

      await cubit.close();
    });

    test('onQueryChanged with whitespace-only query clears results', () async {
      final cubit = SearchCubit(
        searchUseCase: MockSearchMusicUseCase(mockSongs: const [
          SongsTableData(
            id: 1,
            title: 'Beat Flow',
            artist: 'Artist A',
            album: 'Album A',
            durationMs: 180000,
            path: '/path/1',
            source: SongSource.local,
            isFavorite: false,
            isMissing: false,
            isDownloaded: false,
            playCount: 0,
            lastPositionMs: 0,
          ),
        ]),
        folderUseCases: mockFolderUseCases,
      );

      cubit.onQueryChanged('   ');
      // Asserting an absence, so there is nothing to poll for: give the debounce
      // room to fire and prove it produced nothing.
      await Future.delayed(const Duration(seconds: 1));

      expect(cubit.state.query, equals('   '));
      expect(cubit.state.results, isEmpty);
      expect(cubit.state.isLoading, isFalse);

      await cubit.close();
    });
  });
}
