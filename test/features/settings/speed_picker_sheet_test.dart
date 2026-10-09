// Covers lib/features/player/presentation/widgets/speed_picker_sheet.dart:
// the option-list helpers plus the speed/pitch reset, chip and slider paths.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/speed_picker_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockPlayerCubit player;

  setUp(() {
    player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => player.minPlaybackSpeed).thenReturn(0.5);
    when(() => player.maxPlaybackSpeed).thenReturn(3.0);
    when(() => player.setPlaybackSpeed(any())).thenAnswer((_) async {});
    when(() => player.setPlaybackPitch(any())).thenAnswer((_) async {});
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    when(() => player.state).thenReturn(PlayerState(
      playback: PlaybackSlice(playbackSpeed: speed, playbackPitch: pitch),
    ));
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: player,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SpeedPickerSheet()),
        ),
      ),
    );
    await tester.pump();
  }

  group('static helpers', () {
    test('speedOptionsFor falls back when min > max', () {
      expect(SpeedPickerSheet.speedOptionsFor(3.0, 0.5),
          SpeedPickerSheet.speedOptions);
    });

    test('speedOptionsFor returns the filtered advanced range', () {
      final options = SpeedPickerSheet.speedOptionsFor(0.1, 8.0);
      expect(options.first, 0.1);
      expect(options.last, 8.0);
      expect(options, contains(4.0));
    });

    test('speedOptionsFor falls back when the range excludes every option', () {
      expect(SpeedPickerSheet.speedOptionsFor(10.0, 20.0),
          SpeedPickerSheet.speedOptions);
    });

    test('semitonesToPitch and formatSpeed convert deterministically', () {
      expect(SpeedPickerSheet.semitonesToPitch(12.0), closeTo(2.0, 1e-9));
      expect(SpeedPickerSheet.semitonesToPitch(0.0), 1.0);
      expect(SpeedPickerSheet.formatSpeed(1.5), '1.50x');
    });
  });

  testWidgets('default speed and pitch render without reset affordances',
      (tester) async {
    await pumpSheet(tester);

    expect(find.text(l10n.playbackSpeed), findsOneWidget);
    expect(find.text(l10n.currentSpeed('1.00x')), findsOneWidget);
    expect(find.text(l10n.reset), findsNothing);
    expect(find.text(l10n.dspOriginalPitch), findsOneWidget);
  });

  Future<void> tapChip(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('tapping a speed chip writes it and reset restores 1.0x',
      (tester) async {
    await pumpSheet(tester, speed: 1.5);

    expect(find.text(l10n.reset), findsOneWidget);
    await tapChip(tester, '2.00x');
    verify(() => player.setPlaybackSpeed(2.0)).called(1);

    await tester.tap(find.text(l10n.reset));
    await tester.pump();
    verify(() => player.setPlaybackSpeed(1.0)).called(1);
  });

  testWidgets('non-unity pitch shows semitones and drives pitch setters',
      (tester) async {
    await pumpSheet(tester, pitch: 1.5);

    // 1.5x pitch == +7 semitones (12 * log2(1.5)).
    expect(find.textContaining('semitones'), findsOneWidget);
    expect(find.text(l10n.reset), findsOneWidget);

    await tapChip(tester, '+25%');
    verify(() => player.setPlaybackPitch(1.25)).called(1);

    await tester.tap(find.text(l10n.reset));
    await tester.pump();
    verify(() => player.setPlaybackPitch(1.0)).called(1);
  });

  testWidgets('dragging the pitch slider writes the pitch', (tester) async {
    await pumpSheet(tester, pitch: 1.0);

    await tester.drag(find.byType(PulsrSlider), const Offset(60, 0));
    await tester.pump();

    verify(() => player.setPlaybackPitch(any())).called(greaterThanOrEqualTo(1));
  });

  testWidgets('SpeedPickerSheet.show opens the sheet from a host', (tester) async {
    when(() => player.state).thenReturn(const PlayerState());
    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: player,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => SpeedPickerSheet.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SpeedPickerSheet), findsOneWidget);
  });
}
