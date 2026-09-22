// lib/data/audio/equalizer_snapshot_ops.dart
part of 'equalizer_manager.dart';

/// Full effect-chain capture / restore for per-scope DSP snapshots
/// (album / artist / genre — see [DspSnapshotStore]).
///
/// Before this existed, a recalled snapshot only re-applied the graphic-EQ
/// curve (preset name + gains + boosts). Every JamesDSP / Phase-1 stage
/// (saturation, stereo width, reverb, dynamic EQ, multiband compressor,
/// dynamic bass, ViPER-DDC, arbitrary EQ, LiveProg, crossfeed, limiter,
/// loudness contour, sub crossover, virtualizer, spatializer, balance) was
/// silently dropped on recall. This captures and restores all of them.
///
/// Deliberately excluded because they are device/output-global, not a
/// per-album tonal choice: dspPreference, bit-perfect bypass, dither, sinc
/// resampler, and the loudness volume-tracking level.
extension EqualizerSnapshotOps on EqualizerManager {
  /// Schema version of the serialized effects map. Bump only on a
  /// backward-incompatible field change; [applyEffectsState] tolerates missing
  /// keys via per-field fallbacks so additive changes need no bump.
  static const int effectsSnapshotVersion = 1;

  /// Serializes the full effect chain into a JSON-safe map. The map is stored
  /// verbatim inside [DspSnapshot.effects].
  Map<String, dynamic> captureEffectsState() => <String, dynamic>{
        'v': effectsSnapshotVersion,
        // EQ curve + plan
        'eqEnabled': isEnabled,
        'eqBandCount': eqBandCount,
        'presetName': currentPreset.name,
        'gains': List<double>.from(currentPreset.gains),
        'bassBoost': currentPreset.bassBoost,
        'preampDb': preampDb,
        'volumeBoost': volumeBoost,
        // Virtualizer / spatializer
        'virtualizerEnabled': isVirtualizerEnabled,
        'virtualizerStrength': virtualizerStrength,
        'spatializerEnabled': isSpatializerEnabled,
        // Dynamics (HAL preset)
        'dynamicsEnabled': isDynamicsEnabled,
        'dynamicsPreset': dynamicsPreset.name,
        // Crossfeed
        'crossfeedEnabled': isCrossfeedEnabled,
        'crossfeedDelayUs': crossfeedDelayUs,
        'crossfeedFeedDb': crossfeedFeedDb,
        'crossfeedMode': crossfeedMode,
        // Lookahead limiter + compressor knobs
        'limiterEnabled': isLimiterEnabled,
        'limiterThresholdDb': limiterThresholdDb,
        'limiterReleaseMs': limiterReleaseMs,
        'limiterLookaheadMs': limiterLookaheadMs,
        'hasCompressorParams': _hasStoredCompressorParams,
        'compressorRatio': compressorRatio,
        'compressorAttackMs': compressorAttackMs,
        'compressorMakeupGainDb': compressorMakeupGainDb,
        // Convolution reverb
        'reverbEnabled': isReverbEnabled,
        'reverbPreset': reverbPreset,
        'reverbWetDry': reverbWetDry,
        'reverbCrossChannel': reverbCrossChannel,
        // Panner
        'stereoBalance': stereoBalance,
        'monoMix': monoMix,
        // Harmonic saturation
        'saturationEnabled': isSaturationEnabled,
        'saturationDrive': saturationDrive,
        'saturationMix': saturationMix,
        'saturationTilt': saturationTilt,
        'saturationMode': saturationMode,
        'saturationMultiband': saturationMultiband,
        // Stereo width
        'stereoWidthEnabled': isStereoWidthEnabled,
        'stereoWidth': stereoWidth,
        'stereoWidthMultiband': stereoWidthMultiband,
        'stereoWidthLow': stereoWidthLow,
        'stereoWidthMid': stereoWidthMid,
        'stereoWidthHigh': stereoWidthHigh,
        'stereoWidthLowCrossoverHz': stereoWidthLowCrossoverHz,
        'stereoWidthHighCrossoverHz': stereoWidthHighCrossoverHz,
        // Loudness contour
        'loudnessContourEnabled': isLoudnessContourEnabled,
        'loudnessContourIntensity': loudnessContourIntensity,
        // Sub crossover
        'subCrossoverEnabled': isSubCrossoverEnabled,
        'subCrossoverCornerHz': subCrossoverCornerHz,
        'subCrossoverSlopeDbPerOct': subCrossoverSlopeDbPerOct,
        'subCrossoverGain': subCrossoverGain,
        'subCrossoverBassMono': subCrossoverBassMono,
        'subCrossoverAntiPop': subCrossoverAntiPop,
        // Dynamic EQ
        'dynamicEqEnabled': isDynamicEqEnabled,
        'dynamicEqBands': dynamicEqBands.map((b) => b.toJson()).toList(),
        // Multiband compressor
        'multibandCompressorEnabled': isMultibandCompressorEnabled,
        'multibandCompressorF0': multibandCompressorF0,
        'multibandCompressorF1': multibandCompressorF1,
        'multibandCompressorF2': multibandCompressorF2,
        'multibandCompressorBands':
            multibandCompressorBands.map((b) => b.toJson()).toList(),
        // Dynamic bass
        'dynamicBassEnabled': isDynamicBassEnabled,
        'dynamicBassStrength': dynamicBassStrength,
        'dynamicBassXLow': dynamicBassXLow,
        'dynamicBassXHigh': dynamicBassXHigh,
        'dynamicBassYLow': dynamicBassYLow,
        'dynamicBassYHigh': dynamicBassYHigh,
        'dynamicBassSideGainLow': dynamicBassSideGainLow,
        'dynamicBassSideGainHigh': dynamicBassSideGainHigh,
        'dynamicBassPreset': dynamicBassPreset,
        // ViPER-DDC
        'viperDdcEnabled': isViperDdcEnabled,
        'viperDdcProfileName': viperDdcProfileName,
        'viperDdcContent': viperDdcContent,
        // Arbitrary response EQ
        'arbitraryEqEnabled': isArbitraryEqEnabled,
        'arbitraryEqString': arbitraryEqString,
        'arbitraryEqLinearPhase': arbitraryEqLinearPhase,
        // LiveProg
        'liveProgEnabled': isLiveProgEnabled,
        'liveProgCode': liveProgCode,
        'liveProgSliders':
            liveProgSliders.map((k, v) => MapEntry(k.toString(), v)),
      };

  /// Restores the full effect chain from a map produced by
  /// [captureEffectsState]. Missing keys fall back to the current in-memory
  /// value, so partial / older maps are tolerated. Each stage is applied
  /// through its public setter, so both the enable flag and parameters are
  /// pushed unconditionally — a stage the snapshot has OFF is correctly
  /// disabled even if it was ON before recall.
  ///
  /// No-ops while battery degrade is active so recall cannot resurrect the
  /// heavy stages that [degradeToEssentials] intentionally suppressed; the
  /// snapshot state is still written to memory and takes effect on
  /// [restoreFromDegrade].
  Future<void> applyEffectsState(Map<String, dynamic> m) async {
    // Battery degrade intentionally suppressed the heavy DSP stages; a snapshot
    // recall must not resurrect them mid-session (see the doc above).
    if (_isDegradedForPower) return;
    double d(String k, double fallback) =>
        (m[k] as num?)?.toDouble() ?? fallback;
    int i(String k, int fallback) => (m[k] as num?)?.toInt() ?? fallback;
    bool b(String k, bool fallback) => (m[k] as bool?) ?? fallback;
    String s(String k, String fallback) => (m[k] as String?) ?? fallback;

    // Band plan first so the curve is interpreted against the right centers.
    final targetBandCount = i('eqBandCount', eqBandCount);
    if (targetBandCount != eqBandCount &&
        (targetBandCount == 10 ||
            targetBandCount == 32 ||
            targetBandCount == 64)) {
      await setBandMode(targetBandCount);
    }

    // EQ curve + preamp + boosts.
    final gains = (m['gains'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        List<double>.from(currentPreset.gains);
    await setPreset(EqPreset(
      name: s('presetName', currentPreset.name),
      gains: gains,
      bassBoost: d('bassBoost', currentPreset.bassBoost),
    ));
    await setPreamp(d('preampDb', preampDb));
    await setVolumeBoost(d('volumeBoost', volumeBoost));
    await setEnabled(b('eqEnabled', isEnabled));

    // Virtualizer / spatializer.
    await setVirtualizerStrength(d('virtualizerStrength', virtualizerStrength));
    await setVirtualizerEnabled(b('virtualizerEnabled', isVirtualizerEnabled));
    await setSpatializerEnabled(b('spatializerEnabled', isSpatializerEnabled));

    // Dynamics HAL preset.
    final dynName = s('dynamicsPreset', dynamicsPreset.name);
    final dynPreset = DynamicsPreset.values.firstWhere(
      (p) => p.name == dynName,
      orElse: () => dynamicsPreset,
    );
    await setDynamicsPreset(dynPreset,
        enabled: b('dynamicsEnabled', isDynamicsEnabled));

    // Crossfeed.
    await setCrossfeed(
      b('crossfeedEnabled', isCrossfeedEnabled),
      delayUs: d('crossfeedDelayUs', crossfeedDelayUs),
      feedDb: d('crossfeedFeedDb', crossfeedFeedDb),
      mode: i('crossfeedMode', crossfeedMode),
    );

    // Lookahead limiter (+ compressor knobs when the snapshot owns them).
    await setLookaheadLimiter(
      b('limiterEnabled', isLimiterEnabled),
      thresholdDb: d('limiterThresholdDb', limiterThresholdDb),
      releaseMs: d('limiterReleaseMs', limiterReleaseMs),
      lookaheadMs: d('limiterLookaheadMs', limiterLookaheadMs),
    );
    if (b('hasCompressorParams', false)) {
      await setCompressorParams(
        ratio: d('compressorRatio', compressorRatio),
        attackMs: d('compressorAttackMs', compressorAttackMs),
        makeupGainDb: d('compressorMakeupGainDb', compressorMakeupGainDb),
      );
    }

    // Convolution reverb (crossChannel has no public setter — set the field
    // and push through the channel directly, mirroring restore).
    reverbCrossChannel = d('reverbCrossChannel', reverbCrossChannel);
    await setReverb(
      b('reverbEnabled', isReverbEnabled),
      preset: i('reverbPreset', reverbPreset),
      wetDry: d('reverbWetDry', reverbWetDry),
    );
    if (PlatformCapabilities.isAndroid && isReverbEnabled) {
      await _effectsChannel.setReverbCrossChannel(reverbCrossChannel);
    }

    // Panner.
    await setStereoBalance(d('stereoBalance', stereoBalance));
    await setMonoMix(b('monoMix', monoMix));

    // Harmonic saturation.
    await setSaturation(
      b('saturationEnabled', isSaturationEnabled),
      drive: d('saturationDrive', saturationDrive),
      mix: d('saturationMix', saturationMix),
      tilt: d('saturationTilt', saturationTilt),
      mode: i('saturationMode', saturationMode),
      multiband: b('saturationMultiband', saturationMultiband),
    );

    // Stereo width.
    await setStereoWidth(
      b('stereoWidthEnabled', isStereoWidthEnabled),
      width: d('stereoWidth', stereoWidth),
      multiband: b('stereoWidthMultiband', stereoWidthMultiband),
      lowWidth: d('stereoWidthLow', stereoWidthLow),
      midWidth: d('stereoWidthMid', stereoWidthMid),
      highWidth: d('stereoWidthHigh', stereoWidthHigh),
      lowCrossoverHz: d('stereoWidthLowCrossoverHz', stereoWidthLowCrossoverHz),
      highCrossoverHz:
          d('stereoWidthHighCrossoverHz', stereoWidthHighCrossoverHz),
    );

    // Loudness contour.
    await setLoudnessContour(
      b('loudnessContourEnabled', isLoudnessContourEnabled),
      intensity: d('loudnessContourIntensity', loudnessContourIntensity),
    );

    // Sub crossover.
    await setSubCrossover(
      b('subCrossoverEnabled', isSubCrossoverEnabled),
      cornerHz: d('subCrossoverCornerHz', subCrossoverCornerHz),
      slopeDbPerOct: d('subCrossoverSlopeDbPerOct', subCrossoverSlopeDbPerOct),
      gain: d('subCrossoverGain', subCrossoverGain),
      bassMono: b('subCrossoverBassMono', subCrossoverBassMono),
      antiPop: b('subCrossoverAntiPop', subCrossoverAntiPop),
    );

    // Dynamic EQ — set bands before the enable flag so the stage comes up
    // configured (setDynamicEqBand only pushes while the stage is enabled).
    final dynEqRaw = m['dynamicEqBands'] as List?;
    if (dynEqRaw != null) {
      final bands = dynEqRaw
          .whereType<Map>()
          .map((e) => DynamicEqBandConfig.fromJson(
              Map<String, dynamic>.from(e)))
          .toList();
      if (bands.isNotEmpty) dynamicEqBands = bands;
    }
    await setDynamicEq(b('dynamicEqEnabled', isDynamicEqEnabled));

    // Multiband compressor.
    final mbcRaw = m['multibandCompressorBands'] as List?;
    final mbcBands = mbcRaw
        ?.whereType<Map>()
        .map((e) => MultibandCompressorBandConfig.fromJson(
            Map<String, dynamic>.from(e)))
        .toList();
    await setMultibandCompressor(
      b('multibandCompressorEnabled', isMultibandCompressorEnabled),
      bands: (mbcBands != null && mbcBands.isNotEmpty) ? mbcBands : null,
      f0: d('multibandCompressorF0', multibandCompressorF0),
      f1: d('multibandCompressorF1', multibandCompressorF1),
      f2: d('multibandCompressorF2', multibandCompressorF2),
    );

    // Dynamic bass. A builtin device preset derives the X/Y/gain values, so
    // only forward the custom knobs when preset == 0 (custom).
    final dbPreset = i('dynamicBassPreset', dynamicBassPreset);
    await setDynamicBass(
      enabled: b('dynamicBassEnabled', isDynamicBassEnabled),
      strength: d('dynamicBassStrength', dynamicBassStrength),
      preset: dbPreset,
      xLow: dbPreset == 0 ? i('dynamicBassXLow', dynamicBassXLow) : null,
      xHigh: dbPreset == 0 ? i('dynamicBassXHigh', dynamicBassXHigh) : null,
      yLow: dbPreset == 0 ? i('dynamicBassYLow', dynamicBassYLow) : null,
      yHigh: dbPreset == 0 ? i('dynamicBassYHigh', dynamicBassYHigh) : null,
      sideGainLow: dbPreset == 0
          ? d('dynamicBassSideGainLow', dynamicBassSideGainLow)
          : null,
      sideGainHigh: dbPreset == 0
          ? d('dynamicBassSideGainHigh', dynamicBassSideGainHigh)
          : null,
    );

    // ViPER-DDC.
    await setViperDdc(
      b('viperDdcEnabled', isViperDdcEnabled),
      profileName: s('viperDdcProfileName', viperDdcProfileName),
      ddcContent: s('viperDdcContent', viperDdcContent),
    );

    // Arbitrary response EQ.
    await setArbitraryEq(
      b('arbitraryEqEnabled', isArbitraryEqEnabled),
      eqString: s('arbitraryEqString', arbitraryEqString),
      linearPhase: b('arbitraryEqLinearPhase', arbitraryEqLinearPhase),
    );

    // LiveProg.
    await setLiveProg(
      b('liveProgEnabled', isLiveProgEnabled),
      code: s('liveProgCode', liveProgCode),
    );
    final sliders = m['liveProgSliders'];
    if (sliders is Map) {
      for (final entry in sliders.entries) {
        final idx = int.tryParse(entry.key.toString());
        final val = (entry.value as num?)?.toDouble();
        if (idx != null && val != null) {
          await setLiveProgSlider(idx, val);
        }
      }
    }

    _syncPipeline();
  }
}
