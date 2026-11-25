// Regression test for P0-1.6: a failed profile apply must roll back EVERY DSP
// stage the engine owns, not just the handful the old rollback knew about.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/services/settings_profiles_service.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/features/player/cubit/controllers/player_dsp_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

import '../player_test_support.dart';

/// Records the engine calls the rollback pushes and fails the first
/// `setEqualizerEnabled`, which is what drives `applyProfile` into its
/// catch/rollback path.
class _ChainAudioHandler extends RecordingAudioHandler {
  final List<String> chain = <String>[];
  bool failEqualizerEnable = true;

  @override
  Future<void> setEqualizerEnabled(bool enabled) async {
    chain.add('setEqualizerEnabled');
    if (failEqualizerEnable) throw StateError('native EQ rejected');
  }

  @override
  Future<void> applyPreset(EqPreset preset) async => chain.add('applyPreset');

  @override
  Future<void> setPreamp(double preampDb) async => chain.add('setPreamp');

  @override
  Future<void> setVolumeBoost(double value) async =>
      chain.add('setVolumeBoost');

  @override
  Future<void> setBassBoost(double amount) async => chain.add('setBassBoost');

  @override
  Future<void> setSaturation(bool enabled,
          {double? drive,
          double? mix,
          double? tilt,
          int? mode,
          bool? multiband}) async =>
      chain.add('setSaturation');

  @override
  Future<void> setStereoWidth(bool enabled,
          {double? width,
          bool? multiband,
          double? lowWidth,
          double? midWidth,
          double? highWidth,
          double? lowCrossoverHz,
          double? highCrossoverHz}) async =>
      chain.add('setStereoWidth');

  @override
  Future<void> setLoudnessContour(bool enabled, {double? intensity}) async =>
      chain.add('setLoudnessContour');

  @override
  Future<void> setSubCrossover(bool enabled,
          {double? cornerHz,
          double? slopeDbPerOct,
          double? gain,
          bool? bassMono,
          bool? antiPop}) async =>
      chain.add('setSubCrossover');

  @override
  Future<void> setDynamicEq(bool enabled) async => chain.add('setDynamicEq');

  @override
  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) async =>
      chain.add('setDynamicEqBand');

  @override
  Future<void> setSpatializerEnabled(bool enabled) async {
    chain.add('setSpatializerEnabled');
    if (failSpatializer) throw StateError('spatializer unavailable');
  }

  /// When true, the matching rollback step throws at the engine boundary.
  bool failSpatializer = false;
  bool failLimiter = false;

  @override
  Future<void> setVirtualizerEnabled(bool enabled) async =>
      chain.add('setVirtualizerEnabled');

  @override
  Future<void> setVirtualizerStrength(double strength) async =>
      chain.add('setVirtualizerStrength');

  @override
  Future<void> setDynamicsPreset(DynamicsPreset preset,
          {bool? enabled}) async =>
      chain.add('setDynamicsPreset');

  @override
  Future<void> setLookaheadLimiter(bool enabled,
      {double? thresholdDb, double? releaseMs, double? lookaheadMs}) async {
    chain.add('setLookaheadLimiter');
    if (failLimiter) throw StateError('limiter unavailable');
  }

  /// When true, [setReverb] throws at the engine boundary.
  bool failReverb = false;

  @override
  Future<void> setReverb(bool enabled,
      {int? preset,
      double? wetDry,
      double? predelayMs,
      double? damping}) async {
    chain.add('setReverb');
    if (failReverb) throw StateError('reverb unavailable');
  }

  @override
  Future<void> setCrossfeed(bool enabled,
          {double? delayUs,
          double? feedDb,
          double? fcut,
          int? mode,
          bool? preferenceEnabled}) async =>
      chain.add('setCrossfeed');

  @override
  Future<void> setStereoBalance(double balance) async =>
      chain.add('setStereoBalance');

  @override
  Future<void> setMonoMix(bool mono) async => chain.add('setMonoMix');

  @override
  Future<void> setSincResampler(bool enabled) async =>
      chain.add('setSincResampler');

  @override
  Future<void> setDither(bool enabled, {int? targetBitDepth}) async =>
      chain.add('setDither');

  @override
  Future<void> setDynamicBass(
          {required bool enabled,
          double? strength,
          int? preset,
          int? xLow,
          int? xHigh,
          int? yLow,
          int? yHigh,
          double? sideGainLow,
          double? sideGainHigh}) async =>
      chain.add('setDynamicBass');

  @override
  Future<void> setViperDdc(bool enabled,
          {String? profileName,
          List<double>? coeffs,
          String? ddcContent}) async =>
      chain.add('setViperDdc');

  @override
  Future<void> setArbitraryEq(bool enabled,
          {String? eqString, bool? linearPhase}) async =>
      chain.add('setArbitraryEq');

  @override
  Future<void> setLiveProg(bool enabled, {String? code}) async =>
      chain.add('setLiveProg');

  @override
  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) async =>
      chain.add('applyHeadphoneProfile');
}

class _HrtfSpyAudioHandler extends RecordingAudioHandler {
  final List<bool> hrtfEnabledCalls = <bool>[];

  @override
  Future<void> setHrtfBinaural(
    bool enabled, {
    double? azimuth,
    double? elevation,
    String? sofaPath,
    bool? preferenceEnabled,
  }) async {
    hrtfEnabledCalls.add(enabled);
    await super.setHrtfBinaural(
      enabled,
      azimuth: azimuth,
      elevation: elevation,
      sofaPath: sofaPath,
      preferenceEnabled: preferenceEnabled,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a mid-apply failure re-pushes the complete pre-apply chain', () async {
    final handler = _ChainAudioHandler();
    final settings = MockSettingsCubit();
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.setCrossfade(any())).thenAnswer((_) async {});
    when(() => settings.setBitPerfectOutput(any())).thenAnswer((_) async {});

    var state = PlayerState(
      dsp: const DspSlice(
        isEqEnabled: true,
        preampDb: -3.5,
        effectiveBassBoost: 0.4,
        isSpatializerEnabled: true,
        isVirtualizerEnabled: true,
        virtualizerStrength: 0.42,
        isDynamicsEnabled: true,
        dynamicsPreset: DynamicsPreset.studioPunch,
        isLimiterEnabled: true,
        limiterThresholdDb: -1.5,
        limiterReleaseMs: 90,
        isReverbEnabled: true,
        reverbPreset: 2,
        reverbWetDry: 0.33,
        isCrossfeedEnabled: true,
        crossfeedMode: 1,
        stereoBalance: -0.25,
        monoMix: true,
        isSincResamplerEnabled: false,
        isDitherEnabled: true,
        ditherTargetBitDepth: 24,
        isSaturationEnabled: true,
        isStereoWidthEnabled: true,
        isLoudnessContourEnabled: true,
        isSubCrossoverEnabled: true,
        isMultibandCompressorEnabled: true,
        isDynamicEqEnabled: true,
        dynamicEqBands: [DynamicEqBandConfig()],
        isViperDdcEnabled: true,
        viperDdcProfileName: 'hp.vdc',
        isArbitraryEqEnabled: true,
        arbitraryEqString: '1 2 3',
        isLiveProgEnabled: true,
        liveProgCode: 'slider1=0.5;',
        isDynamicBassEnabled: true,
        dynamicBassStrength: 1.4,
        dynamicBassPreset: 2,
      ),
    );

    final controller = PlayerDspController(
      audioHandler: handler,
      settingsCubit: settings,
      getState: () => state,
      emit: (s) => state = s,
      syncAudioEffects: ({bool force = false}) {},
      isClosed: () => false,
    );
    addTearDown(controller.dispose);

    final applied = await controller.applyProfile(
      const SettingsProfile(id: 'p1', name: 'Bright', type: ProfileType.custom),
    );

    expect(applied, isFalse, reason: 'the failing EQ enable must abort apply');

    // The apply phase pushes whatever the profile stages request (and stops at
    // its own failure). The rollback begins after the apply phase's headphone
    // step and must push every engine setter in table order.
    final rollback = handler.chain
        .sublist(handler.chain.indexOf('applyHeadphoneProfile') + 1);
    const expectedRollback = <String>[
      'setEqualizerEnabled',
      'applyPreset',
      'setPreamp',
      'setVolumeBoost',
      'setBassBoost',
      'setSaturation',
      'setStereoWidth',
      'setLoudnessContour',
      'setSubCrossover',
      'setDynamicEq',
      'setDynamicEqBand',
      'setSpatializerEnabled',
      'setVirtualizerEnabled',
      'setVirtualizerStrength',
      'setDynamicsPreset',
      'setLookaheadLimiter',
      'setReverb',
      'setCrossfeed',
      'setStereoBalance',
      'setMonoMix',
      'setSincResampler',
      'setDither',
      'setDynamicBass',
      'setViperDdc',
      'setArbitraryEq',
      'setLiveProg',
      'applyHeadphoneProfile',
    ];
    expect(rollback, expectedRollback,
        reason: 'the rollback must push the complete chain in table order');

    // The Dart DSP slice is restored wholesale.
    expect(state.dsp.isLimiterEnabled, isTrue);
    expect(state.dsp.limiterThresholdDb, -1.5);
    expect(state.dsp.monoMix, isTrue);
    expect(state.dsp.isViperDdcEnabled, isTrue);
    expect(state.dsp.preampDb, -3.5);
  });

  test('one dead rollback step does not stop the rest', () async {
    final handler = _ChainAudioHandler();
    final settings = MockSettingsCubit();
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.setCrossfade(any())).thenAnswer((_) async {});
    when(() => settings.setBitPerfectOutput(any())).thenAnswer((_) async {});
    // Three different stages fail at the engine boundary; none may abort the
    // rest of the rollback or reorder it.
    handler.failReverb = true;
    handler.failLimiter = true;
    handler.failSpatializer = true;

    var state = PlayerState(
      dsp: const DspSlice(
        isEqEnabled: true,
        isReverbEnabled: true,
        isDynamicBassEnabled: true,
        isLiveProgEnabled: true,
      ),
    );

    final controller = PlayerDspController(
      audioHandler: handler,
      settingsCubit: settings,
      getState: () => state,
      emit: (s) => state = s,
      syncAudioEffects: ({bool force = false}) {},
      isClosed: () => false,
    );
    addTearDown(controller.dispose);

    await controller.applyProfile(
      const SettingsProfile(id: 'p2', name: 'Warm', type: ProfileType.custom),
    );

    expect(handler.chain, contains('setDynamicBass'),
        reason: 'a failing stage must not abort later restore steps');
    expect(handler.chain, contains('setLiveProg'));
    expect(handler.chain, contains('applyHeadphoneProfile'));
    final rollback = handler.chain
        .sublist(handler.chain.indexOf('applyHeadphoneProfile') + 1);
    expect(rollback.indexOf('setReverb'),
        lessThan(rollback.indexOf('setDynamicBass')),
        reason: 'isolation preserves the table order');
    expect(rollback.indexOf('setDynamicBass'),
        lessThan(rollback.indexOf('applyHeadphoneProfile')));
  });

  test('applyProfile disables HRTF when applying a profile', () async {
    final handler = _HrtfSpyAudioHandler();
    final settings = MockSettingsCubit();
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.setCrossfade(any())).thenAnswer((_) async {});
    when(() => settings.setBitPerfectOutput(any())).thenAnswer((_) async {});

    var state = PlayerState(
      dsp: const DspSlice(
        isHrtfEnabled: true,
        hrtfAzimuth: 45.0,
        hrtfElevation: 10.0,
        hrtfSofaPath: '/custom/room.sofa',
      ),
    );

    final controller = PlayerDspController(
      audioHandler: handler,
      settingsCubit: settings,
      getState: () => state,
      emit: (s) => state = s,
      syncAudioEffects: ({bool force = false}) {},
      isClosed: () => false,
    );
    addTearDown(controller.dispose);

    final applied = await controller.applyProfile(
      const SettingsProfile(
        id: 'p_hrtf_reset',
        name: 'Clean',
        type: ProfileType.custom,
      ),
    );

    expect(applied, isTrue);
    expect(state.dsp.isHrtfEnabled, isFalse);
    expect(handler.hrtfEnabledCalls, <bool>[false]);
  });
}
