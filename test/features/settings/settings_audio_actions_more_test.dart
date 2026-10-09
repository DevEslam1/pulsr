// Additional coverage for lib/features/settings/cubit/settings_audio_actions.dart:
// the PulsrAudioHandler-backed live toggles (success + failure logging), the
// EqualizerManager-owned DSP push/limiter path, the Bluetooth bit-perfect hard
// block, the Android direct-USB fallback and the target-format/calibration
// helpers.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/audio/multi_output_router.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/settings_section_harness.dart';

class MockAudioHandler extends Mock implements PulsrAudioHandler {}

class MockEqualizerManager extends Mock implements EqualizerManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(MultiOutputMode.systemDefault);
  });

  const hiresChannel = MethodChannel(PulsrChannels.hiresDac);
  const usbChannel = MethodChannel(PulsrChannels.usbExclusive);
  const usbEvents = MethodChannel(PulsrChannels.usbExclusiveEvents);

  setUp(() {
    stubSettingsChannels();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    clearSettingsChannels();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(hiresChannel, null);
    messenger.setMockMethodCallHandler(usbChannel, null);
    messenger.setMockMethodCallHandler(usbEvents, null);
    if (getIt.isRegistered<PulsrAudioHandler>()) {
      await getIt.unregister<PulsrAudioHandler>();
    }
    if (getIt.isRegistered<EqualizerManager>()) {
      await getIt.unregister<EqualizerManager>();
    }
  });

  SettingsCubit make() =>
      SettingsCubit(scannerService: MockMediaScannerService());

  MockAudioHandler registeredHandler() {
    final handler = MockAudioHandler();
    getIt.registerSingleton<PulsrAudioHandler>(handler);
    return handler;
  }

  test('handler-backed toggles succeed and a rejected AAudio/multi-output reverts',
      () async {
    final handler = registeredHandler();
    var aaudioResult = true;
    var multiResult = true;
    when(() => handler.setAaudioOutputEnabled(
          any(),
          preferExclusive: any(named: 'preferExclusive'),
          targetBufferMs: any(named: 'targetBufferMs'),
        )).thenAnswer((_) async => aaudioResult);
    when(() => handler.setMultiOutputMode(any()))
        .thenAnswer((_) async => multiResult);
    when(() => handler.setDvcEnabled(any())).thenAnswer((_) async {});
    when(() => handler.setBpmSyncCrossfadeEnabled(any()))
        .thenAnswer((_) async {});
    when(() => handler.setFloatOutputEnabled(any())).thenAnswer((_) async {});
    when(() => handler.setHedgedResolutionEnabled(any()))
        .thenAnswer((_) async {});
    when(() => handler.setAdaptiveQualityEnabled(any()))
        .thenAnswer((_) async {});
    when(() => handler.setDuckingMode(any())).thenAnswer((_) async {});
    when(() => handler.setDuckingLevel(any())).thenAnswer((_) async {});
    when(() => handler.setDspSnapshotEnabled(any())).thenAnswer((_) async {});

    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;

    await cubit.setAaudioOutputEnabled(true);
    expect(cubit.state.aaudioOutputEnabled, isTrue);
    await cubit.setAaudioOutputEnabled(false);
    expect(cubit.state.aaudioOutputEnabled, isFalse);

    await cubit.setDvcEnabled(true);
    await cubit.setBpmSyncCrossfadeEnabled(true);
    await cubit.setFloatOutputEnabled(false);
    await cubit.setHedgedResolutionEnabled(false);
    await cubit.setAdaptiveQualityEnabled(false);
    await cubit.setDuckingMode('pause');
    await cubit.setDuckingLevel(0.5);
    await cubit.setDspSnapshotEnabled(false);

    await cubit.setMultiOutputMode('speakerAndBluetooth');
    expect(cubit.state.multiOutputMode, 'speakerAndBluetooth');

    // AAudio rejected by the player: state reverts with an error.
    aaudioResult = false;
    await cubit.setAaudioOutputEnabled(true);
    expect(cubit.state.aaudioOutputEnabled, isFalse);
    expect(cubit.state.errorMessage, isNotNull);

    // Multi-output rejected: reverts to system default with an error.
    multiResult = false;
    await cubit.setMultiOutputMode('speakerAndBluetooth');
    expect(cubit.state.multiOutputMode, 'systemDefault');
  });

  test('handler failures are logged without throwing', () async {
    final handler = registeredHandler();
    when(() => handler.setHedgedResolutionEnabled(any()))
        .thenAnswer((_) async => throw Exception('hedged'));
    when(() => handler.setAdaptiveQualityEnabled(any()))
        .thenAnswer((_) async => throw Exception('adaptive'));
    when(() => handler.setDuckingMode(any()))
        .thenAnswer((_) async => throw Exception('duck'));
    when(() => handler.setDuckingLevel(any()))
        .thenAnswer((_) async => throw Exception('duck level'));
    when(() => handler.setDspSnapshotEnabled(any()))
        .thenAnswer((_) async => throw Exception('snapshot'));
    when(() => handler.setMultiOutputMode(any()))
        .thenAnswer((_) async => throw Exception('multi'));

    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;

    await cubit.setHedgedResolutionEnabled(false);
    await cubit.setAdaptiveQualityEnabled(false);
    await cubit.setDuckingMode('pause');
    await cubit.setDuckingLevel(0.4);
    await cubit.setDspSnapshotEnabled(false);
    await cubit.setMultiOutputMode('speakerAndBluetooth');

    expect(cubit.state.multiOutputMode, 'systemDefault');
    expect(cubit.state.errorMessage, isNotNull);
  });

  test('EqualizerManager owns the DSP push and preference writes', () async {
    final manager = MockEqualizerManager();
    when(() => manager.setDspPreference(any())).thenAnswer((_) async {});
    when(() => manager.setBypassDspForBitPerfect(any()))
        .thenAnswer((_) async {});
    getIt.registerSingleton<EqualizerManager>(manager);

    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;

    await cubit.setDspPreference('native');
    verify(() => manager.setDspPreference(any())).called(greaterThanOrEqualTo(1));

    cubit.safeEmit(cubit.state.copyWith(bitPerfectOutput: true));
    await cubit.setBypassDspOnBitPerfect(true);
    verify(() => manager.setBypassDspForBitPerfect(true))
        .called(greaterThanOrEqualTo(1));

    // A failing push surfaces an error instead of throwing.
    when(() => manager.setBypassDspForBitPerfect(any()))
        .thenAnswer((_) async => throw Exception('bypass'));
    await cubit.setBypassDspOnBitPerfect(true);
    expect(cubit.state.errorMessage, isNotNull);
  });

  test('lookahead limiter without overrides uses the current state values',
      () async {
    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;

    cubit.safeEmit(cubit.state.copyWith(
      limiterThresholdDb: -1.5,
      limiterReleaseMs: 70,
      limiterLookaheadMs: 4,
    ));

    await cubit.setLookaheadLimiter(true);
    expect(cubit.state.limiterEnabled, isTrue);
    expect(cubit.state.limiterThresholdDb, -1.5);
    expect(cubit.state.limiterReleaseMs, 70.0);
    expect(cubit.state.limiterLookaheadMs, 4.0);
  });

  test('Bluetooth route hard-blocks bit-perfect before touching native',
      () async {
    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;

    cubit.safeEmit(cubit.state.copyWith(
      currentOutputDevice: const AudioOutputInfo(
        deviceName: 'BT',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
        isBluetooth: true,
      ),
    ));

    await cubit.setBitPerfectOutput(true);
    expect(cubit.state.bitPerfectOutput, isFalse);
    expect(cubit.state.errorMessage, isNotNull);
  });

  test('Android direct-USB fallback starts then stops bit-perfect', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(hiresChannel, (call) async {
      switch (call.method) {
        case 'setBitPerfectModeDetailed':
          return <String, dynamic>{
            'success': false,
            'reason': 'usb_not_supported',
          };
        case 'getAudioOutputInfo':
          return <String, dynamic>{
            'deviceName': 'USB DAC',
            'isUsbDac': true,
            'sampleRate': 96000,
            'bitDepth': 24,
            'isBitPerfectActive': false,
          };
        case 'setBitPerfectMode':
          return false;
        default:
          return null;
      }
    });
    var streaming = false;
    messenger.setMockMethodCallHandler(usbChannel, (call) async {
      switch (call.method) {
        case 'getStatus':
          return <String, dynamic>{
            'attached': true,
            'permitted': true,
            'streamingSupported': true,
            'streamingActive': streaming,
            'deviceName': 'USB DAC',
            'supportedRates': <int>[48000, 96000],
          };
        case 'startStreaming':
          streaming = true;
          return {'success': true};
        case 'stopStreaming':
          streaming = false;
          return {'success': true};
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(usbEvents, (call) async => null);

    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;

    cubit.safeEmit(cubit.state.copyWith(
      currentOutputDevice: const AudioOutputInfo(
        deviceName: 'USB DAC',
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: false,
      ),
    ));

    await cubit.setBitPerfectOutput(true);
    expect(cubit.state.bitPerfectOutput, isTrue);

    await cubit.setBitPerfectOutput(false);
    expect(cubit.state.bitPerfectOutput, isFalse);
    expect(streaming, isFalse);
  });

  test('target output format is persisted when the platform accepts it',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(hiresChannel, (call) async {
      if (call.method == 'setTargetOutputFormat') return true;
      if (call.method == 'getAudioOutputInfo') return <String, dynamic>{};
      return null;
    });

    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;

    await cubit.setTargetOutputSampleRate(96000);
    await cubit.setTargetOutputBitDepth(24);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('target_output_sample_rate'), 96000);
    expect(prefs.getInt('target_output_bit_depth'), 24);
  });

  test('bluetooth auto-calibration matches the codec table', () async {
    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;

    cubit.safeEmit(cubit.state.copyWith(
      currentOutputDevice: const AudioOutputInfo(
        deviceName: 'BT',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
        isBluetooth: true,
        btCodecName: 'LDAC',
      ),
    ));

    var calls = 0;
    final offset = await cubit.autoCalibrateBluetoothLatency(probe: () async {
      calls++;
      return 200;
    });
    expect(offset, inInclusiveRange(0, 500));
    expect(calls, 5);
  });
}
