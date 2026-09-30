// lib/data/audio/equalizer_effect_ops.dart
part of 'equalizer_manager.dart';

/// Virtualizer, dynamics, spatializer, crossfeed, compressor, impulse-response,
/// stereo-balance/mono and sinc-resampler setters. Extracted from
/// [EqualizerManager] (fat-file ratchet 01-4). Same library via `part of`, so
/// private state stays accessible and all call sites keep working.
extension EqualizerEffectOps on EqualizerManager {
  Future<void> setVirtualizerEnabled(bool enabled) async {
    // FIX M-9: skip no-op IPC when virtualizer is not supported
    if (!_effectsChannel.isVirtualizerSupported) return;
    
    final previous = isVirtualizerEnabled;
    isVirtualizerEnabled = enabled;
    try {
      final applied = await _effectsChannel.setVirtualizerEnabled(enabled);
      if (enabled) {
        _recordEffectOutcome('virtualizer', applied);
        // Never leave the toggle ON when the engine rejected the request.
        if (!applied) isVirtualizerEnabled = previous;
      } else {
        _recordEffectOutcome('virtualizer', true);
      }
      await _savePreferences();
    } catch (e, st) {
      isVirtualizerEnabled = previous;
      _recordEffectOutcome('virtualizer', false);
      ErrorLogger.log(
        'Failed to set virtualizer enabled',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
  }

  Future<void> setVirtualizerStrength(double strength) async {
    // FIX M-9: skip no-op IPC when virtualizer is not supported
    if (!_effectsChannel.isVirtualizerSupported) return;
    
    virtualizerStrength = strength.clamp(0.0, 1.0);
    final applied = await _effectsChannel.setVirtualizerStrength(
      virtualizerStrength,
    );
    _recordEffectOutcome('virtualizer', applied || virtualizerStrength <= 0.0);
    await _savePreferences();
  }

  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) async {
    dynamicsPreset = preset;
    if (enabled != null) {
      isDynamicsEnabled = enabled;
    } else if (preset == DynamicsPreset.off) {
      isDynamicsEnabled = false;
    } else {
      isDynamicsEnabled = true;
    }
    if (!_isDynamicsBypassed) {
      final applied = await _effectsChannel.setDynamicsPreset(
        dynamicsPreset,
        isDynamicsEnabled,
      );
      final wantsDynamics = isDynamicsEnabled && preset != DynamicsPreset.off;
      // A rejected "off" still reaches the desired disabled state; only an
      // enabled-but-rejected preset is a genuine "not applied".
      _recordEffectOutcome('dynamics', applied || !wantsDynamics);
    }
    await _savePreferences();
  }

  Future<void> toggleDynamicsBypass() async {
    _isDynamicsBypassed = !_isDynamicsBypassed;
    if (_isDynamicsBypassed) {
      await _effectsChannel.setDynamicsPreset(DynamicsPreset.off, false);
    } else {
      await _effectsChannel.setDynamicsPreset(
        dynamicsPreset,
        isDynamicsEnabled,
      );
    }
    await _savePreferences();
  }

  bool get isSpatializerSupported => _effectsChannel.isSpatializerSupported;
  bool get isHeadTrackerAvailable => _effectsChannel.isHeadTrackerAvailable;

  /// Applies the spatializer enable flag, then falls back to the hardware
  /// virtualizer when the device has no Spatializer API. Uses the channel
  /// directly (never [_savePreferences]) so it is safe to call from within
  /// [_restorePreferences] while [_effectsLock] is held, and from the public
  /// setter, restore and reattach paths alike.
  Future<bool> _applySpatializerWithFallback(bool enabled) async {
    final applied = await _effectsChannel.setSpatializerEnabled(enabled);
    if (enabled && !_effectsChannel.isSpatializerSupported) {
      if (!isVirtualizerEnabled) {
        isVirtualizerEnabled = true;
        _recordEffectOutcome(
          'virtualizer',
          await _effectsChannel.setVirtualizerEnabled(true),
        );
        if (virtualizerStrength < 0.3) {
          virtualizerStrength = 0.7;
          _recordEffectOutcome(
            'virtualizer',
            await _effectsChannel.setVirtualizerStrength(virtualizerStrength),
          );
        }
      }
    }
    return applied;
  }

  Future<void> setSpatializerEnabled(bool enabled) async {
    final previous = isSpatializerEnabled;
    isSpatializerEnabled = enabled;
    try {
      final applied = await _applySpatializerWithFallback(enabled);
      if (enabled) {
        _recordEffectOutcome('spatializer', applied);
        if (!applied) isSpatializerEnabled = previous;
      } else {
        _recordEffectOutcome('spatializer', true);
      }
      await _savePreferences();
    } catch (e, st) {
      isSpatializerEnabled = previous;
      _recordEffectOutcome('spatializer', false);
      ErrorLogger.log(
        'Failed to set spatializer enabled',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
  }

  bool get hasOemAudio => _effectsChannel.hasOemAudio;
  List<String> get detectedOemEngines => _effectsChannel.detectedOemEngines;

  Future<void> setCrossfeed(
    bool enabled, {
    double? delayUs,
    double? feedDb,
    double? fcut,
    int? mode,
  }) async {
    isCrossfeedEnabled = enabled;
    if (delayUs != null) {
      crossfeedDelayUs = delayUs.clamp(200.0, 700.0);
    }
    if (feedDb != null) {
      crossfeedFeedDb = feedDb.clamp(-15.0, -6.0);
    }
    if (fcut != null) {
      crossfeedFcut = fcut.clamp(200.0, 2000.0);
    }
    if (mode != null) crossfeedMode = mode.clamp(0, 3);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setCrossfeedParams(
        crossfeedDelayUs,
        crossfeedFeedDb,
        fcut: crossfeedFcut,
      );
      await _effectsChannel.setCrossfeedMode(crossfeedMode);
      await _effectsChannel.setCrossfeedEnabled(enabled);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setCrossfeedMode(int mode) async {
    crossfeedMode = mode.clamp(0, 3);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setCrossfeedMode(crossfeedMode);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setLookaheadLimiter(
    bool enabled, {
    double? thresholdDb,
    double? releaseMs,
    double? lookaheadMs,
  }) async {
    isLimiterEnabled = enabled;
    if (thresholdDb != null) limiterThresholdDb = thresholdDb;
    if (releaseMs != null) limiterReleaseMs = releaseMs;
    if (lookaheadMs != null) limiterLookaheadMs = lookaheadMs;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setLimiterParams(
        limiterLookaheadMs,
        limiterThresholdDb,
        limiterReleaseMs,
      );
      await _effectsChannel.setLimiterEnabled(enabled);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setCompressorParams({
    double? thresholdDb,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? makeupGainDb,
  }) async {
    if (thresholdDb != null) limiterThresholdDb = thresholdDb;
    if (ratio != null) compressorRatio = ratio;
    if (attackMs != null) compressorAttackMs = attackMs;
    if (releaseMs != null) limiterReleaseMs = releaseMs;
    if (makeupGainDb != null) compressorMakeupGainDb = makeupGainDb;

    // Any explicit edit marks the compressor knobs as user-owned so restore
    // and reattach keep forwarding them to the HAL.
    _hasStoredCompressorParams = true;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setLimiterParams(
        limiterLookaheadMs,
        limiterThresholdDb,
        limiterReleaseMs,
        ratio: compressorRatio,
        attackMs: compressorAttackMs,
        makeupGainDb: compressorMakeupGainDb,
      );
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setReverb(
    bool enabled, {
    int? preset,
    double? wetDry,
    double? predelayMs,
    double? damping,
  }) async {
    isReverbEnabled = enabled;
    if (preset != null) {
      // Wire values are ReverbPreset ordinals (0..N); anything else has no
      // synthesizable IR on the native side, so clamp instead of forwarding
      // garbage that would silently produce the wrong room.
      reverbPreset =
          preset.clamp(0, ReverbPreset.values.length - 1);
    }
    if (wetDry != null) reverbWetDry = wetDry.clamp(0.0, 1.0);
    if (predelayMs != null) reverbPredelayMs = predelayMs.clamp(0.0, 150.0);
    if (damping != null) reverbDamping = damping.clamp(0.0, 1.0);
    if (PlatformCapabilities.isAndroid) {
      // Forward the clamped field, not the raw argument, so an out-of-range
      // ordinal never reaches native and produce the wrong room (see clamp above).
      if (preset != null) await _effectsChannel.setReverbPreset(reverbPreset);
      // FIX M-7: always sync wet/dry after preset change so DSP is not stale
      await _effectsChannel.setReverbWetDry(wetDry ?? reverbWetDry);
      // Predelay, damping and cross-channel share one native call; push the
      // current values so a preset change never leaves them stale.
      await _effectsChannel.setReverbParams(
        predelayMs: reverbPredelayMs,
        damping: reverbDamping,
        crossChannel: reverbCrossChannel,
      );
      await _effectsChannel.setReverbEnabled(enabled);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  /// Loads a user-supplied impulse response. Returns true only when the native
  /// side accepted it, so callers never flip the UI to "Custom (Loaded)" on a
  /// failed load.
  Future<bool> loadCustomImpulseResponse(List<double> irSamples) async {
    if (irSamples.isEmpty) {
      ErrorLogger.log(
        'Cannot load an empty impulse response',
        category: 'EqualizerManager',
      );
      return false;
    }
    if (!PlatformCapabilities.isAndroid) {
      ErrorLogger.log(
        'Custom impulse response convolution reverb is only supported on Android',
        category: 'EqualizerManager',
      );
      return false;
    }
    final loaded = await _effectsChannel.loadImpulseResponse(irSamples);
    if (!loaded) {
      ErrorLogger.log(
        'Custom impulse response rejected by native DSP',
        category: 'EqualizerManager',
      );
      return false;
    }
    isReverbEnabled = true;
    // Must be `custom`: any synthesizable ordinal makes the native side
    // build its own IR on the next re-apply and discard the loaded one.
    reverbPreset = ReverbPreset.custom.wireValue;
    customImpulseResponse = List<double>.unmodifiable(irSamples);
    await _effectsChannel.setReverbEnabled(true);
    _debouncedSavePreferences();
    _syncPipeline();
    return true;
  }

  Future<int> getPipelineLatencyFrames() =>
      _effectsChannel.getPipelineLatencyFrames();
  Future<void> setBandSolo(int index, bool solo) =>
      _effectsChannel.setBandSolo(index, solo);
  Future<void> setBandMute(int index, bool mute) =>
      _effectsChannel.setBandMute(index, mute);

  Future<void> setStereoBalance(double balance) async {
    stereoBalance = balance.clamp(-1.0, 1.0);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setStereoBalance(stereoBalance);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setMonoMix(bool mono) async {
    monoMix = mono;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setMonoMix(mono);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setSincResampler(bool enabled) async {
    isSincResamplerEnabled = enabled;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setSincResamplerEnabled(enabled);
    }
    _debouncedSavePreferences();
  }
}