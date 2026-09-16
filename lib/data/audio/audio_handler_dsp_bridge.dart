// ignore_for_file: unused_element
part of 'audio_handler.dart';

mixin PulsrAudioDspBridge on BaseAudioHandler {
  bool get isEqualizerEnabled => _equalizerManager.isEnabled;

  EqPreset get currentPreset => _equalizerManager.currentPreset;

  bool get isVirtualizerEnabled => _equalizerManager.isVirtualizerEnabled;

  double get virtualizerStrength => _equalizerManager.virtualizerStrength;

  bool get isDynamicsEnabled => _equalizerManager.isDynamicsEnabled;

  bool get isDynamicsEffectivelyEnabled =>
      _equalizerManager.isDynamicsEffectivelyEnabled;

  bool get isDynamicsBypassed => _equalizerManager.isDynamicsBypassed;

  DynamicsPreset get dynamicsPreset => _equalizerManager.dynamicsPreset;

  HeadphoneProfile? get selectedHeadphoneProfile =>
      _equalizerManager.selectedHeadphoneProfile;

  Duration get crossfadeDuration => _crossfadeManager.duration;

  void setCrossfadeDuration(Duration duration) {
    final wasGapless = _gaplessMode;
    _crossfadeManager.duration = duration;
    final isGapless = _gaplessMode;
    if (wasGapless != isGapless) {
      _scheduleEngineSwitch(toGapless: isGapless);
    }
  }

  /// Applies the persisted gapless toggle. Switching it (queue non-empty)
  /// re-selects the gapless playlist engine or the per-track player.
  void setGaplessEnabled(bool enabled) {
    if (_gaplessEnabled == enabled) return;
    final wasGapless = _gaplessMode;
    _gaplessEnabled = enabled;
    final isGapless = _gaplessMode;
    if (wasGapless != isGapless) {
      _scheduleEngineSwitch(toGapless: isGapless);
    }
  }

  void _scheduleEngineSwitch({required bool toGapless}) {
    if (_songs.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _songs.length) {
      return;
    }
    // Debounce slider drags: rapid toggles previously spawned concurrent
    // _switchPlaybackEngine calls that interleaved.
    _crossfadeSwitchDebounce?.cancel();
    _crossfadeSwitchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_switchPlaybackEngine(toGapless: toGapless));
    });
  }

  Future<void> _switchPlaybackEngine({required bool toGapless}) async {
    final generation = ++_engineSwitchGeneration;
    final resumePos = _activePlayer.position;
    final wasPlaying = _activePlayer.playing;
    try {
      if (toGapless) {
        await _loadGaplessQueue(
            initialPosition: resumePos, preload: wasPlaying);
      } else {
        _gaplessLoaded = false;
        if (generation != _engineSwitchGeneration) return;
        if (wasPlaying) {
          await playSongAt(_currentIndex, initialPosition: resumePos);
        } else {
          if (_currentIndex >= 0 && _currentIndex < _songs.length) {
            final song = _songs[_currentIndex];
            final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
            final item = PulsrAudioHandler._songToMediaItem(song, artUri);
            mediaItem.add(item);
            if (song.source != SongSource.youtube) {
              await _activePlayer.setAudioSource(
                _createAudioSource(song, item),
                initialPosition: resumePos,
                preload: false,
              );
            } else {
              _pendingLazyPosition = resumePos;
            }
            _broadcastState(_activePlayer.playbackEvent);
          }
        }
      }
      if (generation != _engineSwitchGeneration) return;
    } catch (e, st) {
      _pendingLazyPosition = null;
      ErrorLogger.log('Error switching playback engine on crossfade toggle',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) =>
      _equalizerManager.setEqualizerEnabled(enabled);

  Future<void> setBandGain(int bandIndex, double gain) =>
      _equalizerManager.setBandGain(bandIndex, gain);

  Future<void> resetToFlat() => _equalizerManager.resetToFlat();

  Future<void> startAbComparison() => _equalizerManager.startAbComparison();

  Future<void> endAbComparison() => _equalizerManager.endAbComparison();

  bool get isAbComparisonActive => _equalizerManager.isAbComparisonActive;

  Future<void> setBassBoost(double value) =>
      _equalizerManager.setBassBoost(value);

  Future<void> applyPreset(EqPreset preset) =>
      _equalizerManager.applyPreset(preset);

  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) =>
      _equalizerManager.applyHeadphoneProfile(profile);

  Future<void> setVirtualizerEnabled(bool enabled) =>
      _equalizerManager.setVirtualizerEnabled(enabled);

  Future<void> setVirtualizerStrength(double strength) =>
      _equalizerManager.setVirtualizerStrength(strength);

  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) =>
      _equalizerManager.setDynamicsPreset(preset, enabled: enabled);

  Future<void> toggleDynamicsBypass() =>
      _equalizerManager.toggleDynamicsBypass();

  bool get isSpatializerEnabled => _equalizerManager.isSpatializerEnabled;

  bool get isSpatializerSupported => _equalizerManager.isSpatializerSupported;

  bool get isVirtualizerSupported => _equalizerManager.isVirtualizerSupported;

  bool get isDynamicsSupported => _equalizerManager.isDynamicsSupported;

  bool get isBassBoostSupported => _equalizerManager.isBassBoostSupported;

  bool get isVolumeBoostSupported => _equalizerManager.isVolumeBoostSupported;

  bool get isHeadTrackerAvailable => _equalizerManager.isHeadTrackerAvailable;

  Future<void> setSpatializerEnabled(bool enabled) =>
      _equalizerManager.setSpatializerEnabled(enabled);

  double get volumeBoost => _equalizerManager.volumeBoost;

  Future<void> setVolumeBoost(double value) =>
      _equalizerManager.setVolumeBoost(value);

  Future<void> setCustomFrequencies(List<double> frequencies) =>
      _equalizerManager.setCustomFrequencies(frequencies);

  bool get is32BandMode => _equalizerManager.is32BandMode;

  Future<void> set32BandMode(bool enabled) =>
      _equalizerManager.set32BandMode(enabled);

  Future<void> switchComparisonSlot(ComparisonSlot slot) =>
      _equalizerManager.switchComparisonSlot(slot);

  String exportPresetToJson([EqPreset? preset]) =>
      _equalizerManager.exportPresetToJson(preset);

  Future<bool> importPresetFromJson(String jsonString) =>
      _equalizerManager.importPresetFromJson(jsonString);

  // Native DSP features
  bool get isCrossfeedEnabled => _equalizerManager.isCrossfeedEnabled;

  double get crossfeedDelayUs => _equalizerManager.crossfeedDelayUs;

  double get crossfeedFeedDb => _equalizerManager.crossfeedFeedDb;

  int get crossfeedMode => _equalizerManager.crossfeedMode;

  Future<void> setCrossfeed(bool enabled, {double? delayUs, double? feedDb, int? mode}) =>
      _equalizerManager.setCrossfeed(enabled, delayUs: delayUs, feedDb: feedDb, mode: mode);

  Future<void> setCrossfeedMode(int mode) =>
      _equalizerManager.setCrossfeedMode(mode);

  bool get isLimiterEnabled => _equalizerManager.isLimiterEnabled;

  double get limiterThresholdDb => _equalizerManager.limiterThresholdDb;

  double get limiterReleaseMs => _equalizerManager.limiterReleaseMs;

  Future<void> setLookaheadLimiter(bool enabled,
          {double? thresholdDb, double? releaseMs, double? lookaheadMs}) =>
      _equalizerManager.setLookaheadLimiter(enabled,
          thresholdDb: thresholdDb,
          releaseMs: releaseMs,
          lookaheadMs: lookaheadMs);

  bool get isReverbEnabled => _equalizerManager.isReverbEnabled;

  int get reverbPreset => _equalizerManager.reverbPreset;

  double get reverbWetDry => _equalizerManager.reverbWetDry;

  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) =>
      _equalizerManager.setReverb(enabled, preset: preset, wetDry: wetDry);

  Future<bool> loadCustomImpulseResponse(List<double> irSamples) =>
      _equalizerManager.loadCustomImpulseResponse(irSamples);

  double get stereoBalance => _equalizerManager.stereoBalance;

  bool get monoMix => _equalizerManager.monoMix;

  Future<void> setStereoBalance(double balance) =>
      _equalizerManager.setStereoBalance(balance);

  Future<void> setMonoMix(bool mono) => _equalizerManager.setMonoMix(mono);

  bool get isSincResamplerEnabled => _equalizerManager.isSincResamplerEnabled;

  Future<void> setSincResampler(bool enabled) =>
      _equalizerManager.setSincResampler(enabled);

  bool get isDitherEnabled => _equalizerManager.isDitherEnabled;

  int get ditherTargetBitDepth => _equalizerManager.ditherTargetBitDepth;

  Future<void> setDither(bool enabled, {int? targetBitDepth}) =>
      _equalizerManager.setDither(enabled, targetBitDepth: targetBitDepth);

  Future<int> getPipelineLatencyFrames() =>
      _equalizerManager.getPipelineLatencyFrames();

  Future<void> setBandSolo(int index, bool solo) =>
      _equalizerManager.setBandSolo(index, solo);

  Future<void> setBandMute(int index, bool mute) =>
      _equalizerManager.setBandMute(index, mute);

  bool get hasOemAudio => _equalizerManager.hasOemAudio;

  List<String> get detectedOemEngines => _equalizerManager.detectedOemEngines;

  bool get isSaturationEnabled => _equalizerManager.isSaturationEnabled;

  double get saturationDrive => _equalizerManager.saturationDrive;

  double get saturationMix => _equalizerManager.saturationMix;

  double get saturationTilt => _equalizerManager.saturationTilt;

  bool get saturationMultiband => _equalizerManager.saturationMultiband;

  Future<void> setSaturation(
    bool enabled, {
    double? drive,
    double? mix,
    double? tilt,
    int? mode,
    bool? multiband,
  }) =>
      _equalizerManager.setSaturation(
        enabled,
        drive: drive,
        mix: mix,
        tilt: tilt,
        mode: mode,
        multiband: multiband,
      );

  Future<void> setSaturationMultiband(bool multiband) =>
      _equalizerManager.setSaturationMultiband(multiband);

  bool get isStereoWidthEnabled => _equalizerManager.isStereoWidthEnabled;

  double get stereoWidth => _equalizerManager.stereoWidth;

  Future<void> setStereoWidth(
    bool enabled, {
    double? width,
    bool? multiband,
    double? lowWidth,
    double? midWidth,
    double? highWidth,
    double? lowCrossoverHz,
    double? highCrossoverHz,
  }) =>
      _equalizerManager.setStereoWidth(
        enabled,
        width: width,
        multiband: multiband,
        lowWidth: lowWidth,
        midWidth: midWidth,
        highWidth: highWidth,
        lowCrossoverHz: lowCrossoverHz,
        highCrossoverHz: highCrossoverHz,
      );

  bool get isLoudnessContourEnabled =>
      _equalizerManager.isLoudnessContourEnabled;

  double get loudnessContourIntensity =>
      _equalizerManager.loudnessContourIntensity;

  Future<void> setLoudnessContour(bool enabled, {double? intensity}) =>
      _equalizerManager.setLoudnessContour(enabled, intensity: intensity);

  bool get isSubCrossoverEnabled => _equalizerManager.isSubCrossoverEnabled;

  double get subCrossoverCornerHz => _equalizerManager.subCrossoverCornerHz;

  double get subCrossoverSlopeDbPerOct =>
      _equalizerManager.subCrossoverSlopeDbPerOct;

  double get subCrossoverGain => _equalizerManager.subCrossoverGain;

  Future<void> setSubCrossover(
    bool enabled, {
    double? cornerHz,
    double? slopeDbPerOct,
    double? gain,
    bool? bassMono,
    bool? antiPop,
  }) =>
      _equalizerManager.setSubCrossover(
        enabled,
        cornerHz: cornerHz,
        slopeDbPerOct: slopeDbPerOct,
        gain: gain,
        bassMono: bassMono,
        antiPop: antiPop,
      );

  bool get isDynamicEqEnabled => _equalizerManager.isDynamicEqEnabled;

  List<DynamicEqBandConfig> get dynamicEqBands =>
      _equalizerManager.dynamicEqBands;

  Future<void> setDynamicEq(bool enabled) =>
      _equalizerManager.setDynamicEq(enabled);

  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) =>
      _equalizerManager.setDynamicEqBand(index, band);

  Future<void> addDynamicEqBand() => _equalizerManager.addDynamicEqBand();

  Future<void> removeDynamicEqBand(int index) => _equalizerManager.removeDynamicEqBand(index);

  bool get isViperDdcEnabled => _equalizerManager.isViperDdcEnabled;

  String get viperDdcProfileName => _equalizerManager.viperDdcProfileName;

  Future<void> setViperDdc(bool enabled,
          {String? profileName, List<double>? coeffs, String? ddcContent}) =>
      _equalizerManager.setViperDdc(enabled,
          profileName: profileName, coeffs: coeffs, ddcContent: ddcContent);

  bool get isArbitraryEqEnabled => _equalizerManager.isArbitraryEqEnabled;

  String get arbitraryEqString => _equalizerManager.arbitraryEqString;

  bool get arbitraryEqLinearPhase => _equalizerManager.arbitraryEqLinearPhase;

  Future<void> setArbitraryEq(bool enabled,
          {String? eqString, bool? linearPhase}) =>
      _equalizerManager.setArbitraryEq(enabled,
          eqString: eqString, linearPhase: linearPhase);

  bool get isLiveProgEnabled => _equalizerManager.isLiveProgEnabled;

  String get liveProgCode => _equalizerManager.liveProgCode;

  Future<void> setLiveProg(bool enabled, {String? code}) =>
      _equalizerManager.setLiveProg(enabled, code: code);

  Future<void> setLiveProgSlider(int sliderIndex, double value) =>
      _equalizerManager.setLiveProgSlider(sliderIndex, value);

  bool get isDynamicBassEnabled => _equalizerManager.isDynamicBassEnabled;

  double get dynamicBassStrength => _equalizerManager.dynamicBassStrength;

  int get dynamicBassPreset => _equalizerManager.dynamicBassPreset;

  Future<void> setDynamicBass({
    required bool enabled,
    double? strength,
    int? preset,
    int? xLow,
    int? xHigh,
    int? yLow,
    int? yHigh,
    double? sideGainLow,
    double? sideGainHigh,
  }) =>
      _equalizerManager.setDynamicBass(
        enabled: enabled,
        strength: strength,
        preset: preset,
        xLow: xLow,
        xHigh: xHigh,
        yLow: yLow,
        yHigh: yHigh,
        sideGainLow: sideGainLow,
        sideGainHigh: sideGainHigh,
      );
































































































  // Requires: provided by the composing class (same library).
  AudioPlayer get _activePlayer;

  // Requires: provided by the composing class (same library).
  void _broadcastState(PlaybackEvent event);

  // Requires: provided by the composing class (same library).
  UriAudioSource _createAudioSource(SongsTableData song, MediaItem tag);

  // Requires: provided by the composing class (same library).
  CrossfadeManager get _crossfadeManager;

  // Requires: provided by the composing class (same library).
  Timer? get _crossfadeSwitchDebounce;
  set _crossfadeSwitchDebounce(Timer? value);

  // Requires: provided by the composing class (same library).
  int get _currentIndex;

  // Requires: provided by the composing class (same library).
  int get _engineSwitchGeneration;
  set _engineSwitchGeneration(int value);

  // Requires: provided by the composing class (same library).
  EqualizerManager get _equalizerManager;

  // Requires: provided by the composing class (same library).
  bool get _gaplessEnabled;
  set _gaplessEnabled(bool value);

  // Requires: provided by the composing class (same library).
  bool get _gaplessMode;

  // Requires: provided by the composing class (same library).
  Future<void> _loadGaplessQueue( {Duration? initialPosition, bool preload = true});

  // Requires: provided by the composing class (same library).
  List<SongsTableData> get _songs;

  // Requires: provided by the composing class (same library).
  bool get _gaplessLoaded;
  set _gaplessLoaded(bool value);

  // Requires: provided by the composing class (same library).
  Duration? get _pendingLazyPosition;
  set _pendingLazyPosition(Duration? value);

  // Requires: provided by the composing class (same library).
  Future<void> playSongAt(int index, {Duration? initialPosition});
}
