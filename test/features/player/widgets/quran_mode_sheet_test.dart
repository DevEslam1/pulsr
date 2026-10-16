// test/features/player/widgets/quran_mode_sheet_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/earbud_optimization_service.dart';
import 'package:pulsr/core/widgets/pulsr_switch.dart';
import 'package:pulsr/domain/models/quran_metadata.dart';
import 'package:pulsr/domain/models/quran_mode_profile.dart';
import 'package:pulsr/domain/repositories/quran_repository.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/quran_mode_sheet.dart';

import 'player_sheet_test_support.dart';

class MockQuranRepository extends Mock implements QuranRepository {}

const _btCaps = EarbudCapabilities(
  deviceName: 'Sony XM5',
  codec: EarbudCodec.ldac,
  isBluetooth: true,
  isLeAudio: false,
  isUsbDac: false,
  sampleRateHz: 96000,
  bitDepth: 24,
  latencyMs: 180,
);

PlayerState quranState({
  bool enabled = false,
  bool reverb = false,
  bool saturation = false,
  double speed = 1.0,
}) {
  return const PlayerState().copyWith(
    dsp: DspSlice(
      isQuranModeEnabled: enabled,
      quranReciterStyle: QuranReciterStyle.mujawwad,
      isReverbEnabled: reverb,
      reverbWetDry: 0.3,
      isSaturationEnabled: saturation,
      saturationMix: 0.4,
    ),
    playback: PlaybackSlice(playbackSpeed: speed),
  );
}

MockPlayerCubit quranCubit(
  PlayerState state, {
  Future<EarbudCapabilities>? caps,
  bool throwCaps = false,
}) {
  final cubit = stubPlayerCubit(state: state);
  when(() => cubit.setQuranModeEnabled(any())).thenAnswer((_) async {});
  when(() => cubit.setQuranReciterStyle(any())).thenAnswer((_) async {});
  when(() => cubit.setQuranAmbience(any())).thenAnswer((_) async {});
  when(() => cubit.setQuranWarmth(any())).thenAnswer((_) async {});
  when(() => cubit.setQuranPlaybackSpeed(any())).thenAnswer((_) async {});
  when(() => cubit.resetQuranProfile()).thenAnswer((_) async {});
  if (throwCaps) {
    when(() => cubit.detectEarbudCapabilities())
        .thenAnswer((_) async => throw Exception('no earbuds'));
  } else {
    when(() => cubit.detectEarbudCapabilities())
        .thenAnswer((_) => caps ?? Future<EarbudCapabilities>.value(_btCaps));
  }
  return cubit;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(QuranReciterStyle.murattal);
    registerFallbackValue(QuranBookmark(
      trackUri: 'test',
      metadata: const QuranMetadata(
        surahNumber: 1,
        surahName: 'Al-Fatihah',
        ayahStart: 1,
        ayahEnd: 7,
        reciter: 'Reciter',
      ),
      currentAyah: 1,
      position: Duration.zero,
      timestamp: DateTime.now(),
    ));
  });

  group('QuranModePanel', () {
    testWidgets('renders and forwards enable + reciter style changes',
        (tester) async {
      final cubit = quranCubit(quranState());
      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const SingleChildScrollView(child: QuranModePanel()),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(QuranModePanel), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(6));

      await tester.tap(find.byType(PulsrSwitch).first);
      await tester.pump();
      verify(() => cubit.setQuranModeEnabled(true)).called(1);

      await tester.tap(find.byType(ChoiceChip).at(1));
      await tester.pump();
      verify(() => cubit.setQuranReciterStyle(any())).called(1);
    });

    testWidgets('enabled state exposes sliders, speed and reset',
        (tester) async {
      final cubit = quranCubit(quranState(enabled: true, reverb: true));
      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const SingleChildScrollView(child: QuranModePanel()),
      ));
      await tester.pumpAndSettle();

      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders, isNotEmpty);
      for (final slider in sliders) {
        expect(slider.onChanged, isNotNull);
        expect(slider.onChangeEnd, isNotNull);
        // Dragging updates the live label without hitting the cubit…
        slider.onChanged!(0.25);
      }
      await tester.pump();
      expect(find.text('25%'), findsWidgets);
      verifyNever(() => cubit.setQuranAmbience(any()));
      // …and the native call only fires once on release.
      for (final slider in sliders) {
        slider.onChangeEnd!(0.25);
      }
      await tester.pump();
      verify(() => cubit.setQuranAmbience(any())).called(1);
      verify(() => cubit.setQuranWarmth(any())).called(1);

      await tester.tap(find.text('0.5x'));
      await tester.pump();
      verify(() => cubit.setQuranPlaybackSpeed(0.5)).called(1);

      final reset = find.byType(OutlinedButton);
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pump();
      verify(() => cubit.resetQuranProfile()).called(1);
    });

    testWidgets('refresh re-detects earbud capabilities', (tester) async {
      final cubit = quranCubit(quranState(enabled: true));
      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const SingleChildScrollView(child: QuranModePanel()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();
      verify(() => cubit.detectEarbudCapabilities()).called(2);
    });

    testWidgets('shows an error card when capability detection fails',
        (tester) async {
      final cubit = quranCubit(quranState(), throwCaps: true);
      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const SingleChildScrollView(child: QuranModePanel()),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(QuranModePanel), findsOneWidget);
    });

    testWidgets('shows the loading card while capabilities are pending',
        (tester) async {
      final completer = Completer<EarbudCapabilities>();
      final cubit = quranCubit(quranState(), caps: completer.future);
      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const SingleChildScrollView(child: QuranModePanel()),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(_btCaps);
      await tester.pumpAndSettle();
    });

    testWidgets(
        'shows empty state card when current track has no Quran metadata',
        (tester) async {
      final repo = MockQuranRepository();
      when(() => repo.getMetadataForTrack(any())).thenAnswer((_) async => null);
      when(() => repo.getBookmark(any())).thenAnswer((_) async => null);
      if (getIt.isRegistered<QuranRepository>()) {
        getIt.unregister<QuranRepository>();
      }
      getIt.registerSingleton<QuranRepository>(repo);

      final cubit = quranCubit(quranState());
      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const SingleChildScrollView(child: QuranModePanel()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No Quran Metadata'), findsOneWidget);
    });

    testWidgets(
        'displays Quran metadata, bookmark action, and repeat modes when metadata exists',
        (tester) async {
      final repo = MockQuranRepository();
      const testMetadata = QuranMetadata(
        surahNumber: 1,
        surahName: 'Al-Fatihah',
        ayahStart: 1,
        ayahEnd: 7,
        reciter: 'Mishary Alafasy',
        ayahTimings: [
          QuranAyahTiming(
            ayahNumber: 1,
            start: Duration.zero,
            end: Duration(seconds: 5),
          ),
          QuranAyahTiming(
            ayahNumber: 2,
            start: Duration(seconds: 5),
            end: Duration(seconds: 10),
          ),
        ],
      );

      when(() => repo.getMetadataForTrack('/music/test.flac'))
          .thenAnswer((_) async => testMetadata);
      when(() => repo.getBookmark('/music/test.flac'))
          .thenAnswer((_) async => null);
      when(() => repo.saveBookmark(any())).thenAnswer((_) async {});

      if (getIt.isRegistered<QuranRepository>()) {
        getIt.unregister<QuranRepository>();
      }
      getIt.registerSingleton<QuranRepository>(repo);

      final state = quranState().copyWith(
        playback: const PlaybackSlice().copyWith(currentSong: testSong),
      );
      final cubit = quranCubit(state);

      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const SingleChildScrollView(child: QuranModePanel()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Al-Fatihah (1)'), findsOneWidget);
      expect(find.text('Mishary Alafasy • Ayah 1-7'), findsOneWidget);
      expect(find.text('Save Quran Bookmark'), findsOneWidget);
      expect(find.text('AYAH REPEAT MODE'), findsOneWidget);
    });

    testWidgets('QuranModeSheet wraps the panel in a bottom sheet container',
        (tester) async {
      final cubit = quranCubit(quranState());
      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const QuranModeSheet(),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(QuranModeSheet), findsOneWidget);
      expect(find.byType(QuranModePanel), findsOneWidget);
    });
  });
}
