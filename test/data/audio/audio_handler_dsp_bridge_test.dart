// test/data/audio/audio_handler_dsp_bridge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/comparison_slot.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';

import 'handler_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  PulsrAudioHandler? handler;

  setUp(() {
    JustAudioPlatform.instance = FakeJustAudioPlatform();
    installHandlerChannelStubs();
    repo = MockMusicRepository();
    stubDefaultRepository(repo);
    ytm = MockYtmService();
  });

  tearDown(() async {
    await handler?.dispose();
    handler = null;
    removeHandlerChannelStubs();
    JustAudioPlatform.instance = originalPlatform;
  });

  Future<PulsrAudioHandler> ready() async {
    final h = await buildTestHandler(repository: repo, ytmService: ytm);
    await h.loadQueue([localSong(1), localSong(2)], autoPlay: false);
    return h;
  }

  test('effect getters are readable', () async {
    handler = await ready();
    expect(handler!.isEqualizerEnabled, isA<bool>());
    expect(handler!.currentPreset, isA<EqPreset>());
    expect(handler!.isVirtualizerEnabled, isA<bool>());
    expect(handler!.virtualizerStrength, isA<double>());
    expect(handler!.isDynamicsEnabled, isA<bool>());
    expect(handler!.isDynamicsEffectivelyEnabled, isA<bool>());
    expect(handler!.isDynamicsBypassed, isA<bool>());
    expect(handler!.dynamicsPreset, isA<DynamicsPreset>());
    expect(handler!.selectedHeadphoneProfile, isNull);
    expect(handler!.crossfadeDuration, Duration.zero);
    expect(handler!.isAbComparisonActive, isA<bool>());
    expect(handler!.isSpatializerEnabled, isA<bool>());
    expect(handler!.isSpatializerSupported, isA<bool>());
    expect(handler!.isVirtualizerSupported, isA<bool>());
    expect(handler!.isDynamicsSupported, isA<bool>());
    expect(handler!.isBassBoostSupported, isA<bool>());
    expect(handler!.isVolumeBoostSupported, isA<bool>());
    expect(handler!.isHeadTrackerAvailable, isA<bool>());
    expect(handler!.volumeBoost, isA<double>());
    expect(handler!.preampDb, isA<double>());
    expect(handler!.is32BandMode, isA<bool>());
    expect(handler!.isCrossfeedEnabled, isA<bool>());
    expect(handler!.crossfeedDelayUs, isA<double>());
    expect(handler!.crossfeedFeedDb, isA<double>());
    expect(handler!.crossfeedMode, isA<int>());
    expect(handler!.isLimiterEnabled, isA<bool>());
    expect(handler!.limiterThresholdDb, isA<double>());
    expect(handler!.limiterReleaseMs, isA<double>());
    expect(handler!.isReverbEnabled, isA<bool>());
    expect(handler!.reverbPreset, isA<int>());
    expect(handler!.reverbWetDry, isA<double>());
    expect(handler!.stereoBalance, isA<double>());
    expect(handler!.monoMix, isA<bool>());
    expect(handler!.isSincResamplerEnabled, isA<bool>());
    expect(handler!.isDitherEnabled, isA<bool>());
    expect(handler!.ditherTargetBitDepth, isA<int>());
    expect(handler!.hasOemAudio, isA<bool>());
    expect(handler!.detectedOemEngines, isA<List<String>>());
    expect(handler!.isSaturationEnabled, isA<bool>());
    expect(handler!.saturationDrive, isA<double>());
    expect(handler!.saturationMix, isA<double>());
    expect(handler!.saturationTilt, isA<double>());
    expect(handler!.saturationMultiband, isA<bool>());
    expect(handler!.isStereoWidthEnabled, isA<bool>());
    expect(handler!.stereoWidth, isA<double>());
    expect(handler!.isLoudnessContourEnabled, isA<bool>());
    expect(handler!.loudnessContourIntensity, isA<double>());
    expect(handler!.isSubCrossoverEnabled, isA<bool>());
    expect(handler!.subCrossoverCornerHz, isA<double>());
    expect(handler!.subCrossoverSlopeDbPerOct, isA<double>());
    expect(handler!.subCrossoverGain, isA<double>());
    expect(handler!.isDynamicEqEnabled, isA<bool>());
    expect(handler!.dynamicEqBands, isA<List<DynamicEqBandConfig>>());
    expect(handler!.isViperDdcEnabled, isA<bool>());
    expect(handler!.viperDdcProfileName, isA<String>());
    expect(handler!.isArbitraryEqEnabled, isA<bool>());
    expect(handler!.arbitraryEqString, isA<String>());
    expect(handler!.arbitraryEqLinearPhase, isA<bool>());
    expect(handler!.isLiveProgEnabled, isA<bool>());
    expect(handler!.liveProgCode, isA<String>());
    expect(handler!.isDynamicBassEnabled, isA<bool>());
    expect(handler!.dynamicBassStrength, isA<double>());
    expect(handler!.dynamicBassPreset, isA<int>());
  });

  test('engine selection setters', () async {
    handler = await ready();
    handler!.setCrossfadeDuration(const Duration(seconds: 4));
    expect(handler!.crossfadeDuration, const Duration(seconds: 4));
    handler!.setGaplessEnabled(false);
    expect(handler!.isGaplessEnabled, isFalse);
    handler!.setGaplessEnabled(true);
    expect(handler!.isGaplessEnabled, isTrue);
  });

  test('equalizer setters and presets', () async {
    handler = await ready();
    await handler!.setEqualizerEnabled(true);
    await handler!.setBandGain(0, 3.0);
    await handler!.setPreamp(-2.0);
    await handler!.applyPreset(EqPreset.defaultPresets.first);
    await handler!.setBassBoost(0.5);
    await handler!.resetToFlat();
    await handler!.set32BandMode(true);
    await handler!.set32BandMode(false);
    await handler!.setCustomFrequencies(
        const [100, 200, 400, 800, 1600, 3200, 6400, 12800, 16000, 20000]);
    await handler!.setBandSolo(0, true);
    await handler!.setBandSolo(0, false);
    await handler!.setBandMute(1, true);
    await handler!.setBandMute(1, false);
  });

  test('A/B comparison controls', () async {
    handler = await ready();
    await handler!.startAbComparison();
    await handler!.switchComparisonSlot(ComparisonSlot.slotB);
    await handler!.endAbComparison();
    await handler!.setBypassCompare(bypass: true, gainCompensationDb: -3);
    await handler!.setBypassCompare(bypass: false);
  });

  test('virtualizer, dynamics and spatializer', () async {
    handler = await ready();
    await handler!.setVirtualizerEnabled(true);
    await handler!.setVirtualizerStrength(0.6);
    await handler!.setDynamicsPreset(DynamicsPreset.studioPunch);
    await handler!.toggleDynamicsBypass();
    await handler!.setSpatializerEnabled(true);
    await handler!.setSpatializerEnabled(false);
    await handler!.applyHeadphoneProfile(null);
    await handler!.setVolumeBoost(0.25);
  });

  test('preset export/import round trips', () async {
    handler = await ready();
    final json = handler!.exportPresetToJson();
    expect(json, isNotEmpty);
    expect(await handler!.importPresetFromJson(json), isTrue);
    expect(await handler!.importPresetFromJson('not-json'), isFalse);
  });

  test('native DSP stage setters', () async {
    handler = await ready();
    await handler!.setCrossfeed(true, delayUs: 350, feedDb: -9, mode: 1);
    await handler!.setCrossfeedMode(2);
    await handler!.setLookaheadLimiter(true,
        thresholdDb: -1, releaseMs: 50, lookaheadMs: 5);
    await handler!.setReverb(true, preset: 1, wetDry: 0.3);
    expect(await handler!.loadCustomImpulseResponse(const [1.0, 0.0, -1.0]),
        isA<bool>());
    await handler!.setStereoBalance(0.2);
    await handler!.setMonoMix(true);
    await handler!.setSincResampler(true);
    await handler!.setDither(true, targetBitDepth: 24);
    expect(await handler!.getPipelineLatencyFrames(), isA<int>());
  });

  test('phase-1 expansion stage setters', () async {
    handler = await ready();
    await handler!.setSaturation(true,
        drive: 0.4, mix: 0.6, tilt: 0.2, mode: 1, multiband: true);
    await handler!.setSaturationMultiband(false);
    await handler!.setStereoWidth(true,
        width: 1.4, multiband: true, lowWidth: 1.1, midWidth: 1.3);
    await handler!.setLoudnessContour(true, intensity: 0.5);
    await handler!.setSubCrossover(true,
        cornerHz: 90, slopeDbPerOct: 24, gain: 0.7);
    await handler!.setDynamicEq(true);
    await handler!.addDynamicEqBand();
    await handler!.removeDynamicEqBand(0);
    await handler!.setViperDdc(true, profileName: 'X', coeffs: const [1.0]);
    await handler!.setArbitraryEq(true,
        eqString: 'GraphicEQ: 100 0; 1000 0', linearPhase: true);
    await handler!.setLiveProg(true, code: 'result = input;');
    await handler!.setLiveProgSlider(0, 0.5);
    await handler!.setDynamicBass(enabled: true, strength: 1.2, preset: 0);
  });
}
