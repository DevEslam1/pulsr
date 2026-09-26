// lib/features/player/cubit/controllers/player_dsp_effects.dart
part of 'player_dsp_controller.dart';

extension PlayerDspEffectsExtension on PlayerDspController {
  // Audio Effects
  Future<void> setBassBoost(double amount) async {
    final clamped = amount.clamp(0.0, 1.0);
    final state = _getState();
    await applyDspEffect(
      featureName: 'Bass Boost',
      guardCondition: amount > 0.01,
      updateDsp: (dsp) => dsp.copyWith(
        eqPreset: EqPreset(
          name: state.eqPreset.name,
          gains: state.eqPreset.gains,
          bassBoost: clamped,
        ),
      ),
      applyAudioHandler: () => _audioHandler.setBassBoost(clamped),
    );
  }

  Future<void> setVirtualizerEnabled(bool enabled) => applyDspEffect(
        featureName: 'Virtualizer',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(isVirtualizerEnabled: enabled),
        applyAudioHandler: () => _audioHandler.setVirtualizerEnabled(enabled),
      );

  Future<void> setVirtualizerStrength(double strength) => applyDspEffect(
        featureName: 'Virtualizer',
        showErrorOnGuard: false,
        updateDsp: (dsp) => dsp.copyWith(virtualizerStrength: strength),
        applyAudioHandler: () => _audioHandler.setVirtualizerStrength(strength),
      );

  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) {
    final isEnabled = enabled ?? (preset != DynamicsPreset.off);
    return applyDspEffect(
      featureName: 'Dynamics',
      guardCondition: isEnabled,
      updateDsp: (dsp) => dsp.copyWith(
        dynamicsPreset: preset,
        isDynamicsEnabled: isEnabled,
      ),
      applyAudioHandler: () =>
          _audioHandler.setDynamicsPreset(preset, enabled: enabled),
    );
  }

  Future<void> toggleDynamicsBypass() async {
    await _audioHandler.toggleDynamicsBypass();
    final state = _getState();
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(
        isDynamicsEnabled: !_audioHandler.isDynamicsBypassed &&
            state.dynamicsPreset != DynamicsPreset.off,
      ),
    ));
  }

  Future<void> setDspEffectsEnabled(bool enabled) async {
    if (enabled && !guardDsp('DSP Engine')) return;
    final state = _getState();
    try {
      if (!enabled) {
        if (state.isDspEffectsActive) {
          _dspSnapshot = state;
        }
        _emit(state.copyWith(
          dsp: state.dsp.copyWith(
            isSpatializerEnabled: false,
            isVirtualizerEnabled: false,
            isDynamicsEnabled: false,
            isCrossfeedEnabled: false,
            isLimiterEnabled: false,
            isReverbEnabled: false,
            isSaturationEnabled: false,
            isStereoWidthEnabled: false,
            isLoudnessContourEnabled: false,
            isSubCrossoverEnabled: false,
            isDynamicEqEnabled: false,
            isViperDdcEnabled: false,
            isArbitraryEqEnabled: false,
            isLiveProgEnabled: false,
            isDynamicBassEnabled: false,
            volumeBoost: 0.0,
          ),
        ));
        await _audioHandler.setSpatializerEnabled(false);
        await _audioHandler.setVirtualizerEnabled(false);
        await _audioHandler.setDynamicsPreset(DynamicsPreset.off, enabled: false);
        await _audioHandler.setCrossfeed(false);
        await _audioHandler.setLookaheadLimiter(false);
        await _audioHandler.setReverb(false);
        await _audioHandler.setSaturation(false);
        await _audioHandler.setStereoWidth(false);
        await _audioHandler.setLoudnessContour(false);
        await _audioHandler.setSubCrossover(false);
        await _audioHandler.setDynamicEq(false);
        await _audioHandler.setViperDdc(false);
        await _audioHandler.setArbitraryEq(false);
        await _audioHandler.setLiveProg(false);
        await _audioHandler.setDynamicBass(enabled: false);
        await _audioHandler.setVolumeBoost(0.0);
      } else {
        final snap = _dspSnapshot;
        if (snap != null && snap.isDspEffectsActive) {
          _emit(state.copyWith(
            dsp: snap.dsp,
          ));
          if (snap.isSpatializerEnabled) {
            await _audioHandler.setSpatializerEnabled(true);
          }
          if (snap.isVirtualizerEnabled) {
            await _audioHandler.setVirtualizerEnabled(true);
            await _audioHandler.setVirtualizerStrength(snap.virtualizerStrength);
          }
          if (snap.isDynamicsEnabled && snap.dynamicsPreset != DynamicsPreset.off) {
            await _audioHandler.setDynamicsPreset(snap.dynamicsPreset, enabled: true);
          }
          if (snap.isCrossfeedEnabled) {
            await _audioHandler.setCrossfeed(true,
                delayUs: snap.crossfeedDelayUs, feedDb: snap.crossfeedFeedDb);
          }
          if (snap.isLimiterEnabled) {
            await _audioHandler.setLookaheadLimiter(true,
                thresholdDb: snap.limiterThresholdDb, releaseMs: snap.limiterReleaseMs);
          }
          if (snap.isReverbEnabled) {
            await _audioHandler.setReverb(true,
                preset: snap.reverbPreset, wetDry: snap.reverbWetDry);
          }
          if (snap.isSaturationEnabled) {
            await _audioHandler.setSaturation(true,
                drive: snap.saturationDrive,
                mix: snap.saturationMix,
                tilt: snap.saturationTilt);
          }
          if (snap.isStereoWidthEnabled) {
            await _audioHandler.setStereoWidth(true, width: snap.stereoWidth);
          }
          if (snap.isLoudnessContourEnabled) {
            await _audioHandler.setLoudnessContour(true,
                intensity: snap.loudnessContourIntensity);
          }
          if (snap.isSubCrossoverEnabled) {
            await _audioHandler.setSubCrossover(true,
                cornerHz: snap.subCrossoverCornerHz,
                slopeDbPerOct: snap.subCrossoverSlopeDbPerOct,
                gain: snap.subCrossoverGain);
          }
          if (snap.isDynamicEqEnabled) {
            await _audioHandler.setDynamicEq(true);
          }
          if (snap.isViperDdcEnabled) {
            await _audioHandler.setViperDdc(true,
                profileName: snap.viperDdcProfileName);
          }
          if (snap.isArbitraryEqEnabled) {
            await _audioHandler.setArbitraryEq(true,
                eqString: snap.arbitraryEqString);
          }
          if (snap.isLiveProgEnabled) {
            await _audioHandler.setLiveProg(true, code: snap.liveProgCode);
          }
          if (snap.isDynamicBassEnabled) {
            await _audioHandler.setDynamicBass(
              enabled: true,
              strength: snap.dynamicBassStrength,
              preset: snap.dynamicBassPreset,
            );
          }
          if (snap.volumeBoost > 0.0) {
            await _audioHandler.setVolumeBoost(snap.volumeBoost);
          }
        } else {
          final enableSpatial = state.isSpatializerSupported;
          final enableVirt = !enableSpatial && state.isVirtualizerSupported;
          _emit(state.copyWith(
            dsp: state.dsp.copyWith(
              isSpatializerEnabled: enableSpatial,
              isVirtualizerEnabled: enableVirt,
              virtualizerStrength: enableVirt ? 0.35 : state.virtualizerStrength,
              isLimiterEnabled: true,
              limiterThresholdDb: -0.2,
              limiterReleaseMs: 50.0,
            ),
          ));
          if (enableSpatial) {
            await _audioHandler.setSpatializerEnabled(true);
          }
          if (enableVirt) {
            await _audioHandler.setVirtualizerEnabled(true);
            await _audioHandler.setVirtualizerStrength(0.35);
          }
          await _audioHandler.setLookaheadLimiter(true,
              thresholdDb: -0.2, releaseMs: 50.0);
        }
      }
    } catch (e) {
      _syncAudioEffects();
      final s = _getState();
      _emit(s.copyWith(
          playback: s.playback
              .copyWith(errorMessage: 'Failed to update DSP effects: $e')));
    }
  }

  Future<void> setVolumeBoost(double value) {
    final state = _getState();
    final preampDb = state.selectedHeadphoneProfile?.preampGain ?? 0.0;
    var safeValue = value.clamp(0.0, 1.0);
    if ((preampDb + safeValue * 10.0) > 6.0) {
      safeValue = ((6.0 - preampDb) / 10.0).clamp(0.0, 1.0);
      if (safeValue < value - 0.01) {
        ErrorLogger.log(
          'Volume boost request (${(value * 10).toStringAsFixed(1)} dB) clamped to '
          '+${(safeValue * 10).toStringAsFixed(1)} dB to prevent clipping with preamp (${preampDb.toStringAsFixed(1)} dB)',
          category: 'PlayerDspEffects',
        );
      }
    }
    return applyDspEffect(
      featureName: 'Volume Boost',
      guardCondition: safeValue > 0.01,
      updateDsp: (dsp) => dsp.copyWith(volumeBoost: safeValue),
      applyAudioHandler: () => _audioHandler.setVolumeBoost(safeValue),
    );
  }

  Future<void> setSpatializerEnabled(bool enabled) => applyDspEffect(
        featureName: 'Spatializer',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(isSpatializerEnabled: enabled),
        applyAudioHandler: () => _audioHandler.setSpatializerEnabled(enabled),
      );

  Future<void> setCrossfeed(bool enabled,
          {double? delayUs, double? feedDb, int? mode}) =>
      applyDspEffect(
        featureName: 'Crossfeed',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(
          isCrossfeedEnabled: enabled,
          crossfeedDelayUs: delayUs ?? dsp.crossfeedDelayUs,
          crossfeedFeedDb: feedDb ?? dsp.crossfeedFeedDb,
          crossfeedMode: mode ?? dsp.crossfeedMode,
        ),
        applyAudioHandler: () => _audioHandler.setCrossfeed(enabled,
            delayUs: delayUs, feedDb: feedDb, mode: mode),
      );

  Future<void> setCrossfeedMode(int mode) => applyDspEffect(
        featureName: 'Crossfeed Mode',
        requiresGuard: true,
        guardCondition: _getState().isCrossfeedEnabled,
        showErrorOnGuard: false,
        updateDsp: (dsp) => dsp.copyWith(crossfeedMode: mode),
        applyAudioHandler: () => _audioHandler.setCrossfeedMode(mode),
      );

  Future<void> setLookaheadLimiter(bool enabled,
          {double? thresholdDb, double? releaseMs, double? lookaheadMs}) =>
      applyDspEffect(
        featureName: 'Limiter',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(
          isLimiterEnabled: enabled,
          limiterThresholdDb: thresholdDb ?? dsp.limiterThresholdDb,
          limiterReleaseMs: releaseMs ?? dsp.limiterReleaseMs,
        ),
        applyAudioHandler: () => _audioHandler.setLookaheadLimiter(enabled,
            thresholdDb: thresholdDb,
            releaseMs: releaseMs,
            lookaheadMs: lookaheadMs),
      );

  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) =>
      applyDspEffect(
        featureName: 'Reverb',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(
          isReverbEnabled: enabled,
          reverbPreset: preset ?? dsp.reverbPreset,
          reverbWetDry: wetDry ?? dsp.reverbWetDry,
        ),
        applyAudioHandler: () =>
            _audioHandler.setReverb(enabled, preset: preset, wetDry: wetDry),
      );

  Future<void> setReverbPreset(int preset) => setReverb(_getState().isReverbEnabled, preset: preset);

  Future<bool> loadCustomImpulseResponse(List<double> irSamples) async {
    if (!guardDsp('Reverb IR')) return false;
    try {
      final loaded = await _audioHandler.loadCustomImpulseResponse(irSamples);
      if (!loaded) {
        _syncAudioEffects();
        final s = _getState();
        _emit(s.copyWith(
            playback: s.playback.copyWith(
                errorMessage: 'Impulse response rejected by the audio engine')));
        return false;
      }
      if (!_isClosed()) {
        final state = _getState();
        _emit(state.copyWith(
          dsp: state.dsp.copyWith(
            isReverbEnabled: true,
            reverbPreset: ReverbPreset.custom.wireValue,
          ),
          playback: state.playback.copyWith(errorMessage: null),
        ));
      }
      return true;
    } catch (e) {
      _syncAudioEffects();
      final s = _getState();
      _emit(s.copyWith(
          playback: s.playback
              .copyWith(errorMessage: 'Failed to load impulse response: $e')));
      return false;
    }
  }

  Future<void> pickAndLoadCustomIrFile() async {
    if (!guardDsp('Reverb IR')) return;
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['wav'],
      );
      if (result != null) {
        final file = SafeFilePath.validate(result.path, allowedExtensions: ['wav']);
        if (file == null) {
          throw Exception('Invalid or inaccessible WAV file');
        }
        // E3: Protect against out-of-memory on oversized impulse response files (>25MB)
        if (await file.length() > PlayerDspController.maxIrFileSizeBytes) {
          throw Exception('IR WAV file exceeds 25 MB limit');
        }
        final samples = await IrFileParser.parseWavFile(file);
        if (await loadCustomImpulseResponse(samples)) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(PrefsKeys.customReverbIrPath, file.path);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to pick/load custom IR file',
          error: e, stackTrace: st, category: 'Reverb');
      final s = _getState();
      _emit(s.copyWith(
          playback: s.playback
              .copyWith(errorMessage: 'Failed to load IR WAV file: $e')));
    }
  }

  Future<void> setStereoBalance(double balance) {
    final clamped = balance.clamp(-1.0, 1.0);
    return applyDspEffect(
      featureName: 'Stereo Balance',
      requiresGuard: true,
      guardCondition: clamped.abs() > 0.01,
      showErrorOnGuard: false,
      updateDsp: (dsp) => dsp.copyWith(stereoBalance: clamped),
      applyAudioHandler: () => _audioHandler.setStereoBalance(clamped),
    );
  }

  Future<void> setMonoMix(bool mono) => applyDspEffect(
        featureName: 'Mono Mix',
        guardCondition: mono,
        updateDsp: (dsp) => dsp.copyWith(monoMix: mono),
        applyAudioHandler: () => _audioHandler.setMonoMix(mono),
      );

  Future<void> setSincResampler(bool enabled) => applyDspEffect(
        featureName: 'Resampler',
        guardCondition: enabled,
        showErrorOnGuard: false,
        updateDsp: (dsp) => dsp.copyWith(isSincResamplerEnabled: enabled),
        applyAudioHandler: () => _audioHandler.setSincResampler(enabled),
      );

  Future<void> setDither(bool enabled, {int? targetBitDepth}) async {
    if (targetBitDepth != null &&
        targetBitDepth != 16 &&
        targetBitDepth != 24 &&
        targetBitDepth != 32) {
      return;
    }
    await applyDspEffect(
      featureName: 'Dither',
      guardCondition: enabled,
      showErrorOnGuard: false,
      updateDsp: (dsp) => dsp.copyWith(
        isDitherEnabled: enabled,
        ditherTargetBitDepth: targetBitDepth ?? dsp.ditherTargetBitDepth,
      ),
      applyAudioHandler: () =>
          _audioHandler.setDither(enabled, targetBitDepth: targetBitDepth),
    );
  }

  Future<void> setSaturation(bool enabled,
          {double? drive,
          double? mix,
          double? tilt,
          int? mode,
          bool? multiband}) =>
      applyDspEffect(
        featureName: 'Harmonic Saturation',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(
          isSaturationEnabled: enabled,
          saturationDrive: drive ?? dsp.saturationDrive,
          saturationMix: mix ?? dsp.saturationMix,
          saturationTilt: tilt ?? dsp.saturationTilt,
          saturationMultiband: multiband ?? dsp.saturationMultiband,
        ),
        applyAudioHandler: () => _audioHandler.setSaturation(enabled,
            drive: drive,
            mix: mix,
            tilt: tilt,
            mode: mode,
            multiband: multiband),
      );

  Future<void> setSaturationMultiband(bool multiband) => applyDspEffect(
        featureName: 'Saturation Multiband',
        requiresGuard: true,
        guardCondition: _getState().isSaturationEnabled,
        showErrorOnGuard: false,
        updateDsp: (dsp) => dsp.copyWith(saturationMultiband: multiband),
        applyAudioHandler: () => _audioHandler.setSaturationMultiband(multiband),
      );

  Future<void> setStereoWidth(bool enabled,
          {double? width,
          bool? multiband,
          double? lowWidth,
          double? midWidth,
          double? highWidth,
          double? lowCrossoverHz,
          double? highCrossoverHz}) =>
      applyDspEffect(
        featureName: 'Stereo Width',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(
          isStereoWidthEnabled: enabled,
          stereoWidth: width ?? dsp.stereoWidth,
          stereoWidthMultiband: multiband ?? dsp.stereoWidthMultiband,
          stereoWidthLow: lowWidth ?? dsp.stereoWidthLow,
          stereoWidthMid: midWidth ?? dsp.stereoWidthMid,
          stereoWidthHigh: highWidth ?? dsp.stereoWidthHigh,
          stereoWidthLowCrossoverHz:
              lowCrossoverHz ?? dsp.stereoWidthLowCrossoverHz,
          stereoWidthHighCrossoverHz:
              highCrossoverHz ?? dsp.stereoWidthHighCrossoverHz,
        ),
        applyAudioHandler: () => _audioHandler.setStereoWidth(enabled,
            width: width,
            multiband: multiband,
            lowWidth: lowWidth,
            midWidth: midWidth,
            highWidth: highWidth,
            lowCrossoverHz: lowCrossoverHz,
            highCrossoverHz: highCrossoverHz),
      );

  Future<void> setLoudnessContour(bool enabled, {double? intensity}) =>
      applyDspEffect(
        featureName: 'Loudness Contour',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(
          isLoudnessContourEnabled: enabled,
          loudnessContourIntensity: intensity ?? dsp.loudnessContourIntensity,
        ),
        applyAudioHandler: () =>
            _audioHandler.setLoudnessContour(enabled, intensity: intensity),
      );

  Future<void> setSubCrossover(bool enabled,
          {double? cornerHz,
          double? slopeDbPerOct,
          double? gain,
          bool? bassMono,
          bool? antiPop}) =>
      applyDspEffect(
        featureName: 'Sub Crossover',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(
          isSubCrossoverEnabled: enabled,
          subCrossoverCornerHz: cornerHz ?? dsp.subCrossoverCornerHz,
          subCrossoverSlopeDbPerOct:
              slopeDbPerOct ?? dsp.subCrossoverSlopeDbPerOct,
          subCrossoverGain: gain ?? dsp.subCrossoverGain,
          subCrossoverBassMono: bassMono ?? dsp.subCrossoverBassMono,
          subCrossoverAntiPop: antiPop ?? dsp.subCrossoverAntiPop,
        ),
        applyAudioHandler: () => _audioHandler.setSubCrossover(enabled,
            cornerHz: cornerHz,
            slopeDbPerOct: slopeDbPerOct,
            gain: gain,
            bassMono: bassMono,
            antiPop: antiPop),
      );

  Future<void> setDynamicEq(bool enabled) => applyDspEffect(
        featureName: 'Dynamic EQ',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(isDynamicEqEnabled: enabled),
        applyAudioHandler: () => _audioHandler.setDynamicEq(enabled),
      );

  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) {
    final bands = List<DynamicEqBandConfig>.from(_getState().dynamicEqBands);
    while (bands.length <= index) {
      bands.add(const DynamicEqBandConfig());
    }
    bands[index] = band;
    return applyDspEffect(
      featureName: 'Dynamic EQ Band',
      requiresGuard: false,
      updateDsp: (dsp) => dsp.copyWith(dynamicEqBands: bands),
      applyAudioHandler: () => _audioHandler.setDynamicEqBand(index, band),
    );
  }

  Future<void> addDynamicEqBand() {
    if (_getState().dynamicEqBands.length >= 8) return Future.value();
    final bands = List<DynamicEqBandConfig>.from(_getState().dynamicEqBands)
      ..add(const DynamicEqBandConfig());
    return applyDspEffect(
      featureName: 'Dynamic EQ Band',
      requiresGuard: false,
      updateDsp: (dsp) => dsp.copyWith(dynamicEqBands: bands),
      applyAudioHandler: () => _audioHandler.addDynamicEqBand(),
    );
  }

  Future<void> removeDynamicEqBand(int index) {
    final currentBands = _getState().dynamicEqBands;
    if (index < 0 || index >= currentBands.length) return Future.value();
    final bands = List<DynamicEqBandConfig>.from(currentBands)..removeAt(index);
    return applyDspEffect(
      featureName: 'Dynamic EQ Band',
      requiresGuard: false,
      updateDsp: (dsp) => dsp.copyWith(dynamicEqBands: bands),
      applyAudioHandler: () => _audioHandler.removeDynamicEqBand(index),
    );
  }

  Future<void> setViperDdcEnabled(bool enabled,
          {String? profileName, List<double>? coeffs}) =>
      applyDspEffect(
        featureName: 'ViPER-DDC',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(
          isViperDdcEnabled: enabled,
          viperDdcProfileName: profileName ?? dsp.viperDdcProfileName,
        ),
        applyAudioHandler: () => _audioHandler.setViperDdc(enabled,
            profileName: profileName, coeffs: coeffs),
      );

  bool get isArbitraryEqLinearPhase => _audioHandler.arbitraryEqLinearPhase;

  Future<void> setArbitraryEqEnabled(bool enabled,
          {String? eqString, bool? linearPhase}) =>
      applyDspEffect(
        featureName: 'Arbitrary Response EQ',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(
          isArbitraryEqEnabled: enabled,
          arbitraryEqString: eqString ?? dsp.arbitraryEqString,
        ),
        applyAudioHandler: () => _audioHandler.setArbitraryEq(enabled,
            eqString: eqString, linearPhase: linearPhase),
      );

  Future<void> setLiveProgEnabled(bool enabled, {String? code}) =>
      applyDspEffect(
        featureName: 'Live Programmable DSP',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(
          isLiveProgEnabled: enabled,
          liveProgCode: code ?? dsp.liveProgCode,
        ),
        applyAudioHandler: () =>
            _audioHandler.setLiveProg(enabled, code: code),
      );

  Future<void> setLiveProgSlider(int sliderIndex, double value) async {
    try {
      await _audioHandler.setLiveProgSlider(sliderIndex, value);
    } catch (e) {
      final s = _getState();
      _emit(s.copyWith(
          playback: s.playback
              .copyWith(errorMessage: 'Failed to set LiveProg slider: $e')));
    }
  }

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
      applyDspEffect(
        featureName: 'Dynamic Bass',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(
          isDynamicBassEnabled: enabled,
          dynamicBassStrength: strength ?? dsp.dynamicBassStrength,
          dynamicBassPreset: preset ?? dsp.dynamicBassPreset,
        ),
        applyAudioHandler: () => _audioHandler.setDynamicBass(
          enabled: enabled,
          strength: strength,
          preset: preset,
          xLow: xLow,
          xHigh: xHigh,
          yLow: yLow,
          yHigh: yHigh,
          sideGainLow: sideGainLow,
          sideGainHigh: sideGainHigh,
        ),
      );
}
