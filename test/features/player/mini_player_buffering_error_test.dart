// Mini-player buffering spinner, seek gating, and the error pill retry path.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/mini_player.dart';

import 'widgets/player_sheet_test_support.dart';

PlayerState stateWith({
  bool isPlaying = true,
  bool isBuffering = false,
  String? errorMessage,
  Duration position = const Duration(seconds: 12),
}) {
  return PlayerState(
    playback: PlaybackSlice(
      currentSong: testSong,
      isPlaying: isPlaying,
      isBuffering: isBuffering,
      position: position,
      duration: const Duration(minutes: 3, seconds: 30),
      errorMessage: errorMessage,
    ),
    queueSlice: const QueueSlice(queue: [testSong], currentIndex: 0),
  );
}

MockPlayerCubit stubMiniCubit(PlayerState state) {
  final cubit = stubPlayerCubit(state: state);
  when(() => cubit.togglePlayPause()).thenAnswer((_) async {});
  when(() => cubit.next()).thenAnswer((_) async {});
  when(() => cubit.seek(any())).thenAnswer((_) async {});
  when(() => cubit.clearError()).thenReturn(null);
  when(() => cubit.playSong(
        any(),
        queue: any(named: 'queue'),
        initialPosition: any(named: 'initialPosition'),
        openPlayerIfPlaying: any(named: 'openPlayerIfPlaying'),
      )).thenAnswer((_) async {});
  return cubit;
}

Finder miniProgress() => find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_MiniPlayerProgressBar');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(testSong);
  });

  testWidgets('buffering swaps the pause icon for a spinner', (tester) async {
    final cubit = stubMiniCubit(stateWith(isBuffering: true));

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
  });

  testWidgets('a settled player shows the pause icon, not a spinner',
      (tester) async {
    final cubit = stubMiniCubit(stateWith(isBuffering: false));

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('the seek thumb is disabled while buffering', (tester) async {
    final cubit = stubMiniCubit(stateWith(isBuffering: true));

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tapAt(tester.getCenter(miniProgress()));
    await tester.pump(const Duration(milliseconds: 30));

    verifyNever(() => cubit.seek(any()));
  });

  testWidgets('the seek thumb works again once buffering ends', (tester) async {
    final cubit = stubMiniCubit(stateWith(isBuffering: false));

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(miniProgress()));
    await tester.pump(const Duration(milliseconds: 30));

    verify(() => cubit.seek(any())).called(greaterThanOrEqualTo(1));
  });

  testWidgets(
      'an active error renders a pill whose retry replays from position',
      (tester) async {
    final cubit = stubMiniCubit(stateWith(
      isPlaying: false,
      errorMessage: 'Decoder exploded',
      position: const Duration(seconds: 42),
    ));

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Decoder exploded'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();

    verify(() => cubit.playSong(
          testSong,
          queue: any(named: 'queue'),
          initialPosition: const Duration(seconds: 42),
          openPlayerIfPlaying: any(named: 'openPlayerIfPlaying'),
        )).called(1);
  });

  testWidgets('the pill close button clears the error', (tester) async {
    final cubit = stubMiniCubit(stateWith(errorMessage: 'Decoder exploded'));

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    verify(() => cubit.clearError()).called(1);
  });

  testWidgets('no error surfaces when errorMessage is null', (tester) async {
    final cubit = stubMiniCubit(stateWith());

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
  });
}
