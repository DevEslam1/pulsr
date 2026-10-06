// lib/features/player/cubit/controllers/player_dsp_effects.dart
part of 'player_dsp_controller.dart';

extension PlayerDspEffectsExtension on PlayerDspController {
  /// Collects every currently-active gain stage (in dB) for the shared clipping
  /// budget, reading live values from PlayerState, the equalizer manager and
  /// the volume controller. [excludeVolumeBoost] / [excludeBassBoost] drop the
  /// stage being (re)set so it is budgeted against the OTHERS only.
  List<GainStage> _activeGainStages({
    bool excludeVolumeBoost = false,
    bool excludeBassBoost = false,
  }) {
    final state = _getState();
    // Engine accessors (equalizerManager is a late-final, volumeController is
    // nullable) may be unreadable before the handler is fully wired or in unit
    // tests with a partial fake. The budget is a best-effort pre-brickwall
    // guard — the native unconditional output clamp is the hard safety net —
    // so a read failure degrades to 0 dB rather than throwing into a setter.
    double eqPreampDb = 0.0;
    double rgPreampDb = 0.0;
    try {
      eqPreampDb = _audioHandler.equalizerManager.preampDb;
      final vol = _audioHandler.volumeController;
      final rgActive = (vol?.replayGainMode ?? 'off') != 'off';
      rgPreampDb = rgActive ? (vol?.preampWithRg ?? 0.0) : 0.0;
    } catch (_) {
      // Accessors not available yet; keep the conservative 0 dB defaults.
    }
    final stages = <GainStage>[
      // EQ preamp already folds in the selected headphone profile's preamp
      // (manager.preampDb is set from the profile on apply), so it is the single
      // preamp stage here — summing it AND the profile preampGain would
      // double-count (and a negative AutoEQ preamp would wrongly inflate the
      // budget).
      GainStage('EQ preamp', eqPreampDb),
      GainStage('ReplayGain preamp', rgPreampDb),
      GainStagingBudget.scaledStage('Loudness contour',
          enabled: state.isLoudnessContourEnabled,
          maxDb: GainStagingBudget.maxLoudnessContourDb,
          intensity: state.loudnessContourIntensity),
      GainStagingBudget.scaledStage('Saturation',
          enabled: state.isSaturationEnabled,
          maxDb: GainStagingBudget.maxSaturationDb,
          intensity: state.saturationDrive.clamp(0.0, 1.0)),
      GainStagingBudget.scaledStage('Dynamic bass',
          enabled: state.isDynamicBassEnabled,
          maxDb: GainStagingBudget.maxDynamicBassDb,
          intensity: ((state.dynamicBassStrength - 1.0) / 7.0).clamp(0.0, 1.0)),
      GainStagingBudget.scaledStage('Sub crossover',
          enabled: state.isSubCrossoverEnabled,
          maxDb: GainStagingBudget.maxSubCrossoverDb,
          intensity: state.subCrossoverGain.clamp(0.0, 1.0)),
    ];
    if (!excludeBassBoost) {
      stages.add(GainStage(
          'Bass boost',
          state.eqPreset.bassBoost.clamp(0.0, 1.0).toDouble() *
              GainStagingBudget.maxBassBoostDb));
    }
    if (!excludeVolumeBoost) {
      stages.add(GainStage(
          'Volume boost',
          state.volumeBoost.clamp(0.0, 1.0).toDouble() *
              GainStagingBudget.maxVolumeBoostDb));
    }
    return stages;
  }

  // Audio Effects
  Future<void> setBassBoost(double amount) async {
    final requested = amount.clamp(0.0, 1.0).toDouble();
    // Budget bass boost against every other active boost stage so the summed
    // DSP gain stays within headroom (not just an isolated 0..1 clamp).
    final allowedDb = GainStagingBudget.clampBoostDb(
      requestedBoostDb: requested * GainStagingBudget.maxBassBoostDb,
      committedStages: _activeGainStages(excludeBassBoost: true),
    );
    final clamped = (allowedDb / GainStagingBudget.maxBassBoostDb)
        .clamp(0.0, 1.0)
        .toDouble();
    if (clamped < requested - 0.01) {
      ErrorLogger.log(
        'Bass boost request (${(requested * GainStagingBudget.maxBassBoostDb).toStringAsFixed(1)} dB) clamped to '
        '+${(clamped * GainStagingBudget.maxBassBoostDb).toStringAsFixed(1)} dB to keep the summed DSP gain '
        'within +${GainStagingBudget.defaultHeadroomCeilingDb.toStringAsFixed(1)} dB headroom',
        category: 'PlayerDspEffects',
      );
    }
    await applyDspEffect(
      featureName: 'Bass Boost',
      guardCondition: requested > 0.01,
      // State mirrors the user's requested boost (the slider stays put); the
      // engine receives the headroom-staged value so stacked effects can't
      // over-drive the signal into the final output clamp. Read eqPreset from
      // the lambda's `dsp` argument, not a pre-await snapshot, so rapid slider
      // updates can't overwrite each other.
      updateDsp: (dsp) => dsp.copyWith(
        eqPreset: dsp.eqPreset.copyWith(
          bassBoost: requested,
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
        // Only capture a snapshot while effects are actually active. A second
        // disable (already inactive) must NOT null it out, or the next enable
        // would have nothing to restore.
        if (state.isDspEffectsActive) {
          _dspSnapshot = state.dsp;
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
        await _audioHandler.setDynamicsPreset(DynamicsPreset.off,
            enabled: false);
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
          final currentDsp = state.dsp;
          final restoredDsp = currentDsp.copyWith(
            isSpatializerEnabled: snap.isSpatializerEnabled,
            isVirtualizerEnabled: snap.isVirtualizerEnabled,
            virtualizerStrength: snap.virtualizerStrength,
            isDynamicsEnabled: snap.isDynamicsEnabled,
            dynamicsPreset: snap.dynamicsPreset,
            isCrossfeedEnabled: snap.isCrossfeedEnabled,
            crossfeedDelayUs: snap.crossfeedDelayUs,
            crossfeedFeedDb: snap.crossfeedFeedDb,
            crossfeedMode: snap.crossfeedMode,
            isLimiterEnabled: snap.isLimiterEnabled,
            limiterThresholdDb: snap.limiterThresholdDb,
            limiterReleaseMs: snap.limiterReleaseMs,
            isReverbEnabled: snap.isReverbEnabled,
            reverbPreset: snap.reverbPreset,
            reverbWetDry: snap.reverbWetDry,
            isSaturationEnabled: snap.isSaturationEnabled,
            saturationDrive: snap.saturationDrive,
            saturationMix: snap.saturationMix,
            saturationTilt: snap.saturationTilt,
            saturationMultiband: snap.saturationMultiband,
            isStereoWidthEnabled: snap.isStereoWidthEnabled,
            stereoWidth: snap.stereoWidth,
            stereoWidthMultiband: snap.stereoWidthMultiband,
            stereoWidthLow: snap.stereoWidthLow,
            stereoWidthMid: snap.stereoWidthMid,
            stereoWidthHigh: snap.stereoWidthHigh,
            stereoWidthLowCrossoverHz: snap.stereoWidthLowCrossoverHz,
            stereoWidthHighCrossoverHz: snap.stereoWidthHighCrossoverHz,
            isLoudnessContourEnabled: snap.isLoudnessContourEnabled,
            loudnessContourIntensity: snap.loudnessContourIntensity,
            isSubCrossoverEnabled: snap.isSubCrossoverEnabled,
            subCrossoverCornerHz: snap.subCrossoverCornerHz,
            subCrossoverSlopeDbPerOct: snap.subCrossoverSlopeDbPerOct,
            subCrossoverGain: snap.subCrossoverGain,
            subCrossoverBassMono: snap.subCrossoverBassMono,
            subCrossoverAntiPop: snap.subCrossoverAntiPop,
            isDynamicEqEnabled: snap.isDynamicEqEnabled,
            dynamicEqBands: snap.dynamicEqBands,
            isViperDdcEnabled: snap.isViperDdcEnabled,
            viperDdcProfileName: snap.viperDdcProfileName,
            isArbitraryEqEnabled: snap.isArbitraryEqEnabled,
            arbitraryEqString: snap.arbitraryEqString,
            isLiveProgEnabled: snap.isLiveProgEnabled,
            liveProgCode: snap.liveProgCode,
            isDynamicBassEnabled: snap.isDynamicBassEnabled,
            dynamicBassStrength: snap.dynamicBassStrength,
            dynamicBassPreset: snap.dynamicBassPreset,
            volumeBoost: snap.volumeBoost,
          );
          _emit(state.copyWith(dsp: restoredDsp));
          if (snap.isSpatializerEnabled) {
            await _audioHandler.setSpatializerEnabled(true);
          }
          if (snap.isVirtualizerEnabled) {
            await _audioHandler.setVirtualizerEnabled(true);
            await _audioHandler
                .setVirtualizerStrength(snap.virtualizerStrength);
          }
          if (snap.isDynamicsEnabled &&
              snap.dynamicsPreset != DynamicsPreset.off) {
            await _audioHandler.setDynamicsPreset(snap.dynamicsPreset,
                enabled: true);
          }
          if (snap.isCrossfeedEnabled) {
            await _audioHandler.setCrossfeed(true,
                delayUs: snap.crossfeedDelayUs,
                feedDb: snap.crossfeedFeedDb,
                mode: snap.crossfeedMode);
          }
          if (snap.isLimiterEnabled) {
            await _audioHandler.setLookaheadLimiter(true,
                thresholdDb: snap.limiterThresholdDb,
                releaseMs: snap.limiterReleaseMs);
          }
          if (snap.isReverbEnabled) {
            await _audioHandler.setReverb(true,
                preset: snap.reverbPreset, wetDry: snap.reverbWetDry);
          }
          if (snap.isSaturationEnabled) {
            await _audioHandler.setSaturation(true,
                drive: snap.saturationDrive,
                mix: snap.saturationMix,
                tilt: snap.saturationTilt,
                multiband: snap.saturationMultiband);
          }
          if (snap.isStereoWidthEnabled) {
            await _audioHandler.setStereoWidth(true,
                width: snap.stereoWidth,
                multiband: snap.stereoWidthMultiband,
                lowWidth: snap.stereoWidthLow,
                midWidth: snap.stereoWidthMid,
                highWidth: snap.stereoWidthHigh,
                lowCrossoverHz: snap.stereoWidthLowCrossoverHz,
                highCrossoverHz: snap.stereoWidthHighCrossoverHz);
          }
          if (snap.isLoudnessContourEnabled) {
            await _audioHandler.setLoudnessContour(true,
                intensity: snap.loudnessContourIntensity);
          }
          if (snap.isSubCrossoverEnabled) {
            await _audioHandler.setSubCrossover(true,
                cornerHz: snap.subCrossoverCornerHz,
                slopeDbPerOct: snap.subCrossoverSlopeDbPerOct,
                gain: snap.subCrossoverGain,
                bassMono: snap.subCrossoverBassMono,
                antiPop: snap.subCrossoverAntiPop);
          }
          if (snap.isDynamicEqEnabled) {
            await _audioHandler.setDynamicEq(true);
            for (int i = 0; i < snap.dynamicEqBands.length; i++) {
              await _audioHandler.setDynamicEqBand(i, snap.dynamicEqBands[i]);
            }
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
            await setVolumeBoost(snap.volumeBoost);
          }
        } else {
          final enableSpatial = state.isSpatializerSupported;
          final enableVirt = !enableSpatial && state.isVirtualizerSupported;
          _emit(state.copyWith(
            dsp: state.dsp.copyWith(
              isSpatializerEnabled: enableSpatial,
              isVirtualizerEnabled: enableVirt,
              virtualizerStrength:
                  enableVirt ? 0.35 : state.virtualizerStrength,
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

  Future<void> rebalanceVolumeBoostIfNeeded() async {
    final s = _getState();
    if (s.volumeBoost <= 0.0) return;
    final allowedDb = GainStagingBudget.clampBoostDb(
      requestedBoostDb: s.volumeBoost * GainStagingBudget.maxVolumeBoostDb,
      committedStages: _activeGainStages(excludeVolumeBoost: true),
    );
    final safeValue = (allowedDb / GainStagingBudget.maxVolumeBoostDb)
        .clamp(0.0, 1.0)
        .toDouble();
    if (safeValue < s.volumeBoost) {
      await _audioHandler.setVolumeBoost(safeValue);
    }
  }

  Future<void> setVolumeBoost(double value) {
    final requested = value.clamp(0.0, 1.0).toDouble();
    // Budget the broadband volume boost against the FULL active gain chain
    // (EQ/ReplayGain preamp, bass boost, loudness, saturation, dynamic bass,
    // sub-crossover) instead of only the headphone preamp, so stacking effects
    // can never drive the summed gain past the shared headroom ceiling.
    final allowedDb = GainStagingBudget.clampBoostDb(
      requestedBoostDb: requested * GainStagingBudget.maxVolumeBoostDb,
      committedStages: _activeGainStages(excludeVolumeBoost: true),
    );
    final safeValue = (allowedDb / GainStagingBudget.maxVolumeBoostDb)
        .clamp(0.0, 1.0)
        .toDouble();
    if (safeValue < requested - 0.01) {
      ErrorLogger.log(
        'Volume boost request (${(requested * GainStagingBudget.maxVolumeBoostDb).toStringAsFixed(1)} dB) clamped to '
        '+${(safeValue * GainStagingBudget.maxVolumeBoostDb).toStringAsFixed(1)} dB to keep the summed DSP gain '
        'within +${GainStagingBudget.defaultHeadroomCeilingDb.toStringAsFixed(1)} dB headroom',
        category: 'PlayerDspEffects',
      );
    }
    return applyDspEffect(
      featureName: 'Volume Boost',
      guardCondition: requested > 0.01,
      // State mirrors the user's requested boost (the slider stays put); the
      // engine receives the headroom-staged value so stacked effects can't
      // over-drive the signal into the final output clamp.
      updateDsp: (dsp) => dsp.copyWith(volumeBoost: requested),
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
      {double? delayUs, double? feedDb, int? mode}) {
    final clampedDelay = delayUs != null
        ? DspParamRanges.crossfeedDelayUs.clampRaw(delayUs)
        : null;
    final clampedFeed =
        feedDb != null ? DspParamRanges.crossfeedFeedDb.clampRaw(feedDb) : null;
    final clampedMode =
        mode != null ? DspParamRanges.crossfeedMode.clamp(mode) : null;
    return applyDspEffect(
      featureName: 'Crossfeed',
      guardCondition: enabled,
      updateDsp: (dsp) => dsp.copyWith(
        isCrossfeedEnabled: enabled,
        crossfeedDelayUs: clampedDelay ?? dsp.crossfeedDelayUs,
        crossfeedFeedDb: clampedFeed ?? dsp.crossfeedFeedDb,
        crossfeedMode: clampedMode ?? dsp.crossfeedMode,
      ),
      applyAudioHandler: () => _audioHandler.setCrossfeed(enabled,
          delayUs: clampedDelay, feedDb: clampedFeed, mode: clampedMode),
    );
  }

  Future<void> setCrossfeedMode(int mode) {
    final clampedMode = DspParamRanges.crossfeedMode.clamp(mode);
    return applyDspEffect(
      featureName: 'Crossfeed Mode',
      requiresGuard: true,
      guardCondition: _getState().isCrossfeedEnabled,
      showErrorOnGuard: false,
      updateDsp: (dsp) => dsp.copyWith(crossfeedMode: clampedMode),
      applyAudioHandler: () => _audioHandler.setCrossfeedMode(clampedMode),
    );
  }

  Future<void> setLookaheadLimiter(bool enabled,
      {double? thresholdDb, double? releaseMs, double? lookaheadMs}) {
    final clampedThresh = thresholdDb != null
        ? DspParamRanges.limiterThresholdDb.clampRaw(thresholdDb)
        : null;
    final clampedRelease = releaseMs != null
        ? DspParamRanges.limiterReleaseMs.clampRaw(releaseMs)
        : null;
    final clampedLookahead = lookaheadMs != null
        ? DspParamRanges.limiterLookaheadMs.clampRaw(lookaheadMs)
        : null;
    return applyDspEffect(
      featureName: 'Limiter',
      guardCondition: enabled,
      updateDsp: (dsp) => dsp.copyWith(
        isLimiterEnabled: enabled,
        limiterThresholdDb: clampedThresh ?? dsp.limiterThresholdDb,
        limiterReleaseMs: clampedRelease ?? dsp.limiterReleaseMs,
      ),
      applyAudioHandler: () => _audioHandler.setLookaheadLimiter(enabled,
          thresholdDb: clampedThresh,
          releaseMs: clampedRelease,
          lookaheadMs: clampedLookahead),
    );
  }

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

  Future<void> setReverbPreset(int preset) =>
      setReverb(_getState().isReverbEnabled, preset: preset);

  Future<bool> loadCustomImpulseResponse(List<double> irSamples) async {
    if (!guardDsp('Reverb IR')) return false;
    try {
      final loaded = await _audioHandler.loadCustomImpulseResponse(irSamples);
      if (!loaded) {
        _syncAudioEffects();
        final s = _getState();
        _emit(s.copyWith(
            playback: s.playback.copyWith(
                errorMessage:
                    'Impulse response rejected by the audio engine')));
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
        final file =
            SafeFilePath.validate(result.path, allowedExtensions: ['wav']);
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
      {double? drive, double? mix, double? tilt, int? mode, bool? multiband}) {
    final clampedDrive =
        drive != null ? DspParamRanges.saturationDrive.clampRaw(drive) : null;
    final clampedMix =
        mix != null ? DspParamRanges.saturationMix.clampRaw(mix) : null;
    final clampedTilt =
        tilt != null ? DspParamRanges.saturationTilt.clampRaw(tilt) : null;
    final clampedMode =
        mode != null ? DspParamRanges.saturationMode.clamp(mode) : null;
    return applyDspEffect(
      featureName: 'Harmonic Saturation',
      guardCondition: enabled,
      updateDsp: (dsp) => dsp.copyWith(
        isSaturationEnabled: enabled,
        saturationDrive: clampedDrive ?? dsp.saturationDrive,
        saturationMix: clampedMix ?? dsp.saturationMix,
        saturationTilt: clampedTilt ?? dsp.saturationTilt,
        saturationMultiband: multiband ?? dsp.saturationMultiband,
      ),
      applyAudioHandler: () => _audioHandler.setSaturation(enabled,
          drive: clampedDrive,
          mix: clampedMix,
          tilt: clampedTilt,
          mode: clampedMode,
          multiband: multiband),
    );
  }

  Future<void> setSaturationMultiband(bool multiband) => applyDspEffect(
        featureName: 'Saturation Multiband',
        requiresGuard: true,
        guardCondition: _getState().isSaturationEnabled,
        showErrorOnGuard: false,
        updateDsp: (dsp) => dsp.copyWith(saturationMultiband: multiband),
        applyAudioHandler: () =>
            _audioHandler.setSaturationMultiband(multiband),
      );

  Future<void> setStereoWidth(bool enabled,
      {double? width,
      bool? multiband,
      double? lowWidth,
      double? midWidth,
      double? highWidth,
      double? lowCrossoverHz,
      double? highCrossoverHz}) {
    final clampedWidth =
        width != null ? DspParamRanges.stereoWidth.clampRaw(width) : null;
    final clampedLow = lowWidth != null
        ? DspParamRanges.stereoWidthBand.clampRaw(lowWidth)
        : null;
    final clampedMid = midWidth != null
        ? DspParamRanges.stereoWidthBand.clampRaw(midWidth)
        : null;
    final clampedHigh = highWidth != null
        ? DspParamRanges.stereoWidthBand.clampRaw(highWidth)
        : null;
    final clampedLowCross = lowCrossoverHz != null
        ? DspParamRanges.stereoWidthLowCrossoverHz.clampRaw(lowCrossoverHz)
        : null;
    final clampedHighCross = highCrossoverHz != null
        ? DspParamRanges.stereoWidthHighCrossoverHz.clampRaw(highCrossoverHz)
        : null;
    return applyDspEffect(
      featureName: 'Stereo Width',
      guardCondition: enabled,
      updateDsp: (dsp) => dsp.copyWith(
        isStereoWidthEnabled: enabled,
        stereoWidth: clampedWidth ?? dsp.stereoWidth,
        stereoWidthMultiband: multiband ?? dsp.stereoWidthMultiband,
        stereoWidthLow: clampedLow ?? dsp.stereoWidthLow,
        stereoWidthMid: clampedMid ?? dsp.stereoWidthMid,
        stereoWidthHigh: clampedHigh ?? dsp.stereoWidthHigh,
        stereoWidthLowCrossoverHz:
            clampedLowCross ?? dsp.stereoWidthLowCrossoverHz,
        stereoWidthHighCrossoverHz:
            clampedHighCross ?? dsp.stereoWidthHighCrossoverHz,
      ),
      applyAudioHandler: () => _audioHandler.setStereoWidth(enabled,
          width: clampedWidth,
          multiband: multiband,
          lowWidth: clampedLow,
          midWidth: clampedMid,
          highWidth: clampedHigh,
          lowCrossoverHz: clampedLowCross,
          highCrossoverHz: clampedHighCross),
    );
  }

  Future<void> setLoudnessContour(bool enabled, {double? intensity}) {
    final clampedIntensity = intensity != null
        ? DspParamRanges.loudnessContourIntensity.clampRaw(intensity)
        : null;
    return applyDspEffect(
      featureName: 'Loudness Contour',
      guardCondition: enabled,
      updateDsp: (dsp) => dsp.copyWith(
        isLoudnessContourEnabled: enabled,
        loudnessContourIntensity:
            clampedIntensity ?? dsp.loudnessContourIntensity,
      ),
      applyAudioHandler: () => _audioHandler.setLoudnessContour(enabled,
          intensity: clampedIntensity),
    );
  }

  Future<void> setSubCrossover(bool enabled,
      {double? cornerHz,
      double? slopeDbPerOct,
      double? gain,
      bool? bassMono,
      bool? antiPop}) {
    final clampedCorner = cornerHz != null
        ? DspParamRanges.subCrossoverCornerHz.clampRaw(cornerHz)
        : null;
    final clampedGain =
        gain != null ? DspParamRanges.subCrossoverGain.clampRaw(gain) : null;
    return applyDspEffect(
      featureName: 'Sub Crossover',
      guardCondition: enabled,
      updateDsp: (dsp) => dsp.copyWith(
        isSubCrossoverEnabled: enabled,
        subCrossoverCornerHz: clampedCorner ?? dsp.subCrossoverCornerHz,
        subCrossoverSlopeDbPerOct:
            slopeDbPerOct ?? dsp.subCrossoverSlopeDbPerOct,
        subCrossoverGain: clampedGain ?? dsp.subCrossoverGain,
        subCrossoverBassMono: bassMono ?? dsp.subCrossoverBassMono,
        subCrossoverAntiPop: antiPop ?? dsp.subCrossoverAntiPop,
      ),
      applyAudioHandler: () => _audioHandler.setSubCrossover(enabled,
          cornerHz: clampedCorner,
          slopeDbPerOct: slopeDbPerOct,
          gain: clampedGain,
          bassMono: bassMono,
          antiPop: antiPop),
    );
  }

  Future<void> setDynamicEq(bool enabled) => applyDspEffect(
        featureName: 'Dynamic EQ',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(isDynamicEqEnabled: enabled),
        applyAudioHandler: () => _audioHandler.setDynamicEq(enabled),
      );

  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) {
    final current = _getState().dynamicEqBands;
    // Match EqualizerManager.setDynamicEqBand: it rejects out-of-range indices
    // (use addDynamicEqBand to append) and stores the sanitized band. Mirror
    // both here so PlayerState never diverges from the engine state.
    if (index < 0 || index >= current.length) return Future.value();
    final sanitized = band.sanitized();
    return applyDspEffect(
      featureName: 'Dynamic EQ Band',
      requiresGuard: true,
      guardCondition: _getState().isDynamicEqEnabled,
      showErrorOnGuard: false,
      // Derive the band list from the lambda's `dsp` argument, not a copy taken
      // before the await, so concurrent edits to different bands are not lost.
      updateDsp: (dsp) {
        if (index < 0 || index >= dsp.dynamicEqBands.length) return dsp;
        final bands = List<DynamicEqBandConfig>.from(dsp.dynamicEqBands);
        bands[index] = sanitized;
        return dsp.copyWith(dynamicEqBands: bands);
      },
      applyAudioHandler: () => _audioHandler.setDynamicEqBand(index, sanitized),
    );
  }

  Future<void> addDynamicEqBand() {
    if (_getState().dynamicEqBands.length >= 8) return Future.value();
    return applyDspEffect(
      featureName: 'Dynamic EQ Band',
      requiresGuard: true,
      guardCondition: _getState().isDynamicEqEnabled,
      showErrorOnGuard: false,
      updateDsp: (dsp) {
        if (dsp.dynamicEqBands.length >= 8) return dsp;
        return dsp.copyWith(
          dynamicEqBands: [
            ...dsp.dynamicEqBands,
            const DynamicEqBandConfig(),
          ],
        );
      },
      applyAudioHandler: () => _audioHandler.addDynamicEqBand(),
    );
  }

  Future<void> removeDynamicEqBand(int index) {
    final currentBands = _getState().dynamicEqBands;
    if (index < 0 || index >= currentBands.length) return Future.value();
    return applyDspEffect(
      featureName: 'Dynamic EQ Band',
      requiresGuard: true,
      guardCondition: _getState().isDynamicEqEnabled,
      showErrorOnGuard: false,
      updateDsp: (dsp) {
        if (index < 0 || index >= dsp.dynamicEqBands.length) return dsp;
        final bands = List<DynamicEqBandConfig>.from(dsp.dynamicEqBands)
          ..removeAt(index);
        return dsp.copyWith(dynamicEqBands: bands);
      },
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
        applyAudioHandler: () => _audioHandler.setLiveProg(enabled, code: code),
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
  }) {
    final clampedStrength = strength != null
        ? DspParamRanges.dynamicBassStrength.clampRaw(strength)
        : null;
    final clampedPreset =
        preset != null ? DspParamRanges.dynamicBassPreset.clamp(preset) : null;
    return applyDspEffect(
      featureName: 'Dynamic Bass',
      guardCondition: enabled,
      updateDsp: (dsp) => dsp.copyWith(
        isDynamicBassEnabled: enabled,
        dynamicBassStrength: clampedStrength ?? dsp.dynamicBassStrength,
        dynamicBassPreset: clampedPreset ?? dsp.dynamicBassPreset,
      ),
      applyAudioHandler: () => _audioHandler.setDynamicBass(
        enabled: enabled,
        strength: clampedStrength,
        preset: clampedPreset,
        xLow: xLow,
        xHigh: xHigh,
        yLow: yLow,
        yHigh: yHigh,
        sideGainLow: sideGainLow,
        sideGainHigh: sideGainHigh,
      ),
    );
  }

  List<double> mergeRoomCorrectionWithHeadphoneCurve(List<double> roomGains,
          {double maxGainDb = 15.0}) =>
      RoomCorrectionService.mergeWithHeadphoneCurve(
        roomGains,
        _getState().selectedHeadphoneProfile?.gains ?? const <double>[],
        maxGainDb: maxGainDb,
      );

  List<double> exportCorrectionImpulseResponse(
    List<double> gains, {
    List<double>? centers,
    int sampleRate = RoomCorrectionService.captureSampleRate,
    int taps = 127,
  }) =>
      RoomCorrectionService.exportCorrectionImpulseResponse(
        gains,
        centers: centers ?? EqPreset.centerFrequencies,
        sampleRate: sampleRate,
        taps: taps,
      );

  Future<void> setBypassCompare({
    required bool bypass,
    double gainCompensationDb = 0.0,
  }) =>
      _audioHandler.setBypassCompare(
        bypass: bypass,
        gainCompensationDb: gainCompensationDb,
      );
}
