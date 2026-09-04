import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/audio_feature_info.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/audio_sound_section.dart';
import 'package:pulsr/features/settings/presentation/widgets/playback_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMediaScannerService mockScanner;

  Widget host(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: ListView(children: [child]),
        ),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // SettingsCubit eagerly constructs HiResAudioService, which probes the
    // hires_dac channel with a 3s timeout on startup. Stub the channel so
    // that timer doesn't dangle into the no-pending-timers teardown check.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.hiresDac),
      (call) async => null,
    );
    mockScanner = MockMediaScannerService();
  });

  group('Crossfade ↔ Gapless conflict card (PlaybackSection)', () {
    testWidgets(
        'resolve action turns gapless OFF and applies the intended crossfade',
        (tester) async {
      final cubit = SettingsCubit(scannerService: mockScanner);
      addTearDown(cubit.close);
      const state = SettingsState(gaplessPlayback: true, crossfadeSeconds: 4);

      await tester.pumpWidget(host(BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: const PlaybackSection(state: state),
      )));

      // Conflict card visible with the one-tap resolution.
      expect(
          find.text('Turn off Gapless & enable Crossfade'), findsOneWidget);
      await tester
          .tap(find.text('Turn off Gapless & enable Crossfade'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(cubit.state.gaplessPlayback, isFalse);
      expect(cubit.state.crossfadeSeconds, 4.0);
    });

    testWidgets(
        'offers plain "Turn off Gapless" when crossfade is still at 0 s',
        (tester) async {
      final cubit = SettingsCubit(scannerService: mockScanner);
      addTearDown(cubit.close);
      const state = SettingsState(gaplessPlayback: true, crossfadeSeconds: 0);

      await tester.pumpWidget(host(BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: const PlaybackSection(state: state),
      )));

      expect(find.text('Turn off Gapless'), findsOneWidget);
      await tester.tap(find.text('Turn off Gapless'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(cubit.state.gaplessPlayback, isFalse);
    });

    testWidgets('no conflict card when gapless is OFF', (tester) async {
      final cubit = SettingsCubit(scannerService: mockScanner);
      addTearDown(cubit.close);
      const state = SettingsState(gaplessPlayback: false, crossfadeSeconds: 4);

      await tester.pumpWidget(host(BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: const PlaybackSection(state: state),
      )));

      expect(find.text('Turn off Gapless & enable Crossfade'), findsNothing);
      expect(find.byTooltip('Reset to default (0.0s)'), findsOneWidget);
    });
  });

  group('Restore-default slider rows wired to cubit setters', () {
    testWidgets('crossfade reset icon restores 0.0 s default',
        (tester) async {
      final cubit = SettingsCubit(scannerService: mockScanner);
      addTearDown(cubit.close);
      const state = SettingsState(gaplessPlayback: false, crossfadeSeconds: 6);

      await tester.pumpWidget(host(BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: const PlaybackSection(state: state),
      )));

      await tester.tap(find.byTooltip('Reset to default (0.0s)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(cubit.state.crossfadeSeconds, 0.0);
    });
  });

  group('ReplayGain ↔ Bit-Perfect-bypass conflict card (AudioSoundSection)',
      () {
    testWidgets(
        'resolve action disables Bit-Perfect bypass and unblocks ReplayGain',
        (tester) async {
      final cubit = SettingsCubit(scannerService: mockScanner);
      addTearDown(cubit.close);
      final playerCubit = MockPlayerCubit();
      when(() => playerCubit.state).thenReturn(const PlayerState());
      when(() => playerCubit.stream).thenAnswer((_) => const Stream.empty());
      const state = SettingsState(
        bitPerfectOutput: true,
        bypassDspOnBitPerfect: true,
        replayGainMode: ReplayGainMode.track,
        currentOutputDevice: AudioOutputInfo(
          deviceName: 'Test USB DAC',
          isUsbDac: true,
          sampleRate: 48000,
          bitDepth: 24,
          isBitPerfectActive: true,
        ),
      );
      // Sanity: the state really is blocked before resolving.
      expect(
        AudioConflicts.replayGainBlockedByBitPerfect(
          bitPerfectOutput: state.bitPerfectOutput,
          bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
          device: state.currentOutputDevice,
        ),
        isNotNull,
      );

      await tester.pumpWidget(host(BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: BlocProvider<PlayerCubit>.value(
          value: playerCubit,
          child: const AudioSoundSection(state: state),
        ),
      )));

      expect(find.text('Disable Bit-Perfect bypass'), findsOneWidget);
      await tester.ensureVisible(find.text('Disable Bit-Perfect bypass'));
      await tester.pump();
      await tester.tap(find.text('Disable Bit-Perfect bypass'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(cubit.state.bypassDspOnBitPerfect, isFalse);
      expect(
        AudioConflicts.replayGainBlockedByBitPerfect(
          bitPerfectOutput: cubit.state.bitPerfectOutput,
          bypassDspOnBitPerfect: cubit.state.bypassDspOnBitPerfect,
          device: cubit.state.currentOutputDevice,
        ),
        isNull,
      );
    });

    test('AudioConflicts logic: only blocks when bit-perfect is armed and on DAC', () {
      const normalSpeaker = AudioOutputInfo(
        deviceName: 'Speaker',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 24,
        isDirectSupported: true,
        isBitPerfectActive: false,
      );
      const btDevice = AudioOutputInfo(
        deviceName: 'Bluetooth Earbuds',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBluetooth: true,
        isBitPerfectActive: false,
      );
      const usbDac = AudioOutputInfo(
        deviceName: 'USB DAC',
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: true,
      );

      // Normal speaker with isDirectSupported: true does NOT block DSP when bit-perfect is on
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: normalSpeaker,
        ),
        isNull,
      );

      // Bluetooth does NOT block DSP
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: btDevice,
        ),
        isNull,
      );

      // USB DAC with bit-perfect on DOES block DSP
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: usbDac,
        ),
        isNotNull,
      );

      // Bit-perfect output OFF never blocks DSP
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: true,
          device: usbDac,
        ),
        isNull,
      );
    });
  });
}
