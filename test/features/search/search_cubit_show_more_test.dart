// test/features/search/search_cubit_show_more_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/utils/search_algorithm_utils.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSearch implements SearchMusicUseCase {
  final List<SongsTableData> songs;
  _MockSearch(this.songs);

  @override
  Stream<Result<List<SongsTableData>>> searchSongs(
    String query, {
    List<String> excludedFolders = const [],
    int limit = 500,
  }) =>
      Stream.value(Right(songs));
}

class _MockFolderUseCases extends Mock implements FolderUseCases {}

SongsTableData _song(int id) => SongsTableData(
      id: id,
      title: 'Beat Track $id',
      artist: 'Artist',
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
  Duration timeout = const Duration(seconds: 5),
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
        .thenAnswer((_) async => const Right(<String>[]));
  });

  test('surfaces a show-more flag instead of silently truncating at 200',
      () async {
    final cubit = SearchCubit(
      searchUseCase: _MockSearch([for (var i = 1; i <= 250; i++) _song(i)]),
      folderUseCases: folders,
    );

    cubit.onQueryChanged('beat');
    await _pumpUntil(() =>
        cubit.state.results.length == SearchAlgorithmUtils.maxResultCount);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(cubit.state.results.length, SearchAlgorithmUtils.maxResultCount);
    expect(cubit.hasMoreResults.value, isTrue);

    await cubit.showMoreResults();
    expect(cubit.state.results.length, 250);
    expect(cubit.hasMoreResults.value, isFalse);

    await cubit.close();
  });

  test('a new query resets the raised cap and the show-more flag', () async {
    final cubit = SearchCubit(
      searchUseCase: _MockSearch([for (var i = 1; i <= 210; i++) _song(i)]),
      folderUseCases: folders,
    );

    cubit.onQueryChanged('beat');
    await _pumpUntil(() => cubit.hasMoreResults.value);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await cubit.showMoreResults();
    expect(cubit.state.results.length, 210);
    expect(cubit.hasMoreResults.value, isFalse);

    cubit.onQueryChanged('other');
    expect(cubit.hasMoreResults.value, isFalse);

    await cubit.close();
  });
}
