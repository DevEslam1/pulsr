// SearchScreen widget suite (local-only build: AppConfig.ytmEnabled == false).
//
// Covers the start page, local result rendering, clearing, the filter bar and
// the error state. A mock SearchCubit backed by a state controller keeps the
// widget deterministic.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/highlighted_text.dart';
import 'package:pulsr/core/widgets/pulsr_empty_state.dart';
import 'package:pulsr/core/widgets/pulsr_chip.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:pulsr/features/search/cubit/search_state.dart';
import 'package:pulsr/features/search/presentation/search_screen.dart';
import 'package:pulsr/features/search/presentation/widgets/highlighted_song_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _SearchCubit extends Mock implements SearchCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SearchCubit searchCubit;
  late StreamController<SearchState> states;
  late ValueNotifier<List<String>> savedSearches;
  late ValueNotifier<List<SongsTableData>> searchPlayedSongs;
  late ValueNotifier<bool> hasMoreResults;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(List<String>.empty());
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    searchCubit = _SearchCubit();
    states = StreamController<SearchState>.broadcast();
    savedSearches = ValueNotifier<List<String>>(const []);
    searchPlayedSongs = ValueNotifier<List<SongsTableData>>(const []);
    hasMoreResults = ValueNotifier<bool>(false);

    when(() => searchCubit.state).thenReturn(const SearchState());
    when(() => searchCubit.stream).thenAnswer((_) => states.stream);
    when(() => searchCubit.savedSearches).thenReturn(savedSearches);
    when(() => searchCubit.searchPlayedSongs).thenReturn(searchPlayedSongs);
    when(() => searchCubit.recordPlayedSong(any())).thenAnswer((_) async {});
    when(() => searchCubit.removeSearchPlayedSong(any()))
        .thenAnswer((_) async {});
    when(() => searchCubit.clearSearchPlayedSongs()).thenAnswer((_) async {});
    when(() => searchCubit.hasMoreResults).thenReturn(hasMoreResults);
    when(() => searchCubit.isDebouncing).thenReturn(false);
    when(() => searchCubit.isSaved(any(), any())).thenReturn(false);
    when(() => searchCubit.onQueryChanged(any(),
        immediate: any(named: 'immediate'))).thenReturn(null);
    when(() => searchCubit.commitQuery(any())).thenAnswer((_) async {});
    when(() => searchCubit.clearQuery()).thenReturn(null);
    when(() => searchCubit.setFilter(any())).thenReturn(null);
    when(() => searchCubit.applySavedSearch(any(), any())).thenReturn(null);
    when(() => searchCubit.suggestionsFor(any()))
        .thenAnswer((_) async => const <String>[]);
    addTearDown(() async {
      await states.close();
      savedSearches.dispose();
      searchPlayedSongs.dispose();
      hasMoreResults.dispose();
    });
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    useScreenSize(tester, const Size(800, 1400));
    final player = stubPlayerCubit();
    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<SearchCubit>.value(value: searchCubit),
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

  testWidgets('renders the start page', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Search'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typing a query renders local song results', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'Beat');
    await tester.pump();

    verify(() => searchCubit.onQueryChanged('Beat',
        immediate: any(named: 'immediate'))).called(1);

    await emit(
      tester,
      SearchState(
        query: 'Beat',
        results: [
          createTestSong(id: 1, title: 'Beat Flow', artist: 'A', album: 'B')
        ],
      ),
    );

    expect(find.byType(HighlightedSongTile), findsWidgets);
    expect(find.text('Beat Flow'), findsWidgets);

    final highlighted = tester.widgetList<PulsrHighlightedText>(find.descendant(
        of: find.byType(HighlightedSongTile),
        matching: find.byType(PulsrHighlightedText)));
    expect(highlighted, isNotEmpty);
    expect(highlighted.every((w) => w.query == 'Beat'), isTrue);
  });

  testWidgets('clearing the query returns to the start page', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'Beat');
    await tester.pump();
    await emit(
      tester,
      SearchState(
        query: 'Beat',
        results: [
          createTestSong(id: 1, title: 'Beat Flow', artist: 'A', album: 'B')
        ],
      ),
    );
    expect(find.byType(HighlightedSongTile), findsWidgets);

    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pump();
    verify(() => searchCubit.clearQuery()).called(1);

    await emit(tester, const SearchState());
    expect(find.byType(HighlightedSongTile), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the filter bar selects a filter', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Songs'));
    await tester.pump();
    verify(() => searchCubit.setFilter('Songs')).called(1);

    await emit(tester, const SearchState(selectedFilter: 'Songs'));
    final chip =
        tester.widget<PulsrChip>(find.widgetWithText(PulsrChip, 'Songs'));
    expect(chip.selected, isTrue);
  });

  testWidgets('a failed local search renders the error state', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'Beat');
    await tester.pump();
    await emit(
      tester,
      const SearchState(query: 'Beat', errorMessage: 'kaboom'),
    );

    expect(find.byType(PulsrEmptyState), findsOneWidget);
  });
}
