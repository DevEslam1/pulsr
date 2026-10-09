// SleepTimerSheet extra coverage: the active-duration / end-of-track /
// end-of-queue / N-tracks status lines, the turn-off affordance, the mode and
// preset chips, the custom-minutes dialog (invalid + valid) and the
// "stop at a specific time" picker.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/sleep_timer_manager.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/sheets/sleep_timer_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit cubit;

  setUpAll(() {
    registerFallbackValue(DateTime(2024));
  });

  setUp(() {
    cubit = MockPlayerCubit();
    when(() => cubit.state).thenReturn(const PlayerState());
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => cubit.sleepTimerRemainingTracks).thenReturn(null);
    when(() => cubit.isEndOfQueueSleepTimer).thenReturn(false);
    when(() => cubit.sleepTimerMode).thenReturn(SleepTimerMode.duration);
    when(() => cubit.startSleepTimer(any())).thenReturn(null);
    when(() => cubit.startEndOfTrackTimer()).thenReturn(null);
    when(() => cubit.startEndOfQueueTimer()).thenReturn(null);
    when(() => cubit.startAfterNTracksTimer(any())).thenReturn(null);
    when(() => cubit.startAbsoluteSleepTimer(any())).thenReturn(null);
    when(() => cubit.cancelSleepTimer()).thenReturn(null);
  });

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: cubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SleepTimerSheet.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('duration timer shows the countdown and turn-off cancels',
      (tester) async {
    when(() => cubit.state).thenReturn(const PlayerState(
      playback: PlaybackSlice(
        sleepTimerRemaining: Duration(minutes: 2, seconds: 30),
      ),
    ));
    await openSheet(tester);

    expect(find.text('Music will stop in 2m 30s'), findsOneWidget);
    await tester.tap(find.text('Turn Off'));
    await tester.pump();
    verify(() => cubit.cancelSleepTimer()).called(1);
  });

  testWidgets('end-of-queue mode shows its status and selects the chip',
      (tester) async {
    when(() => cubit.isEndOfQueueSleepTimer).thenReturn(true);
    when(() => cubit.sleepTimerMode).thenReturn(SleepTimerMode.endOfQueue);
    await openSheet(tester);

    expect(find.text('Music will stop at the end of the queue'), findsOneWidget);
    final chip =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'End of queue'));
    expect(chip.selected, isTrue);
  });

  testWidgets('one remaining track reports end-of-track', (tester) async {
    when(() => cubit.sleepTimerMode).thenReturn(SleepTimerMode.afterNTracks);
    when(() => cubit.sleepTimerRemainingTracks).thenReturn(1);
    await openSheet(tester);

    expect(find.text('Music will stop at the end of this track'), findsOneWidget);
  });

  testWidgets('multiple remaining tracks reports the count', (tester) async {
    when(() => cubit.sleepTimerMode).thenReturn(SleepTimerMode.afterNTracks);
    when(() => cubit.sleepTimerRemainingTracks).thenReturn(3);
    await openSheet(tester);

    expect(find.text('Music will stop after 3 songs'), findsOneWidget);
  });

  testWidgets('mode chips start the matching timers', (tester) async {
    await openSheet(tester);

    await tester.tap(find.text('End of track'));
    await tester.pump();
    verify(() => cubit.startEndOfTrackTimer()).called(1);

    await openSheet(tester);
    await tester.tap(find.text('End of queue'));
    await tester.pump();
    verify(() => cubit.startEndOfQueueTimer()).called(1);

    await openSheet(tester);
    await tester.tap(find.text('2 songs'));
    await tester.pump();
    verify(() => cubit.startAfterNTracksTimer(2)).called(1);
  });

  testWidgets('an active preset is selected and tapping a preset starts it',
      (tester) async {
    when(() => cubit.state).thenReturn(const PlayerState(
      playback: PlaybackSlice(sleepTimerRemaining: Duration(minutes: 30)),
    ));
    await openSheet(tester);

    final thirty =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '30 min'));
    expect(thirty.selected, isTrue);

    await tester.tap(find.text('15 min'));
    await tester.pump();
    verify(() => cubit.startSleepTimer(15)).called(1);
  });

  testWidgets('custom minutes dialog rejects out-of-range then accepts a value',
      (tester) async {
    await openSheet(tester);

    await tester.tap(find.byIcon(Icons.timer_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a value from 1 to 720 minutes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '45');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();

    verify(() => cubit.startSleepTimer(45)).called(1);
  });

  testWidgets('stop at specific time arms an absolute timer', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byIcon(Icons.access_time_rounded));
    await tester.pumpAndSettle();

    // Confirm the default time in the material picker.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    verify(() => cubit.startAbsoluteSleepTimer(any())).called(1);
  });
}
