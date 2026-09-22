part of 'player_cubit.dart';

mixin PlayerDspControls on PulsrCubit<PlayerState> {
  PlayerDspController get dspController;

  Future<void> setEqualizerEnabled(bool enabled) =>
      dspController.setEqualizerEnabled(enabled);

  Future<void> applyPreset(EqPreset preset, {bool isPerSongRestore = false}) =>
      dspController.applyPreset(preset, isPerSongRestore: isPerSongRestore);

  Future<void> resetEqualizer() => dspController.resetEqualizer();

  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile,
          {bool isPerSongRestore = false}) =>
      dspController.applyHeadphoneProfile(profile,
          isPerSongRestore: isPerSongRestore);

  Future<void> setBandGain(int bandIndex, double gain) =>
      dspController.setBandGain(bandIndex, gain);

  Future<void> resetToFlat() => dspController.resetToFlat();

  Future<void> startAbComparison() => dspController.startAbComparison();

  Future<void> endAbComparison() => dspController.endAbComparison();

  Future<void> setBassBoost(double amount) =>
      dspController.setBassBoost(amount);

  Future<void> setBandMode(int count) => dspController.setBandMode(count);

  Future<void> switchComparisonSlot(ComparisonSlot slot) =>
      dspController.switchComparisonSlot(slot);

  String exportPresetToJson() => dspController.exportPresetToJson();

  Future<bool> importPresetFromJson(String jsonStr) =>
      dspController.importPresetFromJson(jsonStr);

  List<double> mergeRoomCorrectionWithHeadphoneCurve(
    List<double> roomGains, {
    double maxGainDb = 15.0,
  }) =>
      dspController.mergeRoomCorrectionWithHeadphoneCurve(roomGains,
          maxGainDb: maxGainDb);

  List<double> exportCorrectionImpulseResponse(
    List<double> gains, {
    List<double>? centers,
    int sampleRate = RoomCorrectionService.captureSampleRate,
    int taps = 127,
  }) =>
      dspController.exportCorrectionImpulseResponse(gains,
          centers: centers, sampleRate: sampleRate, taps: taps);

  Future<void> setVirtualizerEnabled(bool enabled) =>
      dspController.setVirtualizerEnabled(enabled);

  Future<void> setVirtualizerStrength(double strength) =>
      dspController.setVirtualizerStrength(strength);

  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) =>
      dspController.setDynamicsPreset(preset, enabled: enabled);

  Future<void> toggleDynamicsBypass() => dspController.toggleDynamicsBypass();

  Future<void> setDspEffectsEnabled(bool enabled) =>
      dspController.setDspEffectsEnabled(enabled);

  Future<void> setVolumeBoost(double value) =>
      dspController.setVolumeBoost(value);

  Future<void> setSpatializerEnabled(bool enabled) =>
      dspController.setSpatializerEnabled(enabled);

  Future<void> setCrossfeed(bool enabled,
          {double? delayUs, double? feedDb, int? mode}) =>
      dspController.setCrossfeed(enabled,
          delayUs: delayUs, feedDb: feedDb, mode: mode);

  Future<void> setCrossfeedMode(int mode) =>
      dspController.setCrossfeedMode(mode);

  Future<void> setLookaheadLimiter(bool enabled,
          {double? thresholdDb, double? releaseMs, double? lookaheadMs}) =>
      dspController.setLookaheadLimiter(enabled,
          thresholdDb: thresholdDb,
          releaseMs: releaseMs,
          lookaheadMs: lookaheadMs);

  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) =>
      dspController.setReverb(enabled, preset: preset, wetDry: wetDry);

  Future<void> setReverbPreset(int preset) =>
      dspController.setReverbPreset(preset);

  Future<bool> loadCustomImpulseResponse(List<double> irSamples) =>
      dspController.loadCustomImpulseResponse(irSamples);

  Future<void> pickAndLoadCustomIrFile() =>
      dspController.pickAndLoadCustomIrFile();

  Future<void> setStereoBalance(double balance) =>
      dspController.setStereoBalance(balance);

  Future<void> setMonoMix(bool mono) => dspController.setMonoMix(mono);

  Future<void> setSincResampler(bool enabled) =>
      dspController.setSincResampler(enabled);

  Future<void> setDither(bool enabled, {int? targetBitDepth}) =>
      dspController.setDither(enabled, targetBitDepth: targetBitDepth);

  Future<void> setSaturation(bool enabled,
          {double? drive,
          double? mix,
          double? tilt,
          int? mode,
          bool? multiband}) =>
      dspController.setSaturation(enabled,
          drive: drive, mix: mix, tilt: tilt, mode: mode, multiband: multiband);

  Future<void> setSaturationMultiband(bool multiband) =>
      dspController.setSaturationMultiband(multiband);

  Future<void> setStereoWidth(bool enabled,
          {double? width,
          bool? multiband,
          double? lowWidth,
          double? midWidth,
          double? highWidth,
          double? lowCrossoverHz,
          double? highCrossoverHz}) =>
      dspController.setStereoWidth(enabled,
          width: width,
          multiband: multiband,
          lowWidth: lowWidth,
          midWidth: midWidth,
          highWidth: highWidth,
          lowCrossoverHz: lowCrossoverHz,
          highCrossoverHz: highCrossoverHz);

  Future<void> setLoudnessContour(bool enabled, {double? intensity}) =>
      dspController.setLoudnessContour(enabled, intensity: intensity);

  Future<void> setSubCrossover(bool enabled,
          {double? cornerHz,
          double? slopeDbPerOct,
          double? gain,
          bool? bassMono,
          bool? antiPop}) =>
      dspController.setSubCrossover(enabled,
          cornerHz: cornerHz,
          slopeDbPerOct: slopeDbPerOct,
          gain: gain,
          bassMono: bassMono,
          antiPop: antiPop);

  Future<void> setDynamicEq(bool enabled) =>
      dspController.setDynamicEq(enabled);

  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) =>
      dspController.setDynamicEqBand(index, band);

  Future<void> addDynamicEqBand() => dspController.addDynamicEqBand();

  Future<void> removeDynamicEqBand(int index) =>
      dspController.removeDynamicEqBand(index);

  Future<void> setViperDdcEnabled(bool enabled,
          {String? profileName, List<double>? coeffs}) =>
      dspController.setViperDdcEnabled(enabled,
          profileName: profileName, coeffs: coeffs);

  bool get isArbitraryEqLinearPhase => dspController.isArbitraryEqLinearPhase;

  Future<void> setArbitraryEqEnabled(bool enabled,
          {String? eqString, bool? linearPhase}) =>
      dspController.setArbitraryEqEnabled(enabled,
          eqString: eqString, linearPhase: linearPhase);

  Future<void> setLiveProgEnabled(bool enabled, {String? code}) =>
      dspController.setLiveProgEnabled(enabled, code: code);

  Future<void> setLiveProgSlider(int sliderIndex, double value) =>
      dspController.setLiveProgSlider(sliderIndex, value);

  Future<void> setDynamicBass(
    bool enabled, {
    double? strength,
    int? preset,
    int? xLow,
    int? xHigh,
    int? yLow,
    int? yHigh,
    double? sideGainLow,
    double? sideGainHigh,
  }) =>
      dspController.setDynamicBass(
        enabled,
        strength: strength,
        preset: preset,
        xLow: xLow,
        xHigh: xHigh,
        yLow: yLow,
        yHigh: yHigh,
        sideGainLow: sideGainLow,
        sideGainHigh: sideGainHigh,
      );

  Future<bool> applyProfile(SettingsProfile profile, {bool manual = false}) =>
      dspController.applyProfile(profile, manual: manual);
}
