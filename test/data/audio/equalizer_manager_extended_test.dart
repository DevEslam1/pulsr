// test/data/audio/equalizer_manager_extended_test.dart
//
// Extended coverage for [EqualizerManager]: exercises the DSP stage setters,
// band-plan switching, snapshot capture/restore, headphone profiles, A/B
// comparison, degrade/restore and session reattach under an Android
// target-platform override with the platform channel fully stubbed.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PulsrChannels.audioEffects);
  final calls = <MethodCall>[];

  void mockChannel() {
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
          return {'hasOemAudio': false, 'detectedEngines': <dynamic>[]};
        case 'loadLiveProgCode':
          return 'OK';
        case 'getTelemetry':
          return List<dynamic>.filled(17, 0.0);
        case 'getRtfGovernorStatus':
          return {'enabled': false};
        default:
          return true;
      }
    });
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    AudioEffectsChannel.lastPushedBypassDspForBitPerfect = null;
    mockChannel();
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

  const gainProfile = HeadphoneProfile(
    id: 'hp_gain',
    name: 'Gain Curve',
    brand: 'Brand',
    model: 'ModelX',
    category: 'Over-Ear',
    gains: [1, 2, 3, 4, 5, 4, 3, 2, 1, 0],
    bassBoost: 0.3,
    preampGain: -2.0,
  );

  const parametricProfile = HeadphoneProfile(
    id: 'hp_param',
    name: 'Parametric',
    brand: 'Brand',
    model: 'ModelP',
    category: 'In-Ear',
    gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    filters: [
      EqFilter(frequency: 100, gain: 3, q: 1.0),
      EqFilter(frequency: 5000, gain: -2, q: 2.0, filterType: EqFilterType.highShelf),
    ],
  );

  test('init, setBandMode switches plans and rejects unsupported counts',
      () async {
    final manager = await newManager();
    await manager.setBandMode(32);
    expect(manager.eqBandCount, 32);
    expect(manager.is32BandMode, isTrue);
    await manager.setBandMode(64);
    expect(manager.eqBandCount, 64);
    await manager.setBandMode(10);
    expect(manager.is32BandMode, isFalse);
    await manager.setBandMode(99);
    expect(manager.eqBandCount, 10);
    await manager.set32BandMode(true);
    expect(manager.eqBandCount, 32);
  });

  test('enable, preset, band gain, preamp and volume boost', () async {
    final manager = await newManager();
    await manager.setEnabled(true);
    expect(manager.isEnabled, isTrue);
    await manager.setEqualizerEnabled(false);
    expect(manager.isEnabled, isFalse);

    const preset = EqPreset(
      name: 'Bass',
      gains: [6, 5, 4, 3, 2, 1, 0, 0, 0, 0],
      bassBoost: 0.5,
    );
    await manager.applyPreset(preset);
    expect(manager.currentPreset.name, 'Bass');
    expect(manager.currentPreset.bassBoost, 0.5);

    await manager.setBandGain(0, 40.0);
    expect(manager.currentPreset.gains[0], 15.0);
    await manager.setBandGain(-1, 3.0); // out-of-range index is ignored
    await manager.setBandGain(0, double.nan); // non-finite ignored

    await manager.setPreamp(-5.0);
    expect(manager.preampDb, -5.0);

    await manager.setVolumeBoost(0.4);
    expect(manager.volumeBoost, closeTo(0.4, 0.001));
  });

  test('bass boost clamps and resetToFlat clears the curve', () async {
    final manager = await newManager();
    await manager.setBassBoost(2.0);
    expect(manager.currentPreset.bassBoost, 1.0);
    await manager.setBassBoost(double.nan);
    expect(manager.currentPreset.bassBoost, 0.0);
    await manager.setBandGain(2, 6.0);
    await manager.resetToFlat();
    expect(manager.currentPreset.gains.every((g) => g == 0.0), isTrue);
    expect(manager.preampDb, 0.0);
  });

  test('headphone profiles apply, reject invalid, and parametric fall back',
      () async {
    final manager = await newManager();
    await manager.applyHeadphoneProfile(gainProfile);
    expect(manager.selectedHeadphoneProfile, gainProfile);
    expect(manager.currentPreset.name, 'Gain Curve');

    await manager.applyHeadphoneProfile(parametricProfile);
    expect(manager.selectedHeadphoneProfile, parametricProfile);

    await manager.setHeadphoneProfile(null);
    expect(manager.selectedHeadphoneProfile, isNull);

    const emptyProfile = HeadphoneProfile(
      id: 'empty',
      name: 'Empty',
      brand: 'B',
      model: 'M',
      category: 'Other',
      gains: [],
    );
    await manager.setHeadphoneProfile(emptyProfile);
    expect(manager.selectedHeadphoneProfile, isNull);

    const nonFiniteProfile = HeadphoneProfile(
      id: 'nan',
      name: 'NaN',
      brand: 'B',
      model: 'M',
      category: 'Other',
      gains: [double.nan, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    );
    await manager.setHeadphoneProfile(nonFiniteProfile);
    expect(manager.selectedHeadphoneProfile, isNull);
  });

  test('virtualizer, dynamics, spatializer stage setters', () async {
    final manager = await newManager();
    await manager.setVirtualizerEnabled(true);
    expect(manager.isVirtualizerEnabled, isTrue);
    await manager.setVirtualizerStrength(0.6);
    expect(manager.virtualizerStrength, closeTo(0.6, 0.001));

    await manager.setDynamicsPreset(DynamicsPreset.studioPunch);
    expect(manager.isDynamicsEnabled, isTrue);
    expect(manager.dynamicsPreset, DynamicsPreset.studioPunch);
    await manager.toggleDynamicsBypass();
    expect(manager.isDynamicsBypassed, isTrue);
    await manager.toggleDynamicsBypass();
    expect(manager.isDynamicsBypassed, isFalse);

    await manager.setSpatializerEnabled(true);
    expect(manager.isSpatializerEnabled, isTrue);
  });

  test('crossfeed, limiter and compressor params', () async {
    final manager = await newManager();
    await manager.setCrossfeed(true,
        delayUs: 400.0, feedDb: -8.0, fcut: 800.0, mode: 3);
    expect(manager.isCrossfeedEnabled, isTrue);
    expect(manager.crossfeedMode, 3);
    await manager.setCrossfeedMode(1);
    expect(manager.crossfeedMode, 1);

    await manager.setLookaheadLimiter(true,
        thresholdDb: -1.0, releaseMs: 80.0, lookaheadMs: 5.0);
    expect(manager.isLimiterEnabled, isTrue);
    await manager.setCompressorParams(
        ratio: 4.0, attackMs: 20.0, makeupGainDb: 2.0);
    expect(manager.compressorRatio, 4.0);
  });

  test('reverb, custom impulse response and stereo/balance/sinc', () async {
    final manager = await newManager();
    await manager.setReverb(true,
        preset: 2, wetDry: 0.4, predelayMs: 20.0, damping: 0.6);
    expect(manager.isReverbEnabled, isTrue);
    await manager.setReverb(false);

    expect(await manager.loadCustomImpulseResponse(const []), isFalse);
    expect(
      await manager.loadCustomImpulseResponse(const [double.nan]),
      isFalse,
    );
    expect(
      await manager.loadCustomImpulseResponse(const [0.0, 0.5, 1.0]),
      isTrue,
    );

    await manager.setStereoBalance(0.5);
    expect(manager.stereoBalance, closeTo(0.5, 0.001));
    await manager.setMonoMix(true);
    expect(manager.monoMix, isTrue);
    await manager.setSincResampler(false);
    expect(manager.isSincResamplerEnabled, isFalse);
    expect(await manager.getPipelineLatencyFrames(), isA<int>());
    await manager.setBandSolo(0, true);
    await manager.setBandMute(0, true);
  });

  test('saturation, stereo width, loudness contour and sub crossover',
      () async {
    final manager = await newManager();
    await manager.setSaturation(true,
        drive: 0.5, mix: 0.4, tilt: 0.3, mode: 2, multiband: true);
    expect(manager.isSaturationEnabled, isTrue);
    expect(manager.saturationMultiband, isTrue);
    await manager.setSaturationMultiband(false);

    await manager.setStereoWidth(true,
        width: 1.6,
        multiband: true,
        lowWidth: 1.3,
        midWidth: 1.2,
        highWidth: 1.1,
        lowCrossoverHz: 200.0,
        highCrossoverHz: 3000.0);
    expect(manager.isStereoWidthEnabled, isTrue);
    // Inverted crossovers must be repaired.
    await manager.setStereoWidth(true,
        lowCrossoverHz: 5000.0, highCrossoverHz: 100.0);
    expect(manager.stereoWidthHighCrossoverHz,
        greaterThan(manager.stereoWidthLowCrossoverHz));

    await manager.setLoudnessContour(true, intensity: 0.7);
    expect(manager.isLoudnessContourEnabled, isTrue);
    await manager.updateLoudnessVolume(0.2);
    await manager.updateLoudnessVolume(0.9);

    await manager.setSubCrossover(true,
        cornerHz: 90.0, slopeDbPerOct: 12.0, gain: 0.5, bassMono: true);
    expect(manager.isSubCrossoverEnabled, isTrue);
    expect(manager.subCrossoverSlopeDbPerOct, 12.0);
  });

  test('dynamic EQ band editing and multiband compressor', () async {
    final manager = await newManager();
    await manager.setDynamicEq(true);
    expect(manager.isDynamicEqEnabled, isTrue);
    await manager.setDynamicEqBand(0, const DynamicEqBandConfig(frequency: 120));
    await manager.addDynamicEqBand();
    expect(manager.dynamicEqBands.length, greaterThan(1));
    await manager.setDynamicEqBand(99, const DynamicEqBandConfig());
    await manager.removeDynamicEqBand(0);
    await manager.removeDynamicEqBand(99);

    await manager.setMultibandCompressor(true,
        f0: 200.0, f1: 1200.0, f2: 6000.0);
    expect(manager.isMultibandCompressorEnabled, isTrue);
    // Inverted crossovers are repaired.
    await manager.setMultibandCompressor(true, f0: 5000.0, f1: 100.0, f2: 50.0);
    expect(manager.multibandCompressorF1,
        greaterThan(manager.multibandCompressorF0));
    expect(manager.multibandCompressorF2,
        greaterThan(manager.multibandCompressorF1));
    await manager.setMultibandCompressorBand(
      0,
      const MultibandCompressorBandConfig(
        thresholdDb: -22,
        ratio: 2.5,
        attackMs: 20,
        releaseMs: 120,
        kneeDb: 6,
        makeupGainDb: 0,
      ),
    );
    await manager.setMultibandCompressorBand(99,
        const MultibandCompressorBandConfig(
            thresholdDb: -20,
            ratio: 2,
            attackMs: 10,
            releaseMs: 100,
            kneeDb: 5,
            makeupGainDb: 0));
  });

  test('dynamic bass presets and custom values', () async {
    final manager = await newManager();
    await manager.setDynamicBass(enabled: true, preset: 1);
    expect(manager.isDynamicBassEnabled, isTrue);
    expect(manager.dynamicBassPreset, 1);
    await manager.setDynamicBass(
      enabled: true,
      strength: 1.5,
      xLow: 80,
      xHigh: 4000,
      yLow: 30,
      yHigh: 70,
      sideGainLow: 0.2,
      sideGainHigh: 0.4,
    );
    expect(manager.dynamicBassStrength, closeTo(1.5, 0.001));
  });

  test('DDC, arbitrary EQ and LiveProg stages', () async {
    final manager = await newManager();
    await manager.setViperDdc(true,
        profileName: 'HD650', coeffs: [1.0, 0.0, 0.0, 0.0, 0.0]);
    expect(manager.isViperDdcEnabled, isTrue);
    expect(manager.viperDdcProfileName, 'HD650');
    await manager.setViperDdc(false);

    await manager.setArbitraryEq(true,
        eqString: 'GraphicEq: 20 0; 1000 0', linearPhase: true);
    expect(manager.isArbitraryEqEnabled, isTrue);
    expect(manager.arbitraryEqLinearPhase, isTrue);

    await manager.setLiveProg(true, code: '@init\n@sample');
    expect(manager.isLiveProgEnabled, isTrue);
    await manager.setLiveProgSlider(1, 0.5);
    expect(manager.liveProgSliders[1], 0.5);
    await manager.setLiveProgSlider(99, 0.5); // invalid slider ignored
  });

  test('band-plan and EQ push helpers via reattach/resync', () async {
    final manager = await newManager();
    await manager.setEnabled(true);
    await manager.reapplyToSession(12);
    expect(manager.lastAppliedSessionId, 12);
    await manager.resyncActiveEffects();
    expect(calls.where((c) => c.method == 'setAudioSessionId'), isNotEmpty);
  });

  test('comparison slots, save/switch and A/B comparison', () async {
    final manager = await newManager();
    await manager.setBandGain(0, 5.0);
    manager.saveCurrentToSlot(ComparisonSlot.slotB);
    await manager.switchComparisonSlot(ComparisonSlot.slotB);
    expect(manager.activeComparisonSlot, ComparisonSlot.slotB);

    await manager.startAbComparison();
    expect(manager.isAbComparisonActive, isTrue);
    await manager.setBandGain(0, 8.0);
    await manager.endAbComparison();
    expect(manager.isAbComparisonActive, isFalse);
    // User edit made during A/B is preserved.
    expect(manager.currentPreset.gains[0], 8.0);
  });

  test('preset JSON export/import round trip and rejection', () async {
    final manager = await newManager();
    final json = manager.exportPresetToJson(null, true);
    expect(json, isNotEmpty);
    expect(await manager.importPresetFromJson(json), isTrue);
    expect(await manager.importPresetFromJson('{not valid json'), isFalse);
  });

  test('custom frequency layouts validate length and positivity', () async {
    final manager = await newManager();
    final ten = List<double>.generate(10, (i) => 30.0 * (i + 1));
    final thirtyTwo = List<double>.generate(32, (i) => 20.0 * (i + 1));
    final sixtyFour = List<double>.generate(64, (i) => 20.0 * (i + 1));

    await manager.setCustomFrequencies(ten);
    expect(manager.customFrequencies, ten);
    await manager.setCustomFrequencies(const [1.0, 2.0]);
    expect(manager.customFrequencies, ten);

    await manager.setCustom32Frequencies(thirtyTwo);
    expect(manager.custom32Frequencies, thirtyTwo);
    await manager.setCustom32Frequencies(const [1.0]);

    await manager.setCustom64Frequencies(sixtyFour);
    expect(manager.custom64Frequencies, sixtyFour);
    await manager.setCustom64Frequencies(const [1.0]);
  });

  test('dsp preference, dither and bit-perfect bypass', () async {
    final manager = await newManager();
    await manager.setDspPreference('oem');
    expect(manager.dspPreference, 'oem');
    await manager.setDspPreference('bogus');
    expect(manager.dspPreference, 'native');

    await manager.setDither(true, targetBitDepth: 24);
    expect(manager.isDitherEnabled, isTrue);
    expect(manager.ditherTargetBitDepth, 24);
    await manager.setDither(false, targetBitDepth: 7);
    expect(manager.ditherTargetBitDepth, 24);

    await manager.setBypassDspForBitPerfect(true, isDop: true);
    expect(manager.isBitPerfectBypass, isTrue);
    expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, isTrue);
    await manager.setBypassCompare(bypass: true, gainCompensationDb: -3.0);
  });

  test('snapshot capture and apply round-trip', () async {
    final manager = await newManager();
    await manager.setSaturation(true, drive: 0.6);
    await manager.setStereoWidth(true, width: 1.5);
    await manager.setViperDdc(true, profileName: 'P', coeffs: [1, 0, 0, 0, 0]);
    final snapshot = manager.captureEffectsState();
    expect(snapshot['saturationEnabled'], isTrue);

    await manager.setSaturation(false);
    await manager.applyEffectsState(snapshot);
    expect(manager.isSaturationEnabled, isTrue);
  });

  test('snapshot round-trips user-customized band-center frequencies',
      () async {
    final manager = await newManager();
    // Non-standard but valid 10-band centers (finite, > 0), distinct from the
    // default ISO layout so a replay on default centers would be observable.
    final custom = List<double>.generate(10, (i) => 25.0 * (i + 1));
    await manager.setCustomFrequencies(custom);
    expect(manager.customFrequencies, custom);
    await manager.setBandGain(2, 6.0); // make the curve non-flat

    final snapshot = manager.captureEffectsState();
    expect(snapshot['customFrequencies'], custom);

    // Move the live centers back to the default ISO layout, then recall: the
    // snapshot must put the captured centers back, not replay on ISO.
    await manager.setCustomFrequencies(
      List<double>.from(EqPreset.centerFrequencies),
    );
    expect(manager.customFrequencies, isNot(equals(custom)));

    await manager.applyEffectsState(snapshot);
    expect(manager.customFrequencies, custom);
    // In the 10-band plan the active curve is interpreted against these.
    expect(manager.activeFrequencies, custom);
  });

  test('snapshot without the customFrequencies key keeps current centers',
      () async {
    final manager = await newManager();
    final custom = List<double>.generate(10, (i) => 40.0 * (i + 1));
    await manager.setCustomFrequencies(custom);
    // Simulate an older snapshot that never captured the key.
    final legacy = manager.captureEffectsState()..remove('customFrequencies');
    await manager.applyEffectsState(legacy);
    expect(manager.customFrequencies, custom);
  });

  test('snapshot ignores an invalid customFrequencies payload', () async {
    final manager = await newManager();
    final custom = List<double>.generate(10, (i) => 55.0 * (i + 1));
    await manager.setCustomFrequencies(custom);
    final snapshot = manager.captureEffectsState();
    // Corrupt the captured layout (wrong length) — recall must not apply it.
    snapshot['customFrequencies'] = const [1.0, 2.0, 3.0];
    await manager.applyEffectsState(snapshot);
    expect(manager.customFrequencies, custom);
  });

  test('degrade to essentials and restore', () async {
    final manager = await newManager();
    await manager.setReverb(true);
    await manager.setCrossfeed(true);
    await manager.setSaturation(true);
    await manager.setStereoWidth(true);
    await manager.setLoudnessContour(true);
    await manager.setSubCrossover(true);
    await manager.setDynamicEq(true);
    await manager.setDynamicsPreset(DynamicsPreset.studioPunch);
    await manager.setLookaheadLimiter(true);
    await manager.setViperDdc(true, profileName: 'P', coeffs: [1, 0, 0, 0, 0]);
    await manager.setArbitraryEq(true, eqString: 'GraphicEq: 20 0');
    await manager.setLiveProg(true, code: '@init');

    await manager.degradeToEssentials();
    expect(manager.isDegradedForPower, isTrue);
    expect(manager.isReverbEnabled, isFalse);
    expect(manager.isSaturationEnabled, isFalse);

    await manager.restoreFromDegrade();
    expect(manager.isDegradedForPower, isFalse);
    expect(manager.isReverbEnabled, isTrue);
    expect(manager.isLiveProgEnabled, isTrue);
  });

  test('snapshot recall while degraded is deferred then applied', () async {
    final manager = await newManager();
    await manager.setSaturation(true, drive: 0.7);
    final snapshot = manager.captureEffectsState();
    await manager.setSaturation(false);

    await manager.degradeToEssentials();
    await manager.applyEffectsState(snapshot); // deferred
    expect(manager.isSaturationEnabled, isFalse);
    await manager.restoreFromDegrade();
    expect(manager.isSaturationEnabled, isTrue);
  });

  test('onAppPaused flushes pending preferences', () async {
    final manager = await newManager();
    await manager.setBandGain(0, 3.0);
    await manager.onAppPaused();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('eq_enabled'), isNotNull);
  });

  test('dispose marks the manager disposed', () async {
    final manager = await newManager();
    manager.dispose();
    expect(manager.isDisposed, isTrue);
  });
}
