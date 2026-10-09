// test/data/audio/equalizer_manager_more_test.dart
//
// Additional coverage for the branches the extended suite leaves untouched:
// native-bulk fallbacks, effect-status bookkeeping, loudness auto-contour,
// ViPER-DDC rollback, parametric-profile rejection, degrade/restore with user
// edits, the full-state resync fan-out and the seeded-preference restore path.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/models/reverb_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PulsrChannels.audioEffects);
  final calls = <MethodCall>[];
  final overrides = <String, dynamic>{};
  final throwMethods = <String>{};

  void installChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (throwMethods.contains(call.method)) {
        throw PlatformException(
            code: 'ERR', message: 'forced ${call.method}');
      }
      if (overrides.containsKey(call.method)) return overrides[call.method];
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
          return {'hasOemAudio': false, 'detectedEngines': <dynamic>[]};
        case 'loadLiveProgCode':
          return 'OK';
        case 'getTelemetry':
          return List<dynamic>.filled(17, 0.0);
        case 'getRtfGovernorStatus':
          return {'enabled': false};
        case 'getPipelineLatencyFrames':
          return 128;
        case 'getAutoDegradedStages':
          return <dynamic>[];
        case 'getWeeklyDose':
          return 0.0;
        case 'verifyState':
          return {'eqEnabled': true, 'preampDb': 0.0};
        default:
          return true;
      }
    });
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    overrides.clear();
    throwMethods.clear();
    SharedPreferences.setMockInitialValues({});
    AudioEffectsChannel.lastPushedBypassDspForBitPerfect = null;
    installChannel();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<EqualizerManager> newManager() async {
    final manager = EqualizerManager();
    await manager.init();
    return manager;
  }

  bool hasCall(String method) => calls.any((c) => c.method == method);

  test('setBandMode falls back to per-band writes and the legacy mirror',
      () async {
    throwMethods.add('setNativeEqBandsBulk');
    final manager = await newManager();

    await manager.setBandMode(32);
    expect(manager.eqBandCount, 32);
    expect(hasCall('setNativeEqBand'), isTrue);
    expect(hasCall('setEqBands'), isTrue); // legacy mirror (non-10-band branch)

    calls.clear();
    await manager.setBandMode(10);
    expect(manager.eqBandCount, 10);
    expect(hasCall('setEqBands'), isTrue);
    expect(hasCall('setEqBandGains'), isTrue);
  });

  test('applyCurrentPreset falls back for the 10-band and multi-band plans',
      () async {
    // 10-band fallback.
    throwMethods.add('setNativeEqBandsBulk');
    final manager = await newManager();
    await manager.setEnabled(true);
    expect(hasCall('setEqBands'), isTrue);
    expect(hasCall('setNativeEqBandCount'), isTrue);

    // Multi-band fallback.
    calls.clear();
    throwMethods.remove('setNativeEqBandsBulk');
    await manager.setBandMode(32);
    throwMethods.add('setNativeEqBandsBulk');
    await manager.applyCurrentPreset();
    expect(hasCall('setNativeEqBand'), isTrue);
  });

  test('volume boost is clamped by the headphone preamp headroom and reports '
      'native rejection', () async {
    final manager = await newManager();
    manager.selectedHeadphoneProfile = const HeadphoneProfile(
      id: 'p',
      name: 'P',
      brand: 'B',
      model: 'M',
      category: 'Other',
      gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      preampGain: -2.0,
    );
    await manager.setVolumeBoost(1.0);
    expect(manager.volumeBoost, closeTo(0.8, 1e-6));

    // Native rejection surfaces in the status notifier, then clears.
    overrides['setVolumeBoost'] = false;
    await manager.setVolumeBoost(0.5);
    expect(manager.effectStatusNotifier.value['volumeBoost'], 'notApplied');

    overrides['setVolumeBoost'] = true;
    await manager.setVolumeBoost(0.5);
    expect(manager.effectStatusNotifier.value.containsKey('volumeBoost'), isFalse);

    // A zero boost is treated as applied even when native rejects.
    overrides['setVolumeBoost'] = false;
    await manager.setVolumeBoost(0.0);
  });

  test('auto loudness contour engages and disengages with the volume stage',
      () async {
    final manager = await newManager();
    await manager.updateLoudnessVolume(0.2);
    expect(manager.isLoudnessContourEnabled, isTrue);
    expect(manager.loudnessContourIntensity, closeTo(0.6, 1e-9));

    await manager.updateLoudnessVolume(0.9);
    expect(manager.isLoudnessContourEnabled, isFalse);

    // Bit-perfect bypass suppresses the automatic contour.
    manager.isBitPerfectBypass = true;
    await manager.updateLoudnessVolume(0.1);
    expect(manager.isLoudnessContourEnabled, isFalse);
  });

  test('ViPER-DDC rejection rolls back the profile and throws', () async {
    final manager = await newManager();
    overrides['loadViperDdc'] = false;
    await expectLater(
      manager.setViperDdc(true, profileName: 'Bad', coeffs: [1, 0, 0, 0, 0]),
      throwsA(isA<StateError>()),
    );
    expect(manager.viperDdcContent, isEmpty);
    expect(manager.viperDdcProfileName, isEmpty);
  });

  test('parametric headphone profile rejection falls back to the graphic path',
      () async {
    final manager = await newManager();
    await manager.setEnabled(true);
    throwMethods.add('setNativeEqBandsBulk');
    const profile = HeadphoneProfile(
      id: 'param',
      name: 'Param',
      brand: 'B',
      model: 'M',
      category: 'In-Ear',
      gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      filters: [EqFilter(frequency: 100, gain: 3, q: 1.0)],
    );
    await manager.setHeadphoneProfile(profile);
    expect(manager.selectedHeadphoneProfile, profile);
    // The rejected parametric push must have triggered the graphic fallback.
    expect(hasCall('setEqBands'), isTrue);
  });

  test('profiles with too many or all-invalid filters are rejected', () async {
    final manager = await newManager();

    final tooMany = HeadphoneProfile(
      id: 'many',
      name: 'Many',
      brand: 'B',
      model: 'M',
      category: 'Other',
      gains: const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      filters: List<EqFilter>.generate(
        65,
        (i) => EqFilter(frequency: 20.0 + i, gain: 1.0),
      ),
    );
    await manager.setHeadphoneProfile(tooMany);

    final allInvalid = HeadphoneProfile(
      id: 'bad',
      name: 'Bad',
      brand: 'B',
      model: 'M',
      category: 'Other',
      gains: const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      filters: const [
        EqFilter(frequency: 0, gain: 3),
        EqFilter(frequency: double.nan, gain: 3),
      ],
    );
    await manager.setHeadphoneProfile(allInvalid);
    expect(manager.isDisposed, isFalse);
  });

  test('degrade swallows a failing stage and still captures the baseline',
      () async {
    final manager = await newManager();
    await manager.setReverb(true);
    throwMethods.add('setReverbEnabled');
    await manager.degradeToEssentials();
    expect(manager.isDegradedForPower, isTrue);
  });

  test('restoreFromDegrade keeps a stage the user changed while degraded',
      () async {
    final manager = await newManager();
    await manager.setReverb(true);
    await manager.degradeToEssentials();
    expect(manager.isReverbEnabled, isFalse);

    // User re-enables reverb while degraded: the delta is captured.
    await manager.setReverb(true);
    expect(manager.isReverbEnabled, isTrue);

    await manager.restoreFromDegrade();
    expect(manager.isDegradedForPower, isFalse);
    // The user's choice wins over the pre-degrade snapshot.
    expect(manager.isReverbEnabled, isTrue);
  });

  test('full-state resync pushes every enabled stage', () async {
    final manager = await newManager();
    await manager.setEnabled(true);
    await manager.setVirtualizerEnabled(true);
    await manager.setVirtualizerStrength(0.4);
    await manager.setSpatializerEnabled(true);
    await manager.setCrossfeed(true);
    await manager.setLookaheadLimiter(true);
    await manager.setCompressorParams(ratio: 4.0);
    await manager.setReverb(true,
        preset: ReverbPreset.custom.wireValue, wetDry: 0.3);
    expect(await manager.loadCustomImpulseResponse(const [0.1, 0.2, 0.3]), isTrue);
    await manager.setStereoBalance(0.3);
    await manager.setMonoMix(true);
    await manager.setSaturation(true);
    await manager.setStereoWidth(true);
    await manager.setLoudnessContour(true);
    await manager.setSubCrossover(true);
    await manager.setDynamicEq(true);
    await manager.setMultibandCompressor(true);
    await manager.setDynamicBass(enabled: true);
    await manager.setViperDdc(true, profileName: 'P', coeffs: [1, 0, 0, 0, 0]);
    await manager.setArbitraryEq(true, eqString: 'GraphicEq: 20 0');
    await manager.setLiveProg(true, code: '@init');
    await manager.setLiveProgSlider(0, 0.5);
    await manager.setDither(true);
    await manager.setDspPreference('oem');

    calls.clear();
    overrides['verifyState'] = {'eqEnabled': false, 'preampDb': 5.0};
    await manager.resyncActiveEffects();
    expect(hasCall('setAudioSessionId'), isFalse); // resync never re-creates
    expect(hasCall('loadImpulseResponse'), isTrue);
    expect(hasCall('sendWarmupBuffer'), isTrue);
  });

  test('reapplyToSession ignores non-positive session ids', () async {
    final manager = await newManager();
    await manager.reapplyToSession(0);
    await manager.reapplyToSession(-4);
    expect(hasCall('setAudioSessionId'), isFalse);

    await manager.reapplyToSession(77);
    expect(manager.lastAppliedSessionId, 77);
    expect(hasCall('releaseEffects'), isTrue);
  });

  test('syncNativeLatency pushes resampler rates and swallows failures',
      () async {
    final manager = await newManager();
    await manager.setSincResampler(true);
    final frames = await manager.syncNativeLatency(48000, outputRate: 44100);
    expect(frames, 128);
    expect(hasCall('setSincResamplerRates'), isTrue);

    throwMethods.add('getPipelineLatencyFrames');
    expect(await manager.syncNativeLatency(48000), 0);
  });

  test('dsp preference normalises unknown values', () async {
    final manager = await newManager();
    await manager.setDspPreference('auto');
    expect(manager.dspPreference, 'auto');
    await manager.setDspPreference('nonsense');
    expect(manager.dspPreference, 'native');
  });

  test('band-gain flush writes per-band and the legacy mirror', () async {
    final manager = await newManager();
    await manager.setEnabled(true);
    await manager.setBandMode(32);
    manager.debugForceLegacyMirror = true;

    calls.clear();
    await manager.setBandGain(0, 5.0);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(hasCall('setNativeEqBand'), isTrue);
    expect(hasCall('setEqBandGains'), isTrue);

    // 10-band plan takes the dedicated branch.
    await manager.setBandMode(10);
    calls.clear();
    await manager.setBandGain(1, 4.0);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(hasCall('setEqBandGain'), isTrue);
  });

  test('dispose flushes pending band gains', () async {
    final manager = await newManager();
    await manager.setEnabled(true);
    await manager.setBandGain(0, 3.0);
    manager.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(manager.isDisposed, isTrue);
  });

  test('onAppPaused persists with and without a selected profile', () async {
    final manager = await newManager();
    manager.selectedHeadphoneProfile = const HeadphoneProfile(
      id: 'prof-1',
      name: 'Prof',
      brand: 'B',
      model: 'M',
      category: 'Other',
      gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    );
    await manager.onAppPaused();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsKeys.eqHeadphoneProfileId), 'prof-1');

    manager.selectedHeadphoneProfile = null;
    await manager.onAppPaused();
    expect(prefs.getString(PrefsKeys.eqHeadphoneProfileId), isNull);
  });

  test('seeded preferences restore the full effect state', () async {
    final thirtyTwo = List<double>.generate(32, (i) => 20.0 * (i + 1));
    SharedPreferences.setMockInitialValues({
      PrefsKeys.eqEnabled: true,
      PrefsKeys.eqBandCount: 32,
      PrefsKeys.eqCustom32Frequencies: json.encode(thirtyTwo),
      PrefsKeys.eqCustomFrequencies: '{bad json',
      PrefsKeys.eqGains: json.encode(List<double>.filled(10, 1.0)),
      PrefsKeys.eqPresetName: 'Studio',
      PrefsKeys.eqBassBoost: 0.4,
      PrefsKeys.eqVolumeBoost: 0.3,
      PrefsKeys.eqPreamp: 2.0,
      PrefsKeys.eqVirtualizerEnabled: true,
      PrefsKeys.eqVirtualizerStrength: 0.5,
      PrefsKeys.eqDynamicsEnabled: true,
      PrefsKeys.eqDynamicsPreset: 'studioPunch',
      PrefsKeys.eqSpatializerEnabled: true,
      PrefsKeys.crossfeedEnabled: true,
      PrefsKeys.crossfeedDelayUs: 400.0,
      PrefsKeys.crossfeedMode: 3,
      PrefsKeys.lookaheadLimiterEnabled: true,
      PrefsKeys.compressorRatio: 4.0,
      PrefsKeys.convolutionReverbEnabled: true,
      PrefsKeys.convolutionReverbPreset: ReverbPreset.custom.wireValue,
      PrefsKeys.customReverbIrPath: '/does/not/exist.wav',
      PrefsKeys.stereoBalance: 0.4,
      PrefsKeys.monoMix: true,
      PrefsKeys.saturationEnabled: true,
      PrefsKeys.stereoWidthEnabled: true,
      PrefsKeys.loudnessContourEnabled: true,
      PrefsKeys.subCrossoverEnabled: true,
      PrefsKeys.dynamicEqEnabled: true,
      PrefsKeys.dynamicEqBands: '{bad json',
      PrefsKeys.multibandCompressorEnabled: true,
      PrefsKeys.multibandCompressorBands: '{bad json',
      PrefsKeys.dynamicBassEnabled: true,
      PrefsKeys.viperDdcEnabled: true,
      PrefsKeys.viperDdcContent: 'coeff 1 0 0',
      PrefsKeys.arbitraryEqEnabled: true,
      PrefsKeys.arbitraryEqString: 'GraphicEq: 20 0',
      PrefsKeys.liveProgEnabled: true,
      PrefsKeys.liveProgCode: '@init',
      PrefsKeys.liveProgSliders: json.encode({'0': 0.5}),
      PrefsKeys.dspPreference: 'bogus',
      PrefsKeys.ditherEnabled: true,
      PrefsKeys.ditherTargetBitDepth: 7,
      PrefsKeys.eqHeadphoneProfileId: 'unknown-profile',
    });

    final manager = EqualizerManager();
    await manager.init();

    expect(manager.eqBandCount, 32);
    expect(manager.isEnabled, isTrue);
    expect(manager.isReverbEnabled, isTrue);
    // Custom reverb with an unreadable IR falls back to the default room.
    expect(manager.reverbPreset, ReverbPreset.studio.wireValue);
    expect(manager.dspPreference, 'native'); // bogus normalised
    expect(manager.ditherTargetBitDepth, 16); // 7 normalised
    expect(manager.customFrequencies, isNot(equals(thirtyTwo)));
    expect(manager.custom32Frequencies, thirtyTwo);
  });

  test('custom reverb restore keeps a valid IR and reads the WAV path',
      () async {
    // A missing path takes the failure branch; the manager must not throw.
    SharedPreferences.setMockInitialValues({
      PrefsKeys.convolutionReverbEnabled: true,
      PrefsKeys.convolutionReverbPreset: ReverbPreset.custom.wireValue,
      PrefsKeys.customReverbIrPath: '',
    });
    final manager = EqualizerManager();
    await manager.init();
    expect(manager.reverbPreset, ReverbPreset.studio.wireValue);
  });

  test('dynamic bass preset ignores custom values while active', () async {
    final manager = await newManager();
    await manager.setDynamicBass(
      enabled: true,
      preset: 1,
      xLow: 999,
      xHigh: 999,
      sideGainLow: 0.9,
    );
    expect(manager.dynamicBassPreset, 1);
    // Preset values override the ignored custom ones.
    expect(manager.dynamicBassXLow, isNot(999));
  });

  test('multiband compressor repairs inverted crossovers on both passes',
      () async {
    final manager = await newManager();
    await manager.setMultibandCompressor(true,
        f0: 5000.0, f1: 100.0, f2: 50.0);
    expect(manager.multibandCompressorF1,
        greaterThan(manager.multibandCompressorF0));
    expect(manager.multibandCompressorF2,
        greaterThan(manager.multibandCompressorF1));
  });

  test('dynamic EQ band guards reject out-of-range edits', () async {
    final manager = await newManager();
    await manager.setDynamicEq(true);
    await manager.setDynamicEqBand(99, const DynamicEqBandConfig());
    await manager.removeDynamicEqBand(99);
    expect(manager.dynamicEqBands, isNotEmpty);
  });

  test('setDither ignores unsupported bit depths and non-BT routes', () async {
    final manager = await newManager();
    manager.isBluetoothRoute = true;
    await manager.setDither(true, targetBitDepth: 7);
    expect(manager.ditherTargetBitDepth, 16);
    expect(manager.isDitherEnabled, isTrue);
  });

  test('saturation and stereo width optional parameters are honoured', () async {
    final manager = await newManager();
    await manager.setSaturation(true,
        drive: 0.6, mix: 0.4, tilt: 0.2, mode: 2, multiband: true);
    expect(manager.saturationDrive, closeTo(0.6, 1e-9));
    expect(manager.saturationMode, 2);
    await manager.setSaturation(true); // no optionals -> keeps prior values

    await manager.setStereoWidth(true,
        width: 1.5,
        multiband: true,
        lowWidth: 1.2,
        midWidth: 1.1,
        highWidth: 1.3,
        lowCrossoverHz: 300.0,
        highCrossoverHz: 4000.0);
    expect(manager.isStereoWidthEnabled, isTrue);
    await manager.setStereoWidth(true,
        lowCrossoverHz: 5000.0, highCrossoverHz: 100.0);
    expect(manager.stereoWidthHighCrossoverHz,
        greaterThan(manager.stereoWidthLowCrossoverHz));
  });

  test('sub crossover optional knobs and slope selection', () async {
    final manager = await newManager();
    await manager.setSubCrossover(true,
        cornerHz: 120.0, slopeDbPerOct: 6.0, gain: 0.5, bassMono: true,
        antiPop: false);
    expect(manager.subCrossoverSlopeDbPerOct, 12.0);
    expect(manager.subCrossoverBassMono, isTrue);
    expect(manager.subCrossoverAntiPop, isFalse);
  });
}
