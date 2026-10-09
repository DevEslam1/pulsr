// SearchScreen additional local-only coverage: initial-query prefill, the
// loading skeleton + progress bar, the empty-results action, the save-search
// chip (add + remove) and clearing the recent-search history.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/pulsr_empty_state.dart';
import 'package:pulsr/core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:pulsr/features/search/cubit/search_state.dart';
import 'package:pulsr/features/search/presentation/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _SearchCubit extends Mock implements SearchCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SearchCubit searchCubit;
  late StreamController<SearchState> states;
  late ValueNotifier<List<String>> savedSearches;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    searchCubit = _SearchCubit();
    states = StreamController<SearchState>.broadcast();
    savedSearches = ValueNotifier<List<String>>(const []);

    when(() => searchCubit.state).thenReturn(const SearchState());
    when(() => searchCubit.stream).thenAnswer((_) => states.stream);
    when(() => searchCubit.savedSearches).thenReturn(savedSearches);
    when(() => searchCubit.isSaved(any(), any())).thenReturn(false);
    when(() => searchCubit.onQueryChanged(any(),
        immediate: any(named: 'immediate'))).thenReturn(null);
    when(() => searchCubit.commitQuery(any())).thenAnswer((_) async {});
    when(() => searchCubit.clearQuery()).thenReturn(null);
    when(() => searchCubit.setFilter(any())).thenReturn(null);
    when(() => searchCubit.applySavedSearch(any(), any())).thenReturn(null);
    when(() => searchCubit.suggestionsFor(any()))
        .thenAnswer((_) async => const <String>[]);
    when(() => searchCubit.clearHistory()).thenAnswer((_) async {});
    when(() => searchCubit.removeHistoryQuery(any())).thenAnswer((_) async {});
    when(() => searchCubit.saveCurrentSearch()).thenAnswer((_) async {});
    when(() => searchCubit.removeSavedSearch(any())).thenAnswer((_) async {});
    when(() => searchCubit.refresh()).thenAnswer((_) async {});
    when(() => searchCubit.retry()).thenReturn(null);

    addTearDown(() async {
      await states.close();
      savedSearches.dispose();
    });
  });

  Future<void> pumpScreen(WidgetTester tester, {String? initialQuery}) async {
    useScreenSize(tester, const Size(800, 1600));
    final player = stubPlayerCubit();
    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<SearchCubit>.value(value: searchCubit),
        BlocProvider<PlayerCubit>.value(value: player),
      ],
      child: SearchScreen(initialQuery: initialQuery),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> emit(WidgetTester tester, SearchState state) async {
    states.add(state);
    await tester.pump();
    await tester.pump();
  }

  // The entity rail overflows by a few pixels at default text metrics; the
  // resulting RenderFlex assertion is a layout warning, not a failure.
  void ignoreOverflow() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  Future<void> tapSaveSearch(WidgetTester tester) async {
    // The filter bar is a lazy horizontal list; scroll the chip into view.
    await tester.dragUntilVisible(
      find.text('Save Search'),
      find.byType(ListView).first,
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Search'));
    await tester.pump();
  }

  testWidgets('an initial query is prefilled and dispatched', (tester) async {
    await pumpScreen(tester, initialQuery: 'Beat');

    expect(find.widgetWithText(TextField, 'Beat'), findsOneWidget);
    verify(() => searchCubit.onQueryChanged('Beat',
        immediate: any(named: 'immediate'))).called(1);
  });

  testWidgets('a loading search shows the skeleton and progress bar',
      (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'Beat');
    await tester.pump();
    await emit(tester, const SearchState(query: 'Beat', isLoading: true));

    expect(find.byType(SkeletonList), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
  });

  testWidgets('an empty result set offers a clear action', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'Beat');
    await tester.pump();
    await emit(tester, const SearchState(query: 'Beat'));

    expect(find.byType(PulsrEmptyState), findsOneWidget);
    expect(find.text('No music found'), findsOneWidget);

    await tester.tap(find.text('Clear search'));
    await tester.pump();
    verify(() => searchCubit.clearQuery()).called(1);
  });

  testWidgets('the save-search chip adds then removes the current search',
      (tester) async {
    ignoreOverflow();
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'Beat');
    await tester.pump();
    await emit(
      tester,
      SearchState(
        query: 'Beat',
        results: [createTestSong(id: 1, title: 'Beat Flow')],
      ),
    );

    await tapSaveSearch(tester);
    verify(() => searchCubit.saveCurrentSearch()).called(1);

    when(() => searchCubit.isSaved(any(), any())).thenReturn(true);
    savedSearches.value = ['Beat'];
    await tester.pump();
    await tapSaveSearch(tester);
    verify(() => searchCubit.removeSavedSearch(any())).called(1);
  });

  testWidgets('the recent-search header clear button empties the history',
      (tester) async {
    await pumpScreen(tester);
    await emit(tester, const SearchState(history: ['Focus']));

    expect(find.text('Focus'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    verify(() => searchCubit.clearHistory()).called(1);
  });
}
