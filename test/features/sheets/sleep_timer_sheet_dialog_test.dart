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

  late MockPlayerCubit mockPlayerCubit;

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayerCubit.sleepTimerRemainingTracks).thenReturn(null);
    when(() => mockPlayerCubit.isEndOfQueueSleepTimer).thenReturn(false);
    when(() => mockPlayerCubit.sleepTimerMode).thenReturn(SleepTimerMode.duration);
    when(() => mockPlayerCubit.startSleepTimer(any())).thenReturn(null);
  });

  testWidgets('[H-19] custom minutes dialog safely disposes controller without error during pop transition', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: mockPlayerCubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SleepTimerSheet.show(context),
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Open SleepTimerSheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Tap on Custom Duration ListTile
    final customTile = find.byIcon(Icons.timer_outlined);
    expect(customTile, findsOneWidget);
    await tester.tap(customTile);
    await tester.pumpAndSettle();

    // Dialog is open with text field
    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);

    // Enter minutes
    await tester.enterText(textField, '45');
    await tester.pump();

    // Tap OK
    final okButton = find.widgetWithText(FilledButton, 'OK');
    expect(okButton, findsOneWidget);
    await tester.tap(okButton);

    // Pump intermediate animation frames to verify controller is not disposed during transition
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Verify cubit received the start call
    verify(() => mockPlayerCubit.startSleepTimer(45)).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('[M-10] ChoiceChip for end-of-track is selected when sleepTimerMode is endOfTrack', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    when(() => mockPlayerCubit.sleepTimerMode).thenReturn(SleepTimerMode.endOfTrack);
    when(() => mockPlayerCubit.sleepTimerRemainingTracks).thenReturn(1);
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState(
      playback: PlaybackSlice(sleepTimerRemaining: null),
    ));

    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: mockPlayerCubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SleepTimerSheet.show(context),
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Open SleepTimerSheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Verify End of Track ChoiceChip is selected even when sleepTimerRemaining is null
    final endOfTrackChipFinder = find.widgetWithText(ChoiceChip, 'End of track');
    expect(endOfTrackChipFinder, findsOneWidget);
    final chip = tester.widget<ChoiceChip>(endOfTrackChipFinder);
    expect(chip.selected, isTrue);
  });
}
