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

  /// Largest impulse response embedded inline in a snapshot. Every snapshot
  /// lives in ONE SharedPreferences JSON string (up to 100 entries), and a
  /// 1 s / 48 kHz IR is ~1 MB of JSON. Above this the IR is not embedded and
  /// recall falls back to a synthesized room.
  static const int maxEmbeddedIrSamples = 24000;

  /// Serializes the full effect chain into a JSON-safe map. The map is stored
  /// verbatim inside [DspSnapshot.effects].
  ///
  /// For a `custom` convolution reverb the map also carries a reference to the
  /// loaded impulse response so recall can restore the ACTUAL custom room
  /// instead of falling back to a synthesized preset. To keep the snapshot JSON
  /// small the WAV *path* is preferred (persisted by the IR picker); the raw
  /// samples are only embedded when no backing file is known.
  Map<String, dynamic> captureEffectsState() {
    final isCustomReverb = reverbPreset == ReverbPreset.custom.wireValue;
    final customIrPath = isCustomReverb
        ? (_cachedPrefs?.getString(PrefsKeys.customReverbIrPath) ?? '')
        : '';
    return <String, dynamic>{
      'v': effectsSnapshotVersion,
      // EQ curve + plan
      'eqEnabled': isEnabled,
      'eqBandCount': eqBandCount,
      'presetName': currentPreset.name,
      'gains': List<double>.from(currentPreset.gains),
      // User-customized 10-band center frequencies. The gains above are only
      // meaningful against the centers they were drawn on, so a snapshot taken
      // with a moved band layout must carry it; otherwise recall replays the
      // curve on the default ISO centers (see [applyEffectsState]).
      'customFrequencies': List<double>.from(customFrequencies),
      'custom32Frequencies': List<double>.from(custom32Frequencies),
      'custom64Frequencies': List<double>.from(custom64Frequencies),
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
      'crossfeedFcut': crossfeedFcut,
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
      // Custom-reverb IR reference (prefer the small WAV path; only embed the
      // raw samples when no backing file exists). Restored on apply via
      // loadCustomImpulseResponse so the captured room survives recall.
      if (customIrPath.isNotEmpty)
        'customReverbIrPath': customIrPath
      else if (isCustomReverb &&
          customImpulseResponse.isNotEmpty &&
          customImpulseResponse.length <= maxEmbeddedIrSamples)
        'customImpulseResponse': List<double>.from(customImpulseResponse),
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
  }

  /// Restores the full effect chain from a map produced by
  /// [captureEffectsState]. Missing keys fall back to the current in-memory
  /// value, so partial / older maps are tolerated. Each stage is applied
  /// through its public setter, so both the enable flag and parameters are
  /// pushed unconditionally — a stage the snapshot has OFF is correctly
  /// disabled even if it was ON before recall.
  ///
  /// No-ops the native pushes while battery degrade is active so recall cannot
  /// resurrect the heavy stages that [degradeToEssentials] intentionally
  /// suppressed; the recall is stashed and re-applied on [restoreFromDegrade].
  Future<void> applyEffectsState(Map<String, dynamic> m) async {
    // Battery degrade intentionally suppressed the heavy DSP stages; a snapshot
    // recall must not resurrect them mid-session. Defer it to restore so the
    // user's recall is honored once power is back (see the doc above).
    if (_isDegradedForPower) {
      _pendingDegradeEffectsSnapshot = m;
      return;
    }
    double d(String k, double fallback) =>
        (m[k] as num?)?.toDouble() ?? fallback;
    int i(String k, int fallback) => (m[k] as num?)?.toInt() ?? fallback;
    bool b(String k, bool fallback) => (m[k] as bool?) ?? fallback;
    String s(String k, String fallback) => (m[k] as String?) ?? fallback;

    // One misbehaving stage (rejected LiveProg code, bad ViPER profile, ...)
    // must not abort the rest of the recall and leave the chain half-applied.
    Future<void> guarded(String stage, Future<void> Function() body) async {
      try {
        await body();
      } catch (e, st) {
        ErrorLogger.log(
          'Snapshot recall: stage "$stage" failed; continuing with the rest',
          error: e,
          stackTrace: st,
          category: 'EqualizerManager',
        );
      }
    }

    // Custom band-center frequencies first — BEFORE the band plan and preset
    // below. setBandMode / setPreset rebuild the curve against
    // `activeFrequencies` (which, in the 10-band plan, IS `customFrequencies`),
    // so a snapshot taken with a user-customized layout would otherwise replay
    // its gains on the default ISO centers. Restore only a non-empty list whose
    // length matches the 10-band plan; older snapshots lacking the key keep the
    // current in-memory centers (prior behavior). setCustomFrequencies also
    // re-validates and persists the restored layout.
    final capturedFreqs = (m['customFrequencies'] as List?)
        ?.whereType<num>()
        .map((e) => e.toDouble())
        .toList();
    if (capturedFreqs != null &&
        isValidCustomFrequencyList(
            capturedFreqs, EqPreset.centerFrequencies.length)) {
      await setCustomFrequencies(capturedFreqs);
    }
    // Same restore for the 32- and 64-band custom layouts (active when the
    // recalled plan is 32/64), so a moved dense layout also survives recall.
    final captured32 = (m['custom32Frequencies'] as List?)
        ?.whereType<num>()
        .map((e) => e.toDouble())
        .toList();
    if (captured32 != null &&
        isValidCustomFrequencyList(
            captured32, EqPreset.iso32BandFrequencies.length)) {
      await setCustom32Frequencies(captured32);
    }
    final captured64 = (m['custom64Frequencies'] as List?)
        ?.whereType<num>()
        .map((e) => e.toDouble())
        .toList();
    if (captured64 != null &&
        isValidCustomFrequencyList(
            captured64, EqPreset.iso64Frequencies.length)) {
      await setCustom64Frequencies(captured64);
    }

    // Band plan first so the curve is interpreted against the right centers.
    final targetBandCount = i('eqBandCount', eqBandCount);
    if (targetBandCount != eqBandCount &&
        (targetBandCount == 10 ||
            targetBandCount == 32 ||
            targetBandCount == 64)) {
      await setBandMode(targetBandCount);
    }

    // EQ curve + preamp + boosts.
    final parsedGains = (m['gains'] as List?)
        ?.whereType<num>()
        .map((e) => e.toDouble())
        .toList();
    final gains = (parsedGains != null && parsedGains.isNotEmpty)
        ? parsedGains
        : List<double>.from(currentPreset.gains);
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
      fcut: d('crossfeedFcut', crossfeedFcut),
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
    reverbCrossChannel = DspParamRanges.reverbCrossChannel
        .clamp(d('reverbCrossChannel', reverbCrossChannel));
    // A stored `custom` preset needs its impulse response back, otherwise the
    // reverb would be silent. Restore the IR the snapshot captured (WAV path or
    // embedded samples) when none is live in memory; if that is impossible
    // (file gone, non-Android host, nothing captured) fall back to a
    // synthesizable room (Studio) so the stage is audible instead of dead.
    final storedReverbPreset = i('reverbPreset', reverbPreset);
    var effectiveReverbPreset = storedReverbPreset;
    // Also reload when the snapshot names a DIFFERENT IR file than the one the
    // app last persisted: "some custom IR is live in memory" used to be enough
    // to skip the restore, so album B silently played album A's room.
    final snapIrPath = (m['customReverbIrPath'] as String?) ?? '';
    final liveIrPath =
        _cachedPrefs?.getString(PrefsKeys.customReverbIrPath) ?? '';
    final irDiffers = snapIrPath.isNotEmpty && snapIrPath != liveIrPath;
    if (storedReverbPreset == ReverbPreset.custom.wireValue &&
        (customImpulseResponse.isEmpty || irDiffers)) {
      final restored = await _restoreCustomReverbIrFromSnapshot(m);
      if (!restored) effectiveReverbPreset = ReverbPreset.studio.wireValue;
    }
    await setReverb(
      b('reverbEnabled', isReverbEnabled),
      preset: effectiveReverbPreset,
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
      try {
        final bands = dynEqRaw
            .whereType<Map>()
            .map((e) =>
                DynamicEqBandConfig.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (bands.isNotEmpty) dynamicEqBands = bands;
      } catch (e, st) {
        ErrorLogger.log('Snapshot recall: corrupt dynamic EQ bands ignored',
            error: e, stackTrace: st, category: 'EqualizerManager');
      }
    }
    await setDynamicEq(b('dynamicEqEnabled', isDynamicEqEnabled));

    // Multiband compressor.
    final mbcRaw = m['multibandCompressorBands'] as List?;
    List<MultibandCompressorBandConfig>? mbcBands;
    try {
      mbcBands = mbcRaw
          ?.whereType<Map>()
          .map((e) => MultibandCompressorBandConfig.fromJson(
              Map<String, dynamic>.from(e)))
          .toList();
    } catch (e, st) {
      ErrorLogger.log('Snapshot recall: corrupt compressor bands ignored',
          error: e, stackTrace: st, category: 'EqualizerManager');
    }
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
    await guarded(
      'viperDdc',
      () => setViperDdc(
        b('viperDdcEnabled', isViperDdcEnabled),
        profileName: s('viperDdcProfileName', viperDdcProfileName),
        ddcContent: s('viperDdcContent', viperDdcContent),
      ),
    );

    // Arbitrary response EQ.
    // setArbitraryEq / setLiveProg THROW on a rejected payload, which used to
    // abort the whole recall at this point.
    await guarded(
      'arbitraryEq',
      () => setArbitraryEq(
        b('arbitraryEqEnabled', isArbitraryEqEnabled),
        eqString: s('arbitraryEqString', arbitraryEqString),
        linearPhase: b('arbitraryEqLinearPhase', arbitraryEqLinearPhase),
      ),
    );

    // LiveProg.
    await guarded(
      'liveProg',
      () => setLiveProg(
        b('liveProgEnabled', isLiveProgEnabled),
        code: s('liveProgCode', liveProgCode),
      ),
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

  /// Restores the custom convolution-reverb impulse response captured in a
  /// snapshot [m]. Prefers the persisted WAV path (small) over inline samples
  /// (large), mirroring how [captureEffectsState] stores them. Returns true
  /// only when the native side accepted an IR, so the caller can fall back to a
  /// synthesizable room when restore is impossible (file deleted / unreadable,
  /// or on a non-Android host where [loadCustomImpulseResponse] is a no-op).
  Future<bool> _restoreCustomReverbIrFromSnapshot(
      Map<String, dynamic> m) async {
    final irPath = (m['customReverbIrPath'] as String?) ?? '';
    if (irPath.isNotEmpty) {
      try {
        final samples = await IrFileParser.parseWavFile(File(irPath));
        if (samples.isNotEmpty && await loadCustomImpulseResponse(samples)) {
          return true;
        }
      } catch (e, st) {
        ErrorLogger.log(
          'Failed to restore custom reverb IR from snapshot path $irPath',
          error: e,
          stackTrace: st,
          category: 'EqualizerManager',
        );
      }
    }
    final rawIr = (m['customImpulseResponse'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList();
    if (rawIr != null && rawIr.isNotEmpty) {
      return loadCustomImpulseResponse(rawIr);
    }
    return false;
  }
}
