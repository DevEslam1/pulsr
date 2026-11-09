// Additional coverage for lib/features/settings/cubit/settings_audio_actions.dart:
// the PulsrAudioHandler-backed live toggles (success + failure logging), the
// EqualizerManager-owned DSP push/limiter path, the Bluetooth bit-perfect hard
// block, the Android direct-USB fallback and the target-format/calibration
// helpers.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/audio/multi_output_router.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/services/device_profile_service.dart';
import 'package:pulsr/data/services/hires_audio_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/settings_section_harness.dart';

class MockAudioHandler extends Mock implements PulsrAudioHandler {}

class MockEqualizerManager extends Mock implements EqualizerManager {}

class MockHiResAudioService extends Mock implements HiResAudioService {}

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

  test(
      'handler-backed toggles succeed and a rejected AAudio/multi-output reverts',
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
    verify(() => manager.setDspPreference(any()))
        .called(greaterThanOrEqualTo(1));

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

  test('bit-perfect disables an already-on silence skip and restores it',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final handler = registeredHandler();
    when(() => handler.setSkipSilenceEnabled(any()))
        .thenAnswer((_) async {});
    when(() => handler.setSilenceSkipSensitivity(any()))
        .thenAnswer((_) async {});

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(hiresChannel, (call) async {
      switch (call.method) {
        case 'setBitPerfectModeDetailed':
          return <String, dynamic>{'success': true};
        case 'setBitPerfectMode':
          return true;
        case 'getAudioOutputInfo':
          return <String, dynamic>{
            'deviceName': 'USB DAC',
            'isUsbDac': true,
            'sampleRate': 96000,
            'bitDepth': 24,
            'isBitPerfectActive': true,
          };
        default:
          return null;
      }
    });

    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;
    cubit.safeEmit(cubit.state.copyWith(
      currentOutputDevice: const AudioOutputInfo(
        deviceName: 'USB DAC',
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: true,
      ),
      bypassDspOnBitPerfect: true,
      silenceSkipSensitivity: 60,
    ));

    await cubit.setBitPerfectOutput(true);
    expect(cubit.state.bitPerfectOutput, isTrue);
    verify(() => handler.setSkipSilenceEnabled(false)).called(1);

    await cubit.setBitPerfectOutput(false);
    expect(cubit.state.bitPerfectOutput, isFalse);
    verify(() => handler.setSilenceSkipSensitivity(60)).called(1);
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
    var streamRate = 0;
    var streamDepth = 0;
    var streamChannels = 0;
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
            // A start is only owned once the endpoint reports the format it
            // actually opened on this device.
            'deviceId': 7,
            'streamingSampleRate': streamRate,
            'streamingBitDepth': streamDepth,
            'streamingChannels': streamChannels,
          };
        case 'startStreaming':
          final args = (call.arguments as Map).cast<String, dynamic>();
          streaming = true;
          streamRate = args['sampleRate'] as int;
          streamDepth = args['bitDepth'] as int;
          streamChannels = args['channels'] as int? ?? 2;
          return {'success': true};
        case 'stopStreaming':
          streaming = false;
          streamRate = 0;
          streamDepth = 0;
          streamChannels = 0;
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

  group('direct USB ownership', () {
    const usbDac = AudioOutputInfo(
      deviceName: 'USB DAC',
      isUsbDac: true,
      sampleRate: 96000,
      bitDepth: 24,
      isBitPerfectActive: false,
    );

    void stubPlatform({
      bool bitPerfectRefused = true,
      Map<String, dynamic>? Function(String method, Map<String, dynamic> args)?
          usb,
    }) {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(hiresChannel, (call) async {
        if (call.method == 'setBitPerfectModeDetailed') {
          return bitPerfectRefused
              ? <String, dynamic>{
                  'success': false,
                  'reason': 'no_supported_mixer_attributes',
                }
              : <String, dynamic>{'success': true};
        }
        if (call.method == 'getAudioOutputInfo') {
          return <String, dynamic>{'deviceName': 'USB DAC', 'isUsbDac': true};
        }
        if (call.method == 'setOutputDevice') {
          return <String, dynamic>{'success': true};
        }
        return null;
      });
      messenger.setMockMethodCallHandler(usbEvents, (call) async => null);
      messenger.setMockMethodCallHandler(usbChannel, (call) async {
        final args = call.arguments is Map
            ? (call.arguments as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        return usb?.call(call.method, args);
      });
    }

    test('a route change whose stop was refused keeps endpoint ownership',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var stopWorks = false;
      var started = false;
      stubPlatform(usb: (method, args) {
        switch (method) {
          case 'getStatus':
            return <String, dynamic>{
              'attached': true,
              'permitted': true,
              'streamingSupported': true,
              'streamingActive': started,
              'deviceId': 7,
              'supportedRates': <int>[48000, 96000],
              'streamingSampleRate': started ? 96000 : 0,
              'streamingBitDepth': started ? 24 : 0,
              'streamingChannels': started ? 2 : 0,
            };
          case 'startStreaming':
            started = true;
            return <String, dynamic>{'success': true};
          case 'stopStreaming':
            if (!stopWorks) return <String, dynamic>{'success': false};
            started = false;
            return <String, dynamic>{'success': true};
          default:
            return null;
        }
      });
      final cubit = make();
      addTearDown(cubit.close);
      await cubit.preferencesReady;
      cubit.safeEmit(cubit.state.copyWith(currentOutputDevice: usbDac));

      await cubit.setBitPerfectOutput(true);
      expect(cubit.bitPerfectViaDirectStream, isTrue);

      await cubit.selectOutputDevice(99);
      // Clearing the flag after a refused stop would strand a live endpoint on
      // the old DAC with nothing left to release it.
      expect(cubit.bitPerfectViaDirectStream, isTrue);
      expect(
        cubit.state.errorMessage,
        contains(RegExp('could not (be )?stop', caseSensitive: false)),
      );

      stopWorks = true;
      await cubit.setBitPerfectOutput(false);
      expect(cubit.bitPerfectViaDirectStream, isFalse);
      expect(started, isFalse);
    });

    test('a track format the sink refuses does not switch Bit-Perfect off',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var acceptedFormats = <String>['96000/24'];
      stubPlatform(usb: (method, args) {
        switch (method) {
          case 'getStatus':
            return <String, dynamic>{
              'attached': true,
              'permitted': true,
              'streamingSupported': true,
              'streamingActive': true,
              'deviceId': 7,
              'supportedRates': <int>[96000],
              'streamingSampleRate': 96000,
              'streamingBitDepth': 24,
              'streamingChannels': 2,
            };
          case 'startStreaming':
            final key = '${args['sampleRate']}/${args['bitDepth']}';
            if (!acceptedFormats.contains(key)) {
              return <String, dynamic>{
                'success': false,
                'error': 'format_unsupported',
              };
            }
            return <String, dynamic>{'success': true};
          case 'stopStreaming':
            return <String, dynamic>{'success': true};
          default:
            return null;
        }
      });
      final cubit = make();
      addTearDown(cubit.close);
      await cubit.preferencesReady;
      cubit.safeEmit(cubit.state.copyWith(currentOutputDevice: usbDac));

      await cubit.setBitPerfectOutput(true);
      expect(cubit.state.bitPerfectOutput, isTrue);

      acceptedFormats = <String>['192000/24'];
      final applied =
          await cubit.setBitPerfectTrackFormat(sampleRate: 352800, bitDepth: 16);

      expect(applied, isFalse);
      // One unreadable format must not permanently discard the preference.
      expect(cubit.state.bitPerfectOutput, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.bitPerfectOutput), isTrue);
      expect(cubit.state.errorMessage, contains('352800'));
    });

    test('an unknown track format asks the DAC for its own rate', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      Map<String, dynamic>? startArgs;
      stubPlatform(usb: (method, args) {
        switch (method) {
          case 'getStatus':
            return <String, dynamic>{
              'attached': true,
              'permitted': true,
              'streamingSupported': true,
              'streamingActive': false,
              'deviceId': 7,
              'supportedRates': <int>[96000],
            };
          case 'startStreaming':
            startArgs = args;
            return <String, dynamic>{
              'success': true,
            };
          case 'stopStreaming':
            return <String, dynamic>{'success': true};
          default:
            return null;
        }
      });
      final handler = MockAudioHandler();
      getIt.registerSingleton<PulsrAudioHandler>(handler);
      when(() => handler.currentSong).thenReturn(const SongsTableData(
        id: 1,
        title: 'Unknown header',
        artist: 'A',
        album: 'B',
        durationMs: 1000,
        path: '/music/track.flac',
        source: SongSource.local,
        playCount: 0,
        dateAdded: 0,
        isFavorite: false,
        isMissing: false,
        lastPositionMs: 0,
        isDownloaded: false,
        sampleRate: 0,
        bitDepth: 0,
      ));

      final cubit = make();
      addTearDown(cubit.close);
      await cubit.preferencesReady;
      cubit.safeEmit(cubit.state.copyWith(currentOutputDevice: usbDac));

      await cubit.setBitPerfectOutput(true);

      // 0 Hz / 0-bit is "not read", not a format: forwarding it would be
      // refused as format_unsupported and look like a broken DAC.
      expect(startArgs, isNotNull);
      expect(startArgs!['sampleRate'], isNot(0));
      expect(startArgs!['bitDepth'], isNot(0));
      await getIt.unregister<PulsrAudioHandler>();
    });
  });

  test('strict bit-perfect refusal restores the settings it touched', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(hiresChannel, (call) async {
      if (call.method == 'setBitPerfectModeDetailed') {
        return <String, dynamic>{'success': false, 'reason': 'requires_android_14'};
      }
      if (call.method == 'getAudioOutputInfo') {
        return <String, dynamic>{'deviceName': 'USB DAC', 'isUsbDac': true};
      }
      return null;
    });
    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;
    cubit.safeEmit(cubit.state.copyWith(
      currentOutputDevice: const AudioOutputInfo(
        deviceName: 'USB DAC',
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: true,
      ),
      bitPerfectOutput: true,
      bypassDspOnBitPerfect: true,
      followTrackSampleRate: false,
      // AAudio Direct makes the direct-USB fallback refuse without touching
      // the endpoint, so this test stays on the platform-exclusive path.
      aaudioOutputEnabled: true,
    ));

    await cubit.setStrictBitPerfect(true);

    expect(cubit.state.strictBitPerfect, isFalse);
    // Bit-Perfect and its bypass were already on: refusing Strict must not
    // quietly strip a working exclusive configuration.
    expect(cubit.state.bitPerfectOutput, isTrue);
    expect(cubit.state.bypassDspOnBitPerfect, isTrue);
    expect(cubit.state.followTrackSampleRate, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.bitPerfectOutput), isTrue);
    expect(prefs.getBool(PrefsKeys.bypassDspOnBitPerfect), isTrue);
  });

  test('a refused AAudio toggle leaves crossfade and DVC alone', () async {
    final handler = registeredHandler();
    var accepted = false;
    when(() => handler.setAaudioOutputEnabled(
      any(),
      preferExclusive: any(named: 'preferExclusive'),
      targetBufferMs: any(named: 'targetBufferMs'),
    )).thenAnswer((_) async => accepted);

    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;
    cubit.safeEmit(cubit.state.copyWith(crossfadeSeconds: 4.0, dvcEnabled: true));

    await cubit.setAaudioOutputEnabled(true);

    expect(cubit.state.aaudioOutputEnabled, isFalse);
    expect(cubit.state.crossfadeSeconds, 4.0);
    expect(cubit.state.dvcEnabled, isTrue);

    accepted = true;
    await cubit.setAaudioOutputEnabled(true);
    expect(cubit.state.aaudioOutputEnabled, isTrue);
    expect(cubit.state.crossfadeSeconds, 0.0);
    expect(cubit.state.dvcEnabled, isFalse);
    // The message must explain the AAudio reason, not claim Bit-Perfect.
    expect(cubit.state.errorMessage, contains('AAudio'));
  });

  test('a stale output refresh cannot overwrite a newer one', () async {
    const newer = AudioOutputInfo(
      deviceName: 'Newer DAC',
      isUsbDac: true,
      sampleRate: 96000,
      bitDepth: 24,
      isBitPerfectActive: false,
    );
    const older = AudioOutputInfo(
      deviceName: 'Stale route',
      isUsbDac: false,
      sampleRate: 48000,
      bitDepth: 16,
      isBitPerfectActive: false,
      isBluetooth: true,
    );

    final service = MockHiResAudioService();
    when(() => service.outputDeviceStream)
        .thenAnswer((_) => const Stream<AudioOutputInfo>.empty());
    when(() => service.getAudioOutputInfo())
        .thenAnswer((_) async => const AudioOutputInfo(
              deviceName: 'Boot',
              isUsbDac: false,
              sampleRate: 48000,
              bitDepth: 16,
              isBitPerfectActive: false,
            ));
    getIt.registerSingleton<HiResAudioService>(service);
    addTearDown(() async => getIt.unregister<HiResAudioService>());

    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;

    final first = Completer<AudioOutputInfo>();
    final second = Completer<AudioOutputInfo>();
    var calls = 0;
    when(() => service.getAudioOutputInfo()).thenAnswer((_) {
      calls++;
      return calls == 1 ? first.future : second.future;
    });

    final a = cubit.refreshOutputDevice();
    final b = cubit.refreshOutputDevice();
    // The newer request answers first; the older one lands afterwards.
    second.complete(newer);
    await b;
    first.complete(older);
    await a;

    expect(cubit.state.currentOutputDevice?.deviceName, 'Newer DAC');
  });

  test('an uncalibrated Bluetooth device gets the global offset, not the last one',
      () async {
    const globalMs = 40;
    const headsetA = AudioOutputInfo(
      deviceName: 'Headset A',
      isUsbDac: false,
      sampleRate: 48000,
      bitDepth: 16,
      isBitPerfectActive: false,
      isBluetooth: true,
      activeDeviceType: 'bluetooth',
    );
    const headsetB = AudioOutputInfo(
      deviceName: 'Headset B',
      isUsbDac: false,
      sampleRate: 48000,
      bitDepth: 16,
      isBitPerfectActive: false,
      isBluetooth: true,
      activeDeviceType: 'bluetooth',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(hiresChannel, (call) async {
      if (call.method == 'getAudioOutputInfo') return <String, dynamic>{};
      return null;
    });

    final service = MockHiResAudioService();
    final devices = StreamController<AudioOutputInfo>.broadcast();
    when(() => service.outputDeviceStream).thenAnswer((_) => devices.stream);
    when(() => service.getAudioOutputInfo())
        .thenAnswer((_) async => headsetA);
    getIt.registerSingleton<HiResAudioService>(service);
    addTearDown(() async {
      await devices.close();
      await getIt.unregister<HiResAudioService>();
    });

    SharedPreferences.setMockInitialValues({
      PrefsKeys.bluetoothLatencyOffsetMs: globalMs,
      // Headset A was calibrated for; B never was.
      'setting_bt_latency_by_device': json.encode({
        DeviceProfileService.deviceKeyFromInfo(headsetA): 160,
      }),
    });

    final cubit = make();
    addTearDown(cubit.close);
    await cubit.preferencesReady;

    devices.add(headsetA);
    await pumpEventQueue();
    expect(cubit.state.bluetoothLatencyOffsetMs, 160);

    devices.add(headsetB);
    await pumpEventQueue();
    // A's compensation must not leak onto B: B falls back to the stored global.
    expect(cubit.state.bluetoothLatencyOffsetMs, globalMs);
  });
}
