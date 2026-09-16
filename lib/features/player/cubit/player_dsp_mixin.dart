part of 'player_cubit.dart';

mixin PlayerDspControls on PulsrCubit<PlayerState> {
  String? _dspBlockedReason() {
    final s = _settingsCubit?.state;
    if (s == null) return null;
    return AudioConflicts.dspBlockedByBitPerfect(
      bitPerfectOutput: s.bitPerfectOutput,
      bypassDspOnBitPerfect: s.bypassDspOnBitPerfect,
      device: s.currentOutputDevice,
    );
  }

  bool _guardDsp(String feature, {bool showError = true}) {
    final reason = _dspBlockedReason();
    if (reason != null) {
      if (showError) {
        safeEmit(state.copyWith(errorMessage: '$feature blocked: $reason'));
      }
      return false;
    }
    return true;
  }

  // Equalizer & Audio Effects
  Future<void> setEqualizerEnabled(bool enabled) async {
    if (enabled && !_guardDsp('EQ')) return;
    safeEmit(state.copyWith(isEqEnabled: enabled, errorMessage: null));
    await _audioHandler.setEqualizerEnabled(enabled);
  }

  Future<void> applyPreset(EqPreset preset, {bool isPerSongRestore = false}) async {
    if (!_guardDsp('Preset')) return;
    // Manual edits during an active per-song override must not be lost when
    // the override restores: track the user's latest choice as the backup.
    if (_perSongOverrideActive && !isPerSongRestore) {
      _globalEqBackup = preset;
      _globalHeadphoneProfileBackup = null;
    }
    safeEmit(state.copyWith(
      isEqEnabled: true,
      eqPreset: preset,
      selectedHeadphoneProfile: null,
      errorMessage: null,
    ));
    await _audioHandler.setEqualizerEnabled(true);
    await _audioHandler.applyPreset(preset);
  }

  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile,
      {bool isPerSongRestore = false}) async {
    if (profile != null && !_guardDsp('AutoEQ')) return;
    if (profile != null) {
      if (_perSongOverrideActive && !isPerSongRestore) {
        _globalEqBackup = EqPreset(
          name: profile.name,
          gains: profile.gains,
          bassBoost: profile.bassBoost,
        );
        _globalHeadphoneProfileBackup = profile;
      }
      safeEmit(state.copyWith(
        isEqEnabled: true,
        eqPreset: EqPreset(
          name: profile.name,
          gains: profile.gains,
          bassBoost: profile.bassBoost,
        ),
        selectedHeadphoneProfile: profile,
        errorMessage: null,
      ));
      await _audioHandler.setEqualizerEnabled(true);
    } else {
      safeEmit(state.copyWith(
        eqPreset: EqPreset.defaultPresets.first,
        selectedHeadphoneProfile: null,
      ));
    }
    try {
      await _audioHandler.applyHeadphoneProfile(profile);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(
          errorMessage: 'Failed to apply headphone profile: $e'));
    }
  }

  List<EqPreset> _equalizerCustomPresets() {
    // Custom user curves live as HeadphoneProfile entries; plain EqPreset
    // customs are not stored separately, so only defaults apply here.
    return const [];
  }

  Future<HeadphoneProfile?> _headphoneProfileByName(String name) async {
    try {
      final lower = name.toLowerCase();
      final repo = HeadphoneProfilesRepository();
      // The repository's profiles are empty until load() runs; without this the
      // per-song override by headphone-profile name would never resolve on a
      // fresh process.
      await repo.loadProfiles();
      for (final p in repo.profiles) {
        if (p.name.toLowerCase() == lower) return p;
      }
    } catch (_) {}
    return null;
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    if (gain.abs() > 0.1 && !_guardDsp('EQ Band')) return;
    final clamped = gain.clamp(-15.0, 15.0);
    final gains = List<double>.from(state.eqPreset.gains);
    if (bandIndex >= 0 && bandIndex < gains.length) {
      final hadProfile = state.selectedHeadphoneProfile != null;
      gains[bandIndex] = clamped;
      safeEmit(state.copyWith(
        eqPreset: EqPreset(
          name: 'Custom',
          gains: gains,
          bassBoost: hadProfile ? 0.0 : state.eqPreset.bassBoost,
        ),
        selectedHeadphoneProfile: null,
      ));
    }
    try {
      await _audioHandler.setBandGain(bandIndex, clamped);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set band gain: $e'));
    }
  }

  Future<void> resetToFlat() async {
    safeEmit(state.copyWith(
      eqPreset: EqPreset.defaultPresets.first,
      selectedHeadphoneProfile: null,
    ));
    try {
      await _audioHandler.resetToFlat();
    } catch (e) {
      _syncAudioEffects();
    }
  }

  Future<void> startAbComparison() async {
    await _audioHandler.startAbComparison();
  }

  Future<void> endAbComparison() async {
    await _audioHandler.endAbComparison();
  }

  Future<void> setBassBoost(double amount) async {
    if (amount > 0.01 && !_guardDsp('Bass Boost')) return;
    final clamped = amount.clamp(0.0, 1.0);
    safeEmit(state.copyWith(
      eqPreset: EqPreset(
          name: state.eqPreset.name,
          gains: state.eqPreset.gains,
          bassBoost: clamped),
      errorMessage: null,
    ));
    try {
      await _audioHandler.setBassBoost(clamped);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set bass boost: $e'));
    }
  }

  /// Switches the active EQ band plan to [count] (10, 32 or 64). 10/32 keep the
  /// legacy handler passthrough; 64 goes straight to the manager (the handler's
  /// passthrough only speaks the legacy 10/32 split).
  Future<void> setBandMode(int count) async {
    if (count == 10 || count == 32) {
      await _audioHandler.set32BandMode(count == 32);
    } else if (count == 64) {
      await _audioHandler.equalizerManager.setBandMode(64);
    } else {
      return;
    }
    safeEmit(state.copyWith(
      eqPreset: _audioHandler.currentPreset,
    ));
  }

  Future<void> switchComparisonSlot(ComparisonSlot slot) async {
    await _audioHandler.switchComparisonSlot(slot);
    safeEmit(state.copyWith(
      eqPreset: _audioHandler.currentPreset,
    ));
  }

  String exportPresetToJson() => _audioHandler.exportPresetToJson();

  Future<bool> importPresetFromJson(String jsonStr) async {
    final ok = await _audioHandler.importPresetFromJson(jsonStr);
    if (ok) {
      safeEmit(state.copyWith(
        eqPreset: _audioHandler.currentPreset,
      ));
    }
    return ok;
  }

  /// F-37: merge a fitted room-correction curve with the currently selected
  /// AutoEQ headphone profile (band-wise, clamped). Returns [roomGains]
  /// unchanged (clamped) when no profile is selected. Thin passthrough to
  /// [RoomCorrectionService.mergeWithHeadphoneCurve] for the room-correction
  /// wizard's "stack with headphone" option.
  List<double> mergeRoomCorrectionWithHeadphoneCurve(
    List<double> roomGains, {
    double maxGainDb = 15.0,
  }) {
    final profile = state.selectedHeadphoneProfile;
    return RoomCorrectionService.mergeWithHeadphoneCurve(
      roomGains,
      profile?.gains ?? const <double>[],
      maxGainDb: maxGainDb,
    );
  }

  /// F-37: design a linear-phase FIR impulse response from a correction curve
  /// for the native convolution stage. Thin passthrough to
  /// [RoomCorrectionService.exportCorrectionImpulseResponse].
  List<double> exportCorrectionImpulseResponse(
    List<double> gains, {
    List<double>? centers,
    int sampleRate = RoomCorrectionService.captureSampleRate,
    int taps = 127,
  }) {
    return RoomCorrectionService.exportCorrectionImpulseResponse(
      gains,
      centers: centers ?? EqPreset.centerFrequencies,
      sampleRate: sampleRate,
      taps: taps,
    );
  }

  Future<void> setVirtualizerEnabled(bool enabled) async {
    if (enabled && !_guardDsp('Virtualizer')) return;
    safeEmit(state.copyWith(isVirtualizerEnabled: enabled, errorMessage: null));
    try {
      await _audioHandler.setVirtualizerEnabled(enabled);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set virtualizer: $e'));
    }
  }

  Future<void> setVirtualizerStrength(double strength) async {
    if (!_guardDsp('Virtualizer', showError: false)) return;
    safeEmit(state.copyWith(virtualizerStrength: strength));
    try {
      await _audioHandler.setVirtualizerStrength(strength);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(
          errorMessage: 'Failed to set virtualizer strength: $e'));
    }
  }

  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) async {
    final isEnabled = enabled ?? (preset != DynamicsPreset.off);
    if (isEnabled && !_guardDsp('Dynamics')) return;
    safeEmit(state.copyWith(
      dynamicsPreset: preset,
      isDynamicsEnabled: isEnabled,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setDynamicsPreset(preset, enabled: enabled);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set dynamics preset: $e'));
    }
  }

  Future<void> toggleDynamicsBypass() async {
    await _audioHandler.toggleDynamicsBypass();
    safeEmit(state.copyWith(
      isDynamicsEnabled: !_audioHandler.isDynamicsBypassed &&
          state.dynamicsPreset != DynamicsPreset.off,
    ));
  }

  Future<void> setDspEffectsEnabled(bool enabled) async {
    if (enabled && !_guardDsp('DSP Engine')) return;
    try {
      if (!enabled) {
        if (state.isDspEffectsActive) {
          _dspSnapshot = state;
        }
        // The Equalizer master switch is intentionally NOT touched here: the
        // DSP-effects switch owns only the spatial/dynamics/reverb stages, so
        // the two switches stay independent.
        safeEmit(state.copyWith(
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
          isDynamicBassEnabled: false,
          volumeBoost: 0.0,
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
        await _audioHandler.setDynamicBass(enabled: false);
        await _audioHandler.setVolumeBoost(0.0);
      } else {
        final snap = _dspSnapshot;
        if (snap != null && snap.isDspEffectsActive) {
          safeEmit(state.copyWith(
            isSpatializerEnabled: snap.isSpatializerEnabled,
            isVirtualizerEnabled: snap.isVirtualizerEnabled,
            virtualizerStrength: snap.virtualizerStrength,
            isDynamicsEnabled: snap.isDynamicsEnabled,
            dynamicsPreset: snap.dynamicsPreset,
            isCrossfeedEnabled: snap.isCrossfeedEnabled,
            crossfeedDelayUs: snap.crossfeedDelayUs,
            crossfeedFeedDb: snap.crossfeedFeedDb,
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
            isStereoWidthEnabled: snap.isStereoWidthEnabled,
            stereoWidth: snap.stereoWidth,
            isLoudnessContourEnabled: snap.isLoudnessContourEnabled,
            loudnessContourIntensity: snap.loudnessContourIntensity,
            isSubCrossoverEnabled: snap.isSubCrossoverEnabled,
            subCrossoverCornerHz: snap.subCrossoverCornerHz,
            subCrossoverSlopeDbPerOct: snap.subCrossoverSlopeDbPerOct,
            subCrossoverGain: snap.subCrossoverGain,
            isDynamicEqEnabled: snap.isDynamicEqEnabled,
            dynamicEqBands: snap.dynamicEqBands,
            isDynamicBassEnabled: snap.isDynamicBassEnabled,
            dynamicBassStrength: snap.dynamicBassStrength,
            dynamicBassPreset: snap.dynamicBassPreset,
            volumeBoost: snap.volumeBoost,
          ));
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
                delayUs: snap.crossfeedDelayUs, feedDb: snap.crossfeedFeedDb);
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
          // Default baseline DSP activation when no previous snapshot exists:
          final enableSpatial = state.isSpatializerSupported;
          final enableVirt = !enableSpatial && state.isVirtualizerSupported;
          safeEmit(state.copyWith(
            isSpatializerEnabled: enableSpatial,
            isVirtualizerEnabled: enableVirt,
            virtualizerStrength: enableVirt ? 0.35 : state.virtualizerStrength,
            isLimiterEnabled: true,
            limiterThresholdDb: -0.2,
            limiterReleaseMs: 50.0,
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
      safeEmit(
          state.copyWith(errorMessage: 'Failed to update DSP effects: $e'));
    }
  }

  Future<void> setVolumeBoost(double value) async {
    if (value > 0.01 && !_guardDsp('Volume Boost')) return;
    // Gain staging: cap if combined with preamp > 6 dB
    final preampDb = state.selectedHeadphoneProfile?.preampGain ?? 0.0;
    var safeValue = value.clamp(0.0, 1.0);
    if ((preampDb + safeValue * 10.0) > 6.0) {
      safeValue = ((6.0 - preampDb) / 10.0).clamp(0.0, 1.0);
    }
    safeEmit(state.copyWith(volumeBoost: safeValue, errorMessage: null));
    try {
      await _audioHandler.setVolumeBoost(safeValue);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set volume boost: $e'));
    }
  }

  Future<void> setSpatializerEnabled(bool enabled) async {
    if (enabled && !_guardDsp('Spatializer')) return;
    safeEmit(state.copyWith(isSpatializerEnabled: enabled, errorMessage: null));
    try {
      await _audioHandler.setSpatializerEnabled(enabled);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set spatializer: $e'));
    }
  }

  Future<void> setCrossfeed(bool enabled,
      {double? delayUs, double? feedDb, int? mode}) async {
    if (enabled && !_guardDsp('Crossfeed')) return;
    safeEmit(state.copyWith(
      isCrossfeedEnabled: enabled,
      crossfeedDelayUs: delayUs ?? state.crossfeedDelayUs,
      crossfeedFeedDb: feedDb ?? state.crossfeedFeedDb,
      crossfeedMode: mode ?? state.crossfeedMode,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setCrossfeed(enabled,
          delayUs: delayUs, feedDb: feedDb, mode: mode);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set crossfeed: $e'));
    }
  }

  Future<void> setCrossfeedMode(int mode) async {
    safeEmit(state.copyWith(crossfeedMode: mode));
    try {
      await _audioHandler.setCrossfeedMode(mode);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set crossfeed mode: $e'));
    }
  }

  Future<void> setLookaheadLimiter(bool enabled,
      {double? thresholdDb, double? releaseMs, double? lookaheadMs}) async {
    if (enabled && !_guardDsp('Limiter')) return;
    safeEmit(state.copyWith(
      isLimiterEnabled: enabled,
      limiterThresholdDb: thresholdDb ?? state.limiterThresholdDb,
      limiterReleaseMs: releaseMs ?? state.limiterReleaseMs,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setLookaheadLimiter(enabled,
          thresholdDb: thresholdDb,
          releaseMs: releaseMs,
          lookaheadMs: lookaheadMs);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set limiter: $e'));
    }
  }

  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) async {
    if (enabled && !_guardDsp('Reverb')) return;
    safeEmit(state.copyWith(
      isReverbEnabled: enabled,
      reverbPreset: preset ?? state.reverbPreset,
      reverbWetDry: wetDry ?? state.reverbWetDry,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setReverb(enabled, preset: preset, wetDry: wetDry);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set reverb: $e'));
    }
  }

  /// Loads a custom reverb impulse response. Returns true only when the native
  /// side accepted it; on failure the UI is NOT flipped to "Custom (Loaded)".
  Future<bool> loadCustomImpulseResponse(List<double> irSamples) async {
    if (!_guardDsp('Reverb IR')) return false;
    try {
      final loaded = await _audioHandler.loadCustomImpulseResponse(irSamples);
      if (!loaded) {
        _syncAudioEffects();
        safeEmit(state.copyWith(
            errorMessage: 'Impulse response rejected by the audio engine'));
        return false;
      }
      if (!isClosed) {
        safeEmit(state.copyWith(
          isReverbEnabled: true,
          reverbPreset: ReverbPreset.custom.wireValue,
          errorMessage: null,
        ));
      }
      return true;
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to load impulse response: $e'));
      return false;
    }
  }

  Future<void> pickAndLoadCustomIrFile() async {
    if (!_guardDsp('Reverb IR')) return;
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['wav'],
      );
      if (result != null && result.path != null) {
        final path = result.path!;
        final samples = await IrFileParser.parseWavFile(File(path));
        // Persist the path only after the engine actually accepted the IR,
        // otherwise a failed load would be restored as "custom" with no IR.
        if (await loadCustomImpulseResponse(samples)) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(PrefsKeys.customReverbIrPath, path);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to pick/load custom IR file',
          error: e, stackTrace: st, category: 'Reverb');
      safeEmit(state.copyWith(errorMessage: 'Failed to load IR WAV file: $e'));
    }
  }

  Future<void> setStereoBalance(double balance) async {
    if (balance.abs() > 0.01 &&
        !_guardDsp('Stereo Balance', showError: false)) {
      return;
    }
    final clamped = balance.clamp(-1.0, 1.0);
    safeEmit(state.copyWith(stereoBalance: clamped));
    try {
      await _audioHandler.setStereoBalance(clamped);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set stereo balance: $e'));
    }
  }

  Future<void> setMonoMix(bool mono) async {
    if (mono && !_guardDsp('Mono Mix')) return;
    safeEmit(state.copyWith(monoMix: mono, errorMessage: null));
    try {
      await _audioHandler.setMonoMix(mono);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set mono mix: $e'));
    }
  }

  Future<void> setSincResampler(bool enabled) async {
    if (enabled && !_guardDsp('Resampler', showError: false)) return;
    safeEmit(state.copyWith(isSincResamplerEnabled: enabled));
    try {
      await _audioHandler.setSincResampler(enabled);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set resampler: $e'));
    }
  }

  Future<void> setDither(bool enabled, {int? targetBitDepth}) async {
    if (enabled && !_guardDsp('Dither', showError: false)) return;
    if (targetBitDepth != null &&
        targetBitDepth != 16 &&
        targetBitDepth != 24 &&
        targetBitDepth != 32) {
      return;
    }
    safeEmit(state.copyWith(
      isDitherEnabled: enabled,
      ditherTargetBitDepth: targetBitDepth ?? state.ditherTargetBitDepth,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setDither(enabled, targetBitDepth: targetBitDepth);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set dither: $e'));
    }
  }

  Future<void> setSaturation(bool enabled,
      {double? drive,
      double? mix,
      double? tilt,
      int? mode,
      bool? multiband}) async {
    if (enabled && !_guardDsp('Harmonic Saturation')) return;
    safeEmit(state.copyWith(
      isSaturationEnabled: enabled,
      saturationDrive: drive ?? state.saturationDrive,
      saturationMix: mix ?? state.saturationMix,
      saturationTilt: tilt ?? state.saturationTilt,
      saturationMultiband: multiband ?? state.saturationMultiband,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setSaturation(enabled,
          drive: drive, mix: mix, tilt: tilt, mode: mode, multiband: multiband);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set saturation: $e'));
    }
  }

  Future<void> setSaturationMultiband(bool multiband) async {
    safeEmit(state.copyWith(saturationMultiband: multiband));
    try {
      await _audioHandler.setSaturationMultiband(multiband);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(
          errorMessage: 'Failed to set saturation multiband: $e'));
    }
  }

  Future<void> setStereoWidth(bool enabled,
      {double? width,
      bool? multiband,
      double? lowWidth,
      double? midWidth,
      double? highWidth,
      double? lowCrossoverHz,
      double? highCrossoverHz}) async {
    if (enabled && !_guardDsp('Stereo Width')) return;
    safeEmit(state.copyWith(
      isStereoWidthEnabled: enabled,
      stereoWidth: width ?? state.stereoWidth,
      stereoWidthMultiband: multiband ?? state.stereoWidthMultiband,
      stereoWidthLow: lowWidth ?? state.stereoWidthLow,
      stereoWidthMid: midWidth ?? state.stereoWidthMid,
      stereoWidthHigh: highWidth ?? state.stereoWidthHigh,
      stereoWidthLowCrossoverHz:
          lowCrossoverHz ?? state.stereoWidthLowCrossoverHz,
      stereoWidthHighCrossoverHz:
          highCrossoverHz ?? state.stereoWidthHighCrossoverHz,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setStereoWidth(enabled,
          width: width,
          multiband: multiband,
          lowWidth: lowWidth,
          midWidth: midWidth,
          highWidth: highWidth,
          lowCrossoverHz: lowCrossoverHz,
          highCrossoverHz: highCrossoverHz);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set stereo width: $e'));
    }
  }

  Future<void> setLoudnessContour(bool enabled, {double? intensity}) async {
    if (enabled && !_guardDsp('Loudness Contour')) return;
    safeEmit(state.copyWith(
      isLoudnessContourEnabled: enabled,
      loudnessContourIntensity: intensity ?? state.loudnessContourIntensity,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setLoudnessContour(enabled, intensity: intensity);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set loudness contour: $e'));
    }
  }

  Future<void> setSubCrossover(bool enabled,
      {double? cornerHz,
      double? slopeDbPerOct,
      double? gain,
      bool? bassMono,
      bool? antiPop}) async {
    if (enabled && !_guardDsp('Sub Crossover')) return;
    safeEmit(state.copyWith(
      isSubCrossoverEnabled: enabled,
      subCrossoverCornerHz: cornerHz ?? state.subCrossoverCornerHz,
      subCrossoverSlopeDbPerOct:
          slopeDbPerOct ?? state.subCrossoverSlopeDbPerOct,
      subCrossoverGain: gain ?? state.subCrossoverGain,
      subCrossoverBassMono: bassMono ?? state.subCrossoverBassMono,
      subCrossoverAntiPop: antiPop ?? state.subCrossoverAntiPop,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setSubCrossover(enabled,
          cornerHz: cornerHz,
          slopeDbPerOct: slopeDbPerOct,
          gain: gain,
          bassMono: bassMono,
          antiPop: antiPop);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set sub crossover: $e'));
    }
  }

  Future<void> setDynamicEq(bool enabled) async {
    if (enabled && !_guardDsp('Dynamic EQ')) return;
    safeEmit(state.copyWith(
      isDynamicEqEnabled: enabled,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setDynamicEq(enabled);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set dynamic EQ: $e'));
    }
  }

  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) async {
    var bands = List<DynamicEqBandConfig>.from(state.dynamicEqBands);
    // Seed with neutral defaults if the state list has not been synced yet
    while (bands.length <= index) {
      bands.add(const DynamicEqBandConfig());
    }
    bands[index] = band;
    safeEmit(state.copyWith(dynamicEqBands: bands));
    try {
      await _audioHandler.setDynamicEqBand(index, band);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set dynamic EQ band: $e'));
    }
  }

  Future<void> addDynamicEqBand() async {
    if (state.dynamicEqBands.length >= 8) return;
    var bands = List<DynamicEqBandConfig>.from(state.dynamicEqBands);
    bands.add(const DynamicEqBandConfig());
    safeEmit(state.copyWith(dynamicEqBands: bands));
    try {
      await _audioHandler.addDynamicEqBand();
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to add dynamic EQ band: $e'));
    }
  }

  Future<void> removeDynamicEqBand(int index) async {
    if (index < 0 || index >= state.dynamicEqBands.length) return;
    var bands = List<DynamicEqBandConfig>.from(state.dynamicEqBands);
    bands.removeAt(index);
    safeEmit(state.copyWith(dynamicEqBands: bands));
    try {
      await _audioHandler.removeDynamicEqBand(index);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to remove dynamic EQ band: $e'));
    }
  }

  Future<void> setViperDdcEnabled(bool enabled,
      {String? profileName, List<double>? coeffs}) async {
    if (enabled && !_guardDsp('ViPER-DDC')) return;
    safeEmit(state.copyWith(
      isViperDdcEnabled: enabled,
      viperDdcProfileName: profileName ?? state.viperDdcProfileName,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setViperDdc(enabled,
          profileName: profileName, coeffs: coeffs);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set ViPER-DDC: $e'));
    }
  }

  bool get isArbitraryEqLinearPhase => _audioHandler.arbitraryEqLinearPhase;

  Future<void> setArbitraryEqEnabled(bool enabled,
      {String? eqString, bool? linearPhase}) async {
    if (enabled && !_guardDsp('Arbitrary Response EQ')) return;
    safeEmit(state.copyWith(
      isArbitraryEqEnabled: enabled,
      arbitraryEqString: eqString ?? state.arbitraryEqString,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setArbitraryEq(enabled,
          eqString: eqString, linearPhase: linearPhase);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set Arbitrary EQ: $e'));
    }
  }

  Future<void> setLiveProgEnabled(bool enabled, {String? code}) async {
    if (enabled && !_guardDsp('Live Programmable DSP')) return;
    safeEmit(state.copyWith(
      isLiveProgEnabled: enabled,
      liveProgCode: code ?? state.liveProgCode,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setLiveProg(enabled, code: code);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set LiveProg DSP: $e'));
    }
  }

  Future<void> setLiveProgSlider(int sliderIndex, double value) async {
    try {
      await _audioHandler.setLiveProgSlider(sliderIndex, value);
    } catch (e) {
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set LiveProg slider: $e'));
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
  }) async {
    if (enabled && !_guardDsp('Dynamic Bass')) return;
    safeEmit(state.copyWith(
      isDynamicBassEnabled: enabled,
      dynamicBassStrength: strength ?? state.dynamicBassStrength,
      dynamicBassPreset: preset ?? state.dynamicBassPreset,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setDynamicBass(
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
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set Dynamic Bass: $e'));
    }
  }

  void _startDeviceProfileWatcher() {
    final service = _deviceProfileService;
    final hiRes = _hiResAudioService;
    if (service == null || hiRes == null) return;
    autoSub(hiRes.outputDeviceStream, (device) {
      _onOutputDeviceChanged(device);
    });
  }

  Future<void> _onOutputDeviceChanged(AudioOutputInfo device) async {
    final service = _deviceProfileService;
    final profilesService = _settingsProfilesService;
    if (service == null || profilesService == null || isClosed) return;
    try {
      final key = DeviceProfileService.deviceKeyFromInfo(device);
      await service.rememberDevice(key, device.deviceName);
      // De-dup: the output stream also fires on format changes (sample rate,
      // bit depth) for the same device; only switch when the device changes.
      if (_lastAutoAppliedDeviceKey == key) return;

      final smart = _smartAudioService;
      final smartEnabled = smart != null && await smart.isEnabled();

      // 1) An explicit user device->profile link always wins over auto-match.
      if (await service.isAutoSwitchEnabled()) {
        final link = await service.linkForDeviceKey(key);
        if (link != null) {
          final profiles = await profilesService.getProfiles();
          SettingsProfile? profile;
          for (final p in profiles) {
            if (p.id == link.profileId) {
              profile = p;
              break;
            }
          }
          if (profile != null) {
            // Claim the key before applying: applyProfile awaits a long chain,
            // and a second stream event for the same device would otherwise
            // pass this gate and run a concurrent apply.
            _lastAutoAppliedDeviceKey = key;
            final applied = await applyProfile(profile);
            if (!applied && !isClosed) {
              // applyProfile reports failure instead of throwing, so release
              // the claim here or a later event for this device never retries.
              _lastAutoAppliedDeviceKey = null;
            }
            return;
          }
        }
      }

      // 2) Smart Auto: match the connected headphone to an AutoEQ profile and
      // arbitrate the best output quality for this route.
      if (smartEnabled) {
        final matched = await _applySmartAutoEq(smart, key, device);
        await _applySmartQuality(device, matched?.id);
      }
    } catch (e, st) {
      ErrorLogger.log('Device profile auto-switch failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  /// Smart Auto path: apply the remembered (or freshly detected) AutoEQ profile
  /// for [device]. A per-device saved match wins so the same headset is always
  /// corrected identically; otherwise a fuzzy match is computed and persisted.
  /// Returns the applied profile (or null when nothing matched).
  Future<HeadphoneProfile?> _applySmartAutoEq(
    SmartAudioService smart,
    String key,
    AudioOutputInfo device,
  ) async {
    try {
      final repo = HeadphoneProfilesRepository();
      await repo.loadProfiles();
      if (isClosed || repo.profiles.isEmpty) return null;

      HeadphoneProfile? profile;
      final saved = await smart.linkForDeviceKey(key);
      if (saved != null) {
        profile = repo.getProfileById(saved.profileId);
      }
      if (profile == null) {
        final match = HeadphoneDeviceMatcher.match(
          deviceName: device.deviceName,
          profiles: repo.profiles,
        );
        profile = match?.profile;
        if (profile == null) return null;
        // Persist the freshly detected association so reconnects skip matching.
        await smart.rememberAutoEqLink(
          deviceKey: key,
          deviceLabel: device.deviceName,
          profileId: profile.id,
          score: match!.score,
        );
      }

      if (isClosed) return null;
      _lastAutoAppliedDeviceKey = key;
      await applyHeadphoneProfile(profile);
      return profile;
    } catch (e, st) {
      ErrorLogger.log('Smart Auto AutoEQ match failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      return null;
    }
  }

  /// Smart Auto quality arbitration: hand the route to the bit-perfect/hi-res
  /// path when it is the best available and no correction is requested, else
  /// keep the DSP path. Only toggles bit-perfect that Smart Auto itself turned
  /// on, so an explicit user choice is never overridden.
  Future<void> _applySmartQuality(
    AudioOutputInfo device,
    String? matchedProfileId,
  ) async {
    final settings = _settingsCubit;
    if (settings == null || isClosed) return;
    final song = state.currentSong;
    final plan = resolveSmartAudioPlan(
      mode: SmartAudioMode.auto,
      device: device,
      matchedHeadphoneProfileId: matchedProfileId,
      trackIsHiRes: smartAudioTrackIsHiRes(
        sampleRate: song?.sampleRate ?? 0,
        bitDepth: song?.bitDepth ?? 0,
      ),
      deviceSupportsBitPerfect: device.isBitPerfectSupported,
    );
    try {
      if (plan.preferBitPerfect) {
        if (!settings.state.bitPerfectOutput) {
          _smartAutoBitPerfectApplied = true;
          await settings.setBitPerfectOutput(true);
        }
      } else if (_smartAutoBitPerfectApplied) {
        _smartAutoBitPerfectApplied = false;
        if (settings.state.bitPerfectOutput) {
          await settings.setBitPerfectOutput(false);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Smart Audio quality arbitration failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  /// Applies a settings profile through the cubit's guarded setters so
  /// handler, persisted prefs and UI state stay consistent. Order matters:
  /// DSP stages are applied BEFORE bit-perfect so its bypass conflict rules
  /// evaluate against the pre-switch state, and bit-perfect is re-asserted
  /// last (its bypass then zeroes stages per the saved policy).
  Future<bool> applyProfile(SettingsProfile profile,
      {bool manual = false}) async {
    try {
      EqPreset preset = EqPreset.defaultPresets.first;
      for (final p in EqPreset.defaultPresets) {
        if (p.name == profile.eqPresetName) {
          preset = p;
          break;
        }
      }
      await setEqualizerEnabled(true);
      await applyPreset(preset);
      await setVolumeBoost(profile.volumeBoost);
      if (profile.saturationEnabled != null) {
        await setSaturation(profile.saturationEnabled!);
      }
      if (profile.stereoWidthEnabled != null) {
        await setStereoWidth(profile.stereoWidthEnabled!);
      }
      if (profile.loudnessContourEnabled != null) {
        await setLoudnessContour(profile.loudnessContourEnabled!);
      }
      if (profile.subCrossoverEnabled != null) {
        await setSubCrossover(profile.subCrossoverEnabled!);
      }
      if (profile.dynamicEqEnabled != null) {
        await setDynamicEq(profile.dynamicEqEnabled!);
      }
      if (profile.crossfeedEnabled != null) {
        await setCrossfeed(
          profile.crossfeedEnabled!,
          delayUs: profile.crossfeedDelayUs,
          feedDb: profile.crossfeedFeedDb,
        );
      }
      if (profile.headphoneProfileId != null) {
        final repo = HeadphoneProfilesRepository();
        await repo.loadProfiles();
        final hpProfile = repo.getProfileById(profile.headphoneProfileId!);
        await applyHeadphoneProfile(hpProfile);
      }
      final settings = _settingsCubit;
      if (settings != null) {
        await settings.setCrossfade(
            profile.crossfadeEnabled ? profile.crossfadeSeconds : 0.0);
        await settings.setBitPerfectOutput(profile.bitPerfectEnabled);
      }
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to apply settings profile',
          error: e, stackTrace: st, category: 'PlayerCubit');
      return false;
    }
  }
















































































  // Requires: provided by the composing class (same library).
  PulsrAudioHandler get _audioHandler;

  // Requires: provided by the composing class (same library).
  DeviceProfileService? get _deviceProfileService;

  // Requires: provided by the composing class (same library).
  PlayerState? get _dspSnapshot;
  set _dspSnapshot(PlayerState? value);



  // Requires: provided by the composing class (same library).
  // ignore: unused_element
  EqPreset? get _globalEqBackup;
  set _globalEqBackup(EqPreset? value);

  // Requires: provided by the composing class (same library).
  // ignore: unused_element
  HeadphoneProfile? get _globalHeadphoneProfileBackup;
  set _globalHeadphoneProfileBackup(HeadphoneProfile? value);

  // Requires: provided by the composing class (same library).
  HiResAudioService? get _hiResAudioService;

  // Requires: provided by the composing class (same library).
  String? get _lastAutoAppliedDeviceKey;
  set _lastAutoAppliedDeviceKey(String? value);

  // Requires: provided by the composing class (same library).
  bool get _perSongOverrideActive;

  // Requires: provided by the composing class (same library).
  SettingsCubit? get _settingsCubit;

  // Requires: provided by the composing class (same library).
  SettingsProfilesService? get _settingsProfilesService;

  // Requires: provided by the composing class (same library).
  SmartAudioService? get _smartAudioService;

  // Requires: provided by the composing class (same library).
  bool get _smartAutoBitPerfectApplied;
  set _smartAutoBitPerfectApplied(bool value);

  // Requires: provided by the composing class (same library).
  void _syncAudioEffects();
}
