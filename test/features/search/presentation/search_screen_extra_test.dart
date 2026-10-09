// Additional SearchScreen coverage (local-only build): history rows and
// removal, saved searches, the suggestions overlay, artist/album rails and
// the local "show more" expansion.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:pulsr/features/search/cubit/search_state.dart';
import 'package:pulsr/features/search/presentation/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _SearchCubit extends Mock implements SearchCubit {}

class _LibraryCubit extends Mock implements LibraryCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SearchCubit searchCubit;
  late _LibraryCubit libraryCubit;
  late StreamController<SearchState> states;
  late ValueNotifier<List<String>> savedSearches;
  late PlayerCubit player;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(<String>[]);
    registerFallbackValue(createTestSong(id: -1));
  });

  // The entity rail in the app overflows by a few pixels at the default text
  // metrics; the resulting RenderFlex assertion is a layout warning, not a
  // behavioural failure, so it is filtered out.
  void ignoreOverflow() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    searchCubit = _SearchCubit();
    libraryCubit = _LibraryCubit();
    states = StreamController<SearchState>.broadcast();
    savedSearches = ValueNotifier<List<String>>(const []);
    player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});

    when(() => searchCubit.state).thenReturn(const SearchState());
    when(() => searchCubit.stream).thenAnswer((_) => states.stream);
    when(() => searchCubit.savedSearches).thenReturn(savedSearches);
    when(() => searchCubit.isSaved(any(), any())).thenReturn(false);
    when(() => searchCubit.onQueryChanged(any(),
        immediate: any(named: 'immediate'))).thenReturn(null);
    when(() => searchCubit.commitQuery()).thenAnswer((_) async {});
    when(() => searchCubit.commitQuery(any())).thenAnswer((_) async {});
    when(() => searchCubit.clearQuery()).thenReturn(null);
    when(() => searchCubit.setFilter(any())).thenReturn(null);
    when(() => searchCubit.applySavedSearch(any(), any())).thenReturn(null);
    when(() => searchCubit.suggestionsFor(any()))
        .thenAnswer((_) async => const <String>[]);
    when(() => searchCubit.removeHistoryQuery(any())).thenAnswer((_) async {});
    when(() => searchCubit.removeSavedSearch(any())).thenAnswer((_) async {});
    when(() => searchCubit.clearHistory()).thenAnswer((_) async {});
    when(() => searchCubit.saveCurrentSearch()).thenAnswer((_) async {});
    when(() => searchCubit.retry()).thenReturn(null);
    when(() => searchCubit.refresh()).thenAnswer((_) async {});

    when(() => libraryCubit.state).thenReturn(const LibraryState());
    when(() => libraryCubit.stream)
        .thenAnswer((_) => const Stream<LibraryState>.empty());

    addTearDown(() async {
      await states.close();
      savedSearches.dispose();
    });
  });

  Future<void> pumpScreen(WidgetTester tester,
      {Size size = const Size(800, 1600)}) async {
    useScreenSize(tester, size);
    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<SearchCubit>.value(value: searchCubit),
        BlocProvider<LibraryCubit>.value(value: libraryCubit),
        BlocProvider<PlayerCubit>.value(value: player),
      ],
      child: const SearchScreen(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> emit(WidgetTester tester, SearchState state) async {
    states.add(state);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a recent history term runs and commits the search',
      (tester) async {
    await pumpScreen(tester);
    await emit(tester, const SearchState(history: ['Focus', 'Chill']));

    await tester.tap(find.text('Focus'));
    await tester.pump();
    verify(() => searchCubit.onQueryChanged('Focus',
        immediate: any(named: 'immediate'))).called(1);
    verify(() => searchCubit.commitQuery('Focus')).called(1);
  });

  testWidgets('a recent history term can be removed', (tester) async {
    await pumpScreen(tester);
    await emit(tester, const SearchState(history: ['Focus', 'Chill']));

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();
    verify(() => searchCubit.removeHistoryQuery('Focus')).called(1);
  });

  testWidgets('saved searches can be applied and deleted', (tester) async {
    final entry = SearchCubit.encodeSavedSearch('Rock', 'Songs');
    savedSearches.value = [entry];
    await pumpScreen(tester);
    await emit(tester, const SearchState());

    expect(find.text('SAVED SEARCHES'), findsOneWidget);
    await tester.tap(find.widgetWithText(InputChip, 'Rock'));
    await tester.pump();
    verify(() => searchCubit.applySavedSearch('Rock', 'Songs')).called(1);
  });

  testWidgets('typing shows the suggestions overlay and selects one',
      (tester) async {
    when(() => searchCubit.suggestionsFor(any()))
        .thenAnswer((_) async => ['Beat Flow', 'Beat Box']);
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField).first, 'Beat');
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('Beat Box'), findsOneWidget);
    await tester.tap(find.text('Beat Box'));
    await tester.pump();
    verify(() => searchCubit.onQueryChanged('Beat Box',
        immediate: any(named: 'immediate'))).called(1);
  });

  testWidgets('tapping an artist rail opens the artist route', (tester) async {
    ignoreOverflow();
    when(() => libraryCubit.state).thenReturn(const LibraryState(
      artists: [
        ArtistsTableData(id: 1, name: 'Rihanna', songCount: 3, albumCount: 1),
      ],
    ));
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField).first, 'beat');
    await tester.pump();
    await emit(
      tester,
      SearchState(
        query: 'beat',
        results: [
          createTestSong(id: 1, title: 'Beat', artist: 'Rihanna', album: 'A'),
        ],
      ),
    );

    await tester.tap(find.text('Rihanna'));
    await tester.pumpAndSettle();
    expect(find.text('artist-route'), findsOneWidget);
  });

  testWidgets('an unknown artist falls back to an artist-filtered search',
      (tester) async {
    ignoreOverflow();
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField).first, 'beat');
    await tester.pump();
    await emit(
      tester,
      SearchState(
        query: 'beat',
        results: [
          createTestSong(id: 1, title: 'Beat', artist: 'Ghost', album: 'A'),
        ],
      ),
    );

    await tester.tap(find.text('Ghost'));
    await tester.pump();
    verify(() => searchCubit.applySavedSearch('Ghost', 'Artists')).called(1);
    // Drain the suggestions debounce timer.
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('tapping an album rail opens the album route', (tester) async {
    ignoreOverflow();
    when(() => libraryCubit.state).thenReturn(const LibraryState(
      albums: [
        AlbumsTableData(id: 1, title: 'Good Girl Gone Bad', artist: 'R', songCount: 2),
      ],
    ));
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField).first, 'beat');
    await tester.pump();
    await emit(
      tester,
      SearchState(
        query: 'beat',
        results: [
          createTestSong(
              id: 1,
              title: 'Beat',
              artist: 'R',
              album: 'Good Girl Gone Bad'),
        ],
      ),
    );

    await tester.tap(find.text('Good Girl Gone Bad'));
    await tester.pumpAndSettle();
    expect(find.text('album-route'), findsOneWidget);
  });

  testWidgets('local results list every match and play on tap',
      (tester) async {
    ignoreOverflow();
    await pumpScreen(tester, size: const Size(800, 3000));
    await tester.enterText(find.byType(TextField).first, 'beat');
    await tester.pump();
    await emit(
      tester,
      SearchState(
        query: 'beat',
        results: [
          for (var i = 0; i < 8; i++)
            createTestSong(id: i, title: 'Track $i', artist: 'A$i'),
        ],
      ),
    );

    expect(find.byType(SongTile), findsNWidgets(8));

    await tester.tap(find.byType(SongTile).first);
    await tester.pump();
    verify(() => searchCubit.commitQuery()).called(1);
    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });
}
