import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:pulsr/features/search/cubit/search_state.dart';

class MockSearchMusicUseCase extends Mock implements SearchMusicUseCase {}
class MockFolderUseCases extends Mock implements FolderUseCases {}

void main() {
  late MockSearchMusicUseCase mockSearchUseCase;
  late MockFolderUseCases mockFolderUseCases;
  late List<SongsTableData> testSongs;

  setUp(() {
    mockSearchUseCase = MockSearchMusicUseCase();
    mockFolderUseCases = MockFolderUseCases();

    testSongs = [
      const SongsTableData(
        id: 1,
        title: 'Fix You',
        artist: 'Coldplay',
        album: 'X&Y',
        durationMs: 295000,
        path: '/storage/music/fix_you.mp3',
        source: SongSource.local,
        isFavorite: true,
        isMissing: false,
        isDownloaded: false,
        playCount: 10,
        lastPositionMs: 0,
      ),
      const SongsTableData(
        id: 2,
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        durationMs: 354000,
        path: '/storage/music/bohemian.mp3',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 5,
        lastPositionMs: 0,
      ),
      const SongsTableData(
        id: 3,
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        album: 'Divide',
        durationMs: 233000,
        path: '/storage/music/shape.mp3',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 2,
        lastPositionMs: 0,
      ),
    ];

    when(() => mockFolderUseCases.getExcludedFolders()).thenAnswer((_) async => const Right(<String>[]));
    when(() => mockSearchUseCase.searchSongs(any(), excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) => Stream.value(Right(testSongs)));
  });

  group('Fuzzy Search Tests', () {
    blocTest<SearchCubit, SearchState>(
      'matches artist with typo using Levenshtein distance ("Clodplay" -> "Coldplay")',
      build: () => SearchCubit(
        searchUseCase: mockSearchUseCase,
        folderUseCases: mockFolderUseCases,
      ),
      act: (cubit) async {
        cubit.onQueryChanged('Clodplay');
        await Future.delayed(const Duration(milliseconds: 300));
      },
      expect: () => [
        const SearchState(query: 'Clodplay'),
        const SearchState(query: 'Clodplay', isLoading: true),
        predicate<SearchState>((state) {
          return !state.isLoading &&
              state.results.length == 1 &&
              state.results.first.artist == 'Coldplay';
        }),
      ],
    );

    blocTest<SearchCubit, SearchState>(
      'matches title with word typo ("Bohemain" -> "Bohemian Rhapsody")',
      build: () => SearchCubit(
        searchUseCase: mockSearchUseCase,
        folderUseCases: mockFolderUseCases,
      ),
      act: (cubit) async {
        cubit.onQueryChanged('Bohemain');
        await Future.delayed(const Duration(milliseconds: 300));
      },
      expect: () => [
        const SearchState(query: 'Bohemain'),
        const SearchState(query: 'Bohemain', isLoading: true),
        predicate<SearchState>((state) {
          return !state.isLoading &&
              state.results.length == 1 &&
              state.results.first.title == 'Bohemian Rhapsody';
        }),
      ],
    );
  });
}
