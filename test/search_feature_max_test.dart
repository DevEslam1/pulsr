import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';

/// C-02 / C-04 / C-05: search feature maximization (suggestions, filter
/// persistence, saved searches).
class _MockSearch implements SearchMusicUseCase {
  final List<SongsTableData> songs;
  _MockSearch([this.songs = const []]);

  @override
  Stream<Result<List<SongsTableData>>> searchSongs(
    String query, {
    List<String> excludedFolders = const [],
    int limit = 500,
  }) =>
      Stream.value(Right(songs));
}

class _MockFolderUseCases extends Mock implements FolderUseCases {}

SongsTableData _song(int id, String title, String artist) => SongsTableData(
      id: id,
      title: title,
      artist: artist,
      album: 'Album',
      durationMs: 200000,
      path: '/music/$id.mp3',
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );

Future<void> _pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late _MockFolderUseCases folders;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    folders = _MockFolderUseCases();
    when(() => folders.getExcludedFolders())
        .thenAnswer((_) async => const Right([]));
  });

  group('C-02 suggestions', () {
    test('combines history and library prefixes, capped at suggestionMax',
        () async {
      SharedPreferences.setMockInitialValues({
        'search_history': ['Beat', 'Beatles'],
      });
      final cubit = SearchCubit(
        searchUseCase: _MockSearch([
          _song(1, 'Beat Flow', 'Beat Maker'),
          _song(2, 'Beat Drop', 'Beat Maker'),
          _song(3, 'Beach', 'Someone'),
        ]),
        folderUseCases: folders,
      );
      await _pumpUntil(() => cubit.state.history.isNotEmpty);

      final suggestions = await cubit.suggestionsFor('Bea');
      expect(suggestions.length,
          lessThanOrEqualTo(SearchCubit.suggestionMax));
      expect(suggestions, contains('Beat'));
      expect(suggestions, contains('Beat Flow'));
      await cubit.close();
    });

    test('includes artist-name prefix matches', () async {
      final cubit = SearchCubit(
        searchUseCase: _MockSearch([_song(1, 'Song X', 'Beat Maker')]),
        folderUseCases: folders,
      );
      final suggestions = await cubit.suggestionsFor('Beat');
      expect(suggestions, contains('Beat Maker'));
      await cubit.close();
    });

    test('empty/whitespace query yields no suggestions', () async {
      final cubit = SearchCubit(
        searchUseCase: _MockSearch(),
        folderUseCases: folders,
      );
      expect(await cubit.suggestionsFor('   '), isEmpty);
      await cubit.close();
    });
  });

  group('C-04 filter persistence', () {
    test('setFilter persists and is reloaded by a new cubit', () async {
      final cubit = SearchCubit(
        searchUseCase: _MockSearch(),
        folderUseCases: folders,
      );
      cubit.setFilter('FLAC');
      await _pumpUntil(() => cubit.state.selectedFilter == 'FLAC');
      // Let the fire-and-forget prefs write land.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final reloaded = SearchCubit(
        searchUseCase: _MockSearch(),
        folderUseCases: folders,
      );
      await _pumpUntil(() => reloaded.state.selectedFilter == 'FLAC');
      expect(reloaded.state.selectedFilter, 'FLAC');

      await cubit.close();
      await reloaded.close();
    });
  });

  group('C-05 saved searches', () {
    test('save/remove round-trips including separator chars', () async {
      final cubit = SearchCubit(
        searchUseCase: _MockSearch(),
        folderUseCases: folders,
      );
      cubit.onQueryChanged('Beat|Flow');
      cubit.setFilter('MP3');
      await _pumpUntil(() => cubit.state.query == 'Beat|Flow');

      await cubit.saveCurrentSearch();
      expect(cubit.savedSearches.value.length, 1);

      final decoded =
          SearchCubit.decodeSavedSearch(cubit.savedSearches.value.first);
      expect(decoded.query, 'Beat|Flow');
      expect(decoded.filter, 'MP3');

      await cubit.removeSavedSearch(cubit.savedSearches.value.first);
      expect(cubit.savedSearches.value, isEmpty);
      await cubit.close();
    });

    test('dedupes identical saved searches', () async {
      final cubit = SearchCubit(
        searchUseCase: _MockSearch(),
        folderUseCases: folders,
      );
      cubit.onQueryChanged('Rock');
      await _pumpUntil(() => cubit.state.query == 'Rock');
      await cubit.saveCurrentSearch();
      await cubit.saveCurrentSearch();
      expect(cubit.savedSearches.value.length, 1);
      await cubit.close();
    });

    test('decodeSavedSearch tolerates malformed entries', () {
      final decoded = SearchCubit.decodeSavedSearch('plain query');
      expect(decoded.query, 'plain query');
      expect(decoded.filter, 'All');
    });
  });
}
