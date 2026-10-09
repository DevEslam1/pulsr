// test/data/audio/audio_effects_channel_extended_test.dart
//
// Extended coverage for [AudioEffectsChannel]: exercises the native setter
// wrappers, capability probes, telemetry/degradation paths and DSD decoding
// under an Android target-platform override with the platform channel fully
// stubbed (deterministic; no real native/plugin).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/dsp_telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PulsrChannels.audioEffects);
  final calls = <MethodCall>[];

  void stubChannel({Map<String, dynamic>? debugStatus}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getCapabilities':
          return {
            'isVirtualizerSupported': true,
            'isDynamicsSupported': true,
            'isVolumeBoostSupported': true,
            'isBassBoostSupported': true,
            'isFloatOutputSupported': true,
            'isHardwareOffloadSupported': true,
          };
        case 'getProcessingCapabilities':
          return {'isPcmDspAttached': true, 'hasPcmDspPath': true};
        case 'getSpatializerState':
          return {'isSupported': true, 'isHeadTrackerAvailable': true};
        case 'detectOemAudio':
          return {
            'hasOemAudio': true,
            'detectedEngines': <dynamic>['Dolby', 'DTS'],
          };
        case 'detectSystemEffects':
          return {
            'status': 'active',
            'detectedBundles': <dynamic>['com.dolby'],
            'hasDolbyOrVendor': true,
          };
        case 'setSystemEffectsPolicy':
          return {'status': 'applied'};
        case 'getSystemEffectsStatus':
          return {'status': 'bypassed', 'detectedBundles': <dynamic>[]};
        case 'awaitDspControlUpdates':
          return true;
        case 'hasActiveEffects':
          return true;
        case 'getRtfGovernorStatus':
          return {'enabled': true, 'rtf': 0.5};
        case 'loadLiveProgCode':
          return 'OK';
        case 'getPipelineLatencyFrames':
          return 512;
        case 'getAppliedSampleRate':
          return 44100;
        case 'getAutoDegradedStages':
          return 8;
        case 'getThermalStatus':
          return 2;
        case 'getWeeklyDose':
          return 0.75;
        case 'getTelemetry':
          return List<dynamic>.filled(17, 0.0);
        case 'decodeDsd':
          return <dynamic>[0.0, 0.25, -0.25];
        case 'getDspDebugStatus':
          return debugStatus;
        case 'getDspBatteryDrainEstimate':
          return {'dspMaHPerHour': 12.0};
        case 'getChainOfCustodyReport':
          return {'sampleRate': 48000};
        case 'verifyState':
          return {'ok': true};
        case 'releaseEffects':
          return true;
        default:
          // All bool-returning setters ACK by default.
          return true;
      }
    });
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    AudioEffectsChannel.lastPushedBypassDspForBitPerfect = null;
    stubChannel();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('init probes capabilities, pipeline, spatializer and OEM engines',
      () async {
    final effects = AudioEffectsChannel();
    await effects.init();

    expect(effects.isVirtualizerSupported, isTrue);
    expect(effects.isDynamicsSupported, isTrue);
    expect(effects.isVolumeBoostSupported, isTrue);
    expect(effects.isBassBoostSupported, isTrue);
    expect(effects.isFloatOutputSupported, isTrue);
    expect(effects.isPcmDspAttached, isTrue);
    expect(effects.hasPcmDspPath, isTrue);
    expect(effects.isSpatializerSupported, isTrue);
    expect(effects.isHeadTrackerAvailable, isTrue);
    expect(effects.hasOemAudio, isTrue);
    expect(effects.detectedOemEngines, ['Dolby', 'DTS']);
    expect(effects.isPlaybackSincResamplerSupported, isFalse);
  });

  test('awaitControlUpdates reports the native bool', () async {
    expect(await AudioEffectsChannel().awaitControlUpdates(), isTrue);
  });

  test('awaitControlUpdates swallows platform errors as false', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'BOOM');
    });
    expect(await AudioEffectsChannel().awaitControlUpdates(), isFalse);
  });

  test('system-effects queries and policy round-trip', () async {
    final effects = AudioEffectsChannel();
    expect(await effects.detectSystemEffects(), containsPair('status', 'active'));
    expect(await effects.setSystemEffectsPolicy('tryDisable'),
        'applied');
    expect(await effects.getSystemEffectsStatus(),
        containsPair('status', 'bypassed'));
    expect(await effects.hasActiveEffects(), isTrue);
    expect(await effects.detectOemAudio(), containsPair('hasOemAudio', true));
  });

  test('volume / DVC / bass / virtualizer / dynamics / spatializer setters',
      () async {
    final effects = AudioEffectsChannel();
    expect(await effects.setVolumeBoost(300), isTrue);
    expect(await effects.isDvcSupported(), isTrue);
    expect(await effects.setDvcEnabled(true), isTrue);
    expect(await effects.setDvcGain(0.5), isTrue);
    expect(await effects.setDvcGain(double.nan), isFalse);
    expect(await effects.setBassBoost(2000), isTrue);
    expect(await effects.setVirtualizerEnabled(true), isTrue);
    expect(await effects.setVirtualizerStrength(0.7), isTrue);
    expect(
      await effects.setDynamicsPreset(DynamicsPreset.studioPunch, true),
      isTrue,
    );
    expect(await effects.setSpatializerEnabled(true), isTrue);
  });

  test('EQ setter wrappers ack (bands, gains, preamp)', () async {
    final effects = AudioEffectsChannel();
    await effects.setEqEnabled(true);
    expect(await effects.setEqBands([100.0, 1000.0]), isTrue);
    expect(await effects.setEqBandGain(0, 3.0), isTrue);
    expect(await effects.setEqBandGains([1.0, 2.0]), isTrue);
    await effects.setEqPreamp(-3.0);
    expect(await effects.setNativeEqBand(0, 1000.0, 2.0, 1.414), isTrue);
    expect(
      await effects.setNativeEqBandsBulk(
        frequencies: [100.0, 1000.0],
        gains: [1.0, 2.0],
      ),
      isTrue,
    );
    expect(await effects.setNativeEqBandCount(2), isTrue);
    await effects.setNativeEqEnabled(true);
    expect(calls.where((c) => c.method == 'setEqBands'), isNotEmpty);
  });

  test('bit-perfect bypass and compare reach native and record state',
      () async {
    final effects = AudioEffectsChannel();
    await effects.setBypassDspForBitPerfect(true, isDop: true);
    expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, isTrue);
    await effects.setBypassCompare(bypass: true, gainCompensationDb: -2.0);
    expect(
      calls.map((c) => c.method),
      containsAll(<String>['setBypassDspForBitPerfect', 'setBypassCompare']),
    );
  });

  test('RTF governor and ReplayGain round-trip', () async {
    final effects = AudioEffectsChannel();
    expect(await effects.getRtfGovernorStatus(),
        containsPair('enabled', true));
    await effects.setRtfGovernorEnabled(false);
    expect(
      await effects.setReplayGainParams(
        mode: 1,
        trackGainDb: -2.0,
        albumGainDb: -1.0,
        trackPeak: 0.9,
        albumPeak: 0.95,
        preAmpDb: 0.0,
        enabled: true,
      ),
      isTrue,
    );
    expect(await effects.setReplayGainEnabled(true), isTrue);
  });

  test('native DSP setter wrappers forward without throwing', () async {
    final effects = AudioEffectsChannel();
    await effects.setCrossfeedEnabled(true);
    await effects.setCrossfeedParams(350.0, -9.0, fcut: 700.0);
    await effects.setCrossfeedMode(2);
    await effects.setLimiterEnabled(true);
    await effects.setLimiterParams(3.0, -0.2, 50.0,
        ratio: 3.0, attackMs: 15.0, makeupGainDb: 1.0);
    await effects.setReverbEnabled(true);
    await effects.setReverbPreset(1);
    await effects.setReverbWetDry(0.3);
    await effects.setReverbCrossChannel(0.2);
    await effects.setReverbParams(predelayMs: 10.0, damping: 0.4, crossChannel: 0.1);
    await effects.setStereoBalance(0.2);
    await effects.setMonoMix(false);
    await effects.setSincResamplerEnabled(true);
    await effects.setSincResamplerRates(44100.0, 48000.0);
    await effects.setSincResamplerQuality(3);
    await effects.setSaturationEnabled(true);
    await effects.setSaturationParams(0.5, 0.5, 0.5, mode: 1);
    await effects.setSaturationMultiband(true);
    await effects.setStereoWidthEnabled(true);
    await effects.setStereoWidthParams(1.4,
        multiband: true, lowWidth: 1.2, midWidth: 1.1, highWidth: 1.0);
    await effects.setLoudnessContourEnabled(true);
    await effects.setLoudnessContourParams(0.5, 0.4);
    await effects.setSubCrossoverEnabled(true);
    await effects.setSubCrossoverParams(80.0, 24.0, 0.8);
    await effects.setDynamicEqEnabled(true);
    await effects.setDynamicEqBandCount(2);
    await effects.setDynamicEqBand(
      0,
      frequency: 100.0,
      q: 1.0,
      thresholdDb: -20.0,
      ratio: 2.0,
      attackMs: 10.0,
      releaseMs: 80.0,
      maxCutDb: 6.0,
    );
    await effects.setMultibandCompressorEnabled(true);
    await effects.setMultibandCompressorBand(
      0,
      thresholdDb: -18.0,
      ratio: 2.0,
      attackMs: 15.0,
      releaseMs: 100.0,
      kneeDb: 6.0,
      makeupGainDb: 0.0,
    );
    await effects.setMultibandCompressorCrossovers(f0: 160, f1: 1000, f2: 5000);
    await effects.setDynamicBassParams(
      enabled: true,
      strength: 1.0,
      xLow: 100,
      xHigh: 5600,
      yLow: 40,
      yHigh: 80,
      sideGainLow: 0.1,
      sideGainHigh: 0.5,
      devicePreset: 0,
    );
    await effects.setViperDdcEnabled(true);
    expect(await effects.loadViperDdc(ddcContent: 'x', profileName: 'p'),
        isTrue);
    await effects.setArbitraryEqEnabled(true);
    expect(await effects.loadArbitraryEq(eqString: 'GraphicEq: 20 0'),
        isTrue);
    await effects.setLiveProgEnabled(true);
    expect(await effects.loadLiveProgCode('@init'), 'OK');
    await effects.setLiveProgSlider(1, 0.5);
    await effects.setHeadphoneSafetyParams(enabled: true);
    await effects.setBandSolo(0, true);
    await effects.setBandMute(0, false);
    await effects.setBitPerfectParams(enabled: true, isDop: false);
    expect(
      await effects.setDitherParams(
          enabled: true, targetBitDepth: 24, isBluetooth: false),
      isTrue,
    );
    await effects.releaseEffects();
    await effects.resyncForTrack(48000.0);
    await effects.setCacheBudgetBytes(16 * 1024 * 1024);
    expect(calls, isNotEmpty);
  });

  test('impulse response load rejects empty payloads', () async {
    final effects = AudioEffectsChannel();
    expect(await effects.loadImpulseResponse(const []), isFalse);
    expect(await effects.loadImpulseResponse(const [0.0, 0.5]), isTrue);
  });

  test('DSD decode handles normal and chunked payloads', () async {
    final effects = AudioEffectsChannel();
    final small = Uint8List.fromList(List<int>.generate(16, (i) => i));
    expect(await effects.decodeDsd(small, small), [0.0, 0.25, -0.25]);

    // Mismatched lengths short-circuit.
    expect(await effects.decodeDsd(small, Uint8List(8)), isNull);
    // Empty is a valid empty result.
    expect(await effects.decodeDsd(Uint8List(0), Uint8List(0)), isEmpty);

    // Force the chunked path (payload larger than the 64 KB chunk size).
    final big = Uint8List(70 * 1024);
    final decoded = await effects.decodeDsd(big, big);
    expect(decoded, isNotNull);
    expect(decoded, hasLength(6));
  });

  test('latency, sample-rate and thermal probes report values', () async {
    final effects = AudioEffectsChannel();
    expect(await effects.getPipelineLatencyFrames(), 512);
    expect(await effects.getAppliedSampleRate(), 44100.0);
    expect(await effects.getThermalStatus(), 2);
    expect(await effects.sendWarmupBuffer(), isTrue);
  });

  test('weekly dose and safety attenuation probes', () async {
    final effects = AudioEffectsChannel();
    expect(await effects.getWeeklyDose(), 0.75);
    expect(await effects.resetWeeklyDose(), isTrue);
    expect(await effects.isSafetyAttenuationActive(), isTrue);
  });

  test('auto-degrade transition emits exactly once per 0 -> nonzero', () async {
    final effects = AudioEffectsChannel();
    final transitions = <int>[];
    final sub = effects.onAutoDegradedSessionStarted.listen(transitions.add);

    expect(await effects.getAutoDegradedStages(), 8);
    // Same session: no repeat emission.
    expect(await effects.getAutoDegradedStages(), 8);
    await Future<void>.delayed(Duration.zero);
    expect(transitions, [8]);
    await sub.cancel();
  });

  test('telemetry parses a native list payload', () async {
    final telemetry = await AudioEffectsChannel().getTelemetry();
    expect(telemetry.autoDegradedStages, 0);
  });

  test('telemetry throws on an unexpected payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'nope');
    await expectLater(
      AudioEffectsChannel().getTelemetry(),
      throwsA(isA<StateError>()),
    );
  });

  test('DSP debug status/report parses a full map', () async {
    stubChannel(debugStatus: {
      'audioSessionId': 99,
      'isSessionAttached': true,
      'dspPreference': 'native',
      'isBitPerfectBypassActive': false,
      'isNativeDspLoaded': true,
      'activeDspStagesMask': 3,
      'autoDegradedStagesMask': 0,
      'hasOemAudio': false,
      'detectedEngines': <dynamic>['Dolby'],
      'activeEffectNames': <dynamic>['EQ'],
      'stages': [
        {
          'name': 'Parametric EQ',
          'category': 'C++ Native',
          'isSupported': true,
          'isEnabled': true,
        },
      ],
      'timestamp': '2026-01-01T00:00:00.000Z',
    });
    final effects = AudioEffectsChannel();
    expect(await effects.getDspDebugStatus(), isNotNull);
    final report = await effects.getDspDebugReport();
    expect(report, isNotNull);
    expect(report!.audioSessionId, 99);
    expect(report.stages.single.name, 'Parametric EQ');
  });

  test('battery drain and chain-of-custody reports return maps', () async {
    final effects = AudioEffectsChannel();
    expect(await effects.getDspBatteryDrainEstimate(),
        containsPair('dspMaHPerHour', 12.0));
    expect(await effects.getChainOfCustodyReport(),
        containsPair('sampleRate', 48000));
    expect(await effects.verifyState(), containsPair('ok', true));
  });

  test('setDspPreference succeeds on the first native attempt', () async {
    await AudioEffectsChannel().setDspPreference('native');
    expect(calls.where((c) => c.method == 'setDspPreference').length, 1);
  });

  test('dispose resets capability state and detaches the singleton', () async {
    final effects = AudioEffectsChannel();
    await effects.init();
    expect(effects.isVirtualizerSupported, isTrue);
    effects.dispose();
    expect(effects.isVirtualizerSupported, isFalse);
    expect(effects.hasPcmDspPath, isFalse);
    // A new factory call yields a fresh instance.
    expect(AudioEffectsChannel(), isNot(same(effects)));
  });

  test('non-Android short-circuits every native call', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final effects = AudioEffectsChannel();
    await effects.init();
    expect(calls, isEmpty);
    expect(await effects.awaitControlUpdates(), isTrue);
    expect(await effects.setVolumeBoost(100), isFalse);
    expect(await effects.isDvcSupported(), isFalse);
    expect(await effects.setEqBands([1.0]), isTrue);
    expect(await effects.getTelemetry(), const DspTelemetry.zero());
    expect(await effects.getWeeklyDose(), 0.0);
    expect(await effects.getPipelineLatencyFrames(), 0);
    expect(await effects.getAppliedSampleRate(), 48000.0);
    expect(await effects.getThermalStatus(), 0);
    expect(await effects.getAutoDegradedStages(), 0);
    expect(await effects.detectOemAudio(),
        containsPair('hasOemAudio', false));
    expect(await effects.detectSystemEffects(),
        containsPair('status', 'unsupportedDevice'));
    expect(await effects.getSystemEffectsStatus(),
        containsPair('status', 'unsupportedDevice'));
    expect(await effects.hasActiveEffects(), isFalse);
    expect(await effects.setDitherParams(
        enabled: true, targetBitDepth: 16, isBluetooth: false),
        isFalse);
    expect(await effects.loadViperDdc(ddcContent: 'x', profileName: 'p'),
        isFalse);
    expect(await effects.loadArbitraryEq(eqString: 'x'), isFalse);
    expect(await effects.loadLiveProgCode('x'), 'Unsupported platform');
    expect(await effects.loadImpulseResponse(const [1.0]), isFalse);
    expect(await effects.sendWarmupBuffer(), isTrue);
    expect(await effects.decodeDsd(Uint8List(4), Uint8List(4)), isNull);
    expect(await effects.getDspDebugStatus(), isNull);
    expect(await effects.getDspDebugReport(), isNull);
    expect(await effects.getDspBatteryDrainEstimate(), isEmpty);
    expect(await effects.getChainOfCustodyReport(), isEmpty);
    expect(await effects.verifyState(), isNull);
    expect(await effects.getRtfGovernorStatus(),
        containsPair('enabled', false));
    // No-op native setters must still complete.
    await effects.setCrossfeedEnabled(true);
    await effects.setReverbEnabled(true);
    await effects.setSpatializerEnabled(true);
    await effects.setBypassDspForBitPerfect(true);
    await effects.setBypassCompare(bypass: true);
    await effects.setReplayGainEnabled(true);
  });
}
