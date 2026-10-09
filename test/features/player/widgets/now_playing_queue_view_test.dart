// Coverage for the uncovered branches of now_playing_queue_view.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/now_playing_queue_view.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../player_test_support.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  late MockPlayerCubit cubit;
  late StreamController<PlayerState> states;
  late PlayerState currentState;
  late AppLocalizations l10n;

  setUpAll(() {
    registerFallbackValue(buildSong(0));
    registerFallbackValue(<SongsTableData>[]);
    registerFallbackValue(Duration.zero);
  });

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    cubit = MockPlayerCubit();
    states = StreamController<PlayerState>.broadcast();
    currentState = const PlayerState();
    when(() => cubit.state).thenAnswer((_) => currentState);
    when(() => cubit.stream).thenAnswer((_) => states.stream);
    when(() => cubit.switchQueueSlot(any())).thenAnswer((_) async {});
    when(() => cubit.reorderQueue(any(), any())).thenAnswer((_) async {});
    when(() => cubit.removeQueueItem(any())).thenAnswer((_) async {});
    when(() => cubit.restoreQueue(any(), any())).thenAnswer((_) async {});
    when(() => cubit.playSong(any(),
        queue: any(named: 'queue'),
        initialPosition: any(named: 'initialPosition'),
        openPlayerIfPlaying: any(named: 'openPlayerIfPlaying'))).thenAnswer(
      (_) async {},
    );
  });

  tearDown(() async {
    await states.close();
  });

  Widget host(PlayerState state) {
    currentState = state;
    return MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BlocProvider<PlayerCubit>.value(
          value: cubit,
          child: const SizedBox(
            width: 420,
            height: 640,
            child: NowPlayingQueueView(),
          ),
        ),
      ),
    );
  }

  testWidgets('renders the empty state when the queue is empty',
      (tester) async {
    await tester.pumpWidget(host(const PlayerState()));
    await tester.pump();

    expect(find.text(l10n.queueEmpty), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNothing);
    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Q3'), findsOneWidget);
  });

  testWidgets('renders queue rows and highlights the active track',
      (tester) async {
    final songs = [buildSong(1), buildSong(2)];
    await tester.pumpWidget(host(PlayerState(
      queueSlice: QueueSlice(queue: songs, currentIndex: 0),
    )));
    await tester.pump();

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Song 2'), findsOneWidget);
    expect(find.byType(NowPlayingIndicator), findsOneWidget);
  });

  testWidgets('tapping a row plays the song with the queue', (tester) async {
    final songs = [buildSong(1), buildSong(2)];
    await tester.pumpWidget(host(PlayerState(
      queueSlice: QueueSlice(queue: songs, currentIndex: 0),
    )));
    await tester.pump();

    await tester.tap(find.text('Song 2'));
    await tester.pump();

    verify(() => cubit.playSong(any(),
        queue: any(named: 'queue'),
        initialPosition: any(named: 'initialPosition'),
        openPlayerIfPlaying: any(named: 'openPlayerIfPlaying'))).called(1);
  });

  testWidgets('switching a queue slot invokes the cubit', (tester) async {
    await tester.pumpWidget(host(const PlayerState()));
    await tester.pump();

    await tester.tap(find.text('Q2'));
    await tester.pump();

    verify(() => cubit.switchQueueSlot(1)).called(1);
  });

  testWidgets('removing a row shows an undo snackbar that restores the queue',
      (tester) async {
    final songs = [buildSong(1), buildSong(2)];
    await tester.pumpWidget(host(PlayerState(
      queueSlice: QueueSlice(queue: songs, currentIndex: 0),
    )));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    verify(() => cubit.removeQueueItem(1)).called(1);
    expect(find.text(l10n.undo), findsOneWidget);

    await tester.tap(find.text(l10n.undo));
    await tester.pump();

    verify(() => cubit.restoreQueue(any(), any())).called(1);
  });

  testWidgets('swiping a row away removes it and offers undo', (tester) async {
    final songs = [buildSong(1), buildSong(2), buildSong(3)];
    await tester.pumpWidget(host(PlayerState(
      queueSlice: QueueSlice(queue: songs, currentIndex: 0),
    )));
    await tester.pump();

    await tester.drag(find.text('Song 3'), const Offset(-500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    verify(() => cubit.removeQueueItem(any())).called(greaterThanOrEqualTo(1));
  });

  testWidgets('a currentIndex change triggers the scroll listener',
      (tester) async {
    final songs = [buildSong(1), buildSong(2), buildSong(3)];
    await tester.pumpWidget(host(PlayerState(
      queueSlice: QueueSlice(queue: songs, currentIndex: 0),
    )));
    await tester.pump();

    currentState = PlayerState(
      queueSlice: QueueSlice(queue: songs, currentIndex: 2),
    );
    states.add(currentState);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(NowPlayingIndicator), findsOneWidget);
  });
}
