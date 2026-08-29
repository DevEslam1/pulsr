// Phase 5 — Search stale-response guard.
//
// A slow response for query 1 must never overwrite a fast response for
// query 2: only the latest generation may emit.
import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';

/// Fake whose per-query streams are supplied by the test.
class FakeSearchMusicUseCase implements SearchMusicUseCase {
  final Map<String, StreamController<Result<List<SongsTableData>>>> streams =
      {};

  @override
  Stream<Result<List<SongsTableData>>> searchSongs(String query,
      {List<String> excludedFolders = const []}) {
    final existing = streams[query];
    if (existing != null) return existing.stream;
    final controller = StreamController<Result<List<SongsTableData>>>();
    streams[query] = controller;
    return controller.stream;
  }

  void emitFor(String query, Result<List<SongsTableData>> result) {
    streams[query]?.add(result);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockFolderUseCases extends Mock implements FolderUseCases {}

SongsTableData _song(int id, String title) => SongsTableData(
      id: id,
      title: title,
      artist: 'Artist',
      album: 'Album',
      durationMs: 1000,
      path: '/storage/emulated/0/Music/$title.mp3',
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSearchMusicUseCase fakeSearch;
  late MockFolderUseCases mockFolders;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeSearch = FakeSearchMusicUseCase();
    mockFolders = MockFolderUseCases();
    when(() => mockFolders.getExcludedFolders())
        .thenAnswer((_) async => const Right([]));
  });

  test('slow response 1 never overwrites fast response 2', () async {
    final cubit = SearchCubit(
      searchUseCase: fakeSearch,
      folderUseCases: mockFolders,
    );
    addTearDown(cubit.close);

    // Query 1: its response will arrive LATE.
    cubit.onQueryChanged('slow query name');
    // Let the 250ms debounce fire and the subscription attach.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Query 2 (latest): response arrives quickly.
    cubit.onQueryChanged('fast query name');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    fakeSearch.emitFor(
        'fast query name', Right([_song(2, 'Fast Query Name Track')]));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(cubit.state.results.map((s) => s.title), ['Fast Query Name Track']);

    // Now the STALE response for query 1 lands.
    fakeSearch.emitFor('slow query name', Right([
      _song(1, 'Slow Query Name Track'),
      _song(3, 'Slow Query Name Album'),
    ]));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(cubit.state.query, 'fast query name');
    expect(cubit.state.results.map((s) => s.title), ['Fast Query Name Track'],
        reason: 'the stale slow response must be discarded');
    expect(cubit.state.isLoading, isFalse);
  });

  test('error responses for stale generations are discarded too', () async {
    final cubit = SearchCubit(
      searchUseCase: fakeSearch,
      folderUseCases: mockFolders,
    );
    addTearDown(cubit.close);

    cubit.onQueryChanged('slow query name');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    cubit.onQueryChanged('fast query name');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    fakeSearch.emitFor('fast query name', Right([_song(2, 'Fast Query Name Track')]));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Stale failure must not clobber the good state.
    fakeSearch.emitFor('slow query name', const Left(DatabaseFailure('boom')));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(cubit.state.errorMessage, isNull,
        reason: 'stale failure must not surface');
    expect(cubit.state.results.map((s) => s.title), ['Fast Query Name Track']);
  });
}
