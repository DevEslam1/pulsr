// test/search_cubit_test.dart
import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';

class MockSearchMusicUseCase implements SearchMusicUseCase {
  final List<SongsTableData> mockSongs;

  MockSearchMusicUseCase({this.mockSongs = const []});

  @override
  Stream<Result<List<SongsTableData>>> searchSongs(String query, {List<String> excludedFolders = const []}) {
    return Stream.value(Right(mockSongs));
  }
}

void main() {
  group('SearchCubit Tests', () {
    test('Initial state has empty query and results', () {
      final cubit = SearchCubit(searchUseCase: MockSearchMusicUseCase());
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
          isFavorite: false,
          playCount: 0,
          lastPositionMs: 0,
        ),
      ];
      final useCase = MockSearchMusicUseCase(mockSongs: mockSongs);
      final cubit = SearchCubit(searchUseCase: useCase);

      cubit.onQueryChanged('Beat');
      await Future.delayed(const Duration(milliseconds: 300));

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
          isFavorite: false,
          playCount: 0,
          lastPositionMs: 0,
        ),
      ];
      final cubit = SearchCubit(searchUseCase: MockSearchMusicUseCase(mockSongs: mockSongs));

      cubit.onQueryChanged('Beat');
      await Future.delayed(const Duration(milliseconds: 300));

      cubit.clearQuery();
      expect(cubit.state.query, isEmpty);
      expect(cubit.state.results, isEmpty);

      await cubit.close();
    });
  });
}
