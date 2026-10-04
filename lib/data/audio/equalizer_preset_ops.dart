// lib/data/audio/equalizer_preset_ops.dart
part of 'equalizer_manager.dart';

/// Preset slots, JSON import/export, A/B comparison and custom frequency
/// layouts. Extracted from [EqualizerManager] (fat-file ratchet 01-4).
/// Same library via `part of`, so private state stays accessible and all
/// existing call sites (`manager.exportPresetToJson()` etc.) keep working.
extension EqualizerPresetOps on EqualizerManager {
  void saveCurrentToSlot(ComparisonSlot slot) {
    comparisonSlots[slot] = currentPreset;
  }

  Future<void> switchComparisonSlot(ComparisonSlot slot) async {
    activeComparisonSlot = slot;
    final slotPreset = comparisonSlots[slot] ?? EqPreset.defaultPresets.first;
    await setPreset(slotPreset);
  }

  // --- PRESET JSON IMPORT / EXPORT ---

  String exportPresetToJson([EqPreset? preset, bool pretty = false]) {
    final target = preset ?? currentPreset;
    return EqPresetSchemaValidator.exportToJson(target, pretty: pretty);
  }

  Future<bool> importPresetFromJson(String jsonString) async {
    try {
      final validation = EqPresetSchemaValidator.validateAndParse(jsonString);
      if (!validation.isValid || validation.preset == null) {
        ErrorLogger.log(
          'Failed to import EQ preset: ${validation.errorMessage}',
          category: 'EqualizerManager',
        );
        return false;
      }
      await setPreset(validation.preset!);
      return true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to import EQ preset from JSON',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
      return false;
    }
  }

  Future<void> setBassBoost(double value) async {
    // NaN survives clamp() and `(NaN * 1000).round()` throws UnsupportedError.
    final clamped = value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;
    currentPreset = currentPreset.copyWith(bassBoost: clamped);
    final milliBels = (clamped * 1000).round();
    if (PlatformCapabilities.isAndroid) {
      final applied = await _effectsChannel.setBassBoost(milliBels);
      // A failed "off" request still leaves the desired state; only an
      // enabled-but-rejected boost is a real "not applied".
      _recordEffectOutcome('bassBoost', applied || clamped <= 0.0);
    }
    _debouncedSavePreferences();
  }

  Future<void> resetToFlat() async {
    selectedHeadphoneProfile = null;
    await setPreamp(0.0);
    await setPreset(
      const EqPreset(
        name: 'Flat',
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        bassBoost: 0.0,
      ),
    );
  }

  Future<void> startAbComparison() async {
    // Re-entry would snapshot the already-flattened state as "the original".
    if (isAbComparisonActive) return;
    isAbComparisonActive = true;
    _abComparisonGains = List.from(currentPreset.gains);
    final targetFreqs = activeFrequencies;
    if (PlatformCapabilities.isAndroid) {
      // Flatten BOTH EQ paths, mirroring applyCurrentPreset's dual push:
      // the native parametric EQ and the HAL DynamicsProcessing postEq.
      // Flattening only one left the other chain still applying the curve,
      // so the "flat" A-side was not actually flat.
      final futures = <Future<void>>[];
      for (int i = 0; i < targetFreqs.length; i++) {
        futures.add(
          _effectsChannel.setNativeEqBand(i, targetFreqs[i], 0.0, 1.414),
        );
      }
      await Future.wait(futures);
      // HAL postEq layout is the 10-band customFrequencies layout in both
      // modes (32-band mode stores the interpolated curve there).
      final halFlatGains = List<double>.filled(customFrequencies.length, 0.0);
      await _effectsChannel.setEqBandGains(halFlatGains);
      // Persist flat state immediately so crash mid-A/B doesn't leave flat persisted
      await _savePreferences();
    }
  }

  Future<void> endAbComparison() async {
    isAbComparisonActive = false;
    if (_abComparisonGains.isNotEmpty) {
      final targetFreqs = activeFrequencies;
      // BUG-11: preserve any per-band edits the user made while the comparison
      // was active. Only bands still holding the pre-comparison value are
      // restored; bands the user moved keep their live value.
      final live = currentPreset.gains;
      // If the band plan changed during the comparison (10 -> 32 bands, ...)
      // the saved gains no longer match the live layout; restoring them would
      // write a wrong-sized curve. Keep the live curve in that case.
      final sameLayout = live.length == _abComparisonGains.length;
      final merged = List<double>.from(sameLayout ? _abComparisonGains : live);
      if (sameLayout) {
        for (int i = 0; i < merged.length; i++) {
          if (live[i] != _abComparisonGains[i]) {
            merged[i] = live[i];
          }
        }
      }
      if (!listEquals(merged, currentPreset.gains)) {
        currentPreset = currentPreset.copyWith(gains: merged);
        comparisonSlots[activeComparisonSlot] = currentPreset;
      }
      if (PlatformCapabilities.isAndroid) {
        // Restore BOTH EQ paths (mirrors applyCurrentPreset's dual push).
        final futures = <Future<void>>[];
        for (int i = 0; i < targetFreqs.length && i < merged.length; i++) {
          futures.add(
            _effectsChannel.setNativeEqBand(
              i,
              targetFreqs[i],
              merged[i],
              1.414,
            ),
          );
        }
        await Future.wait(futures);
        if (eqBandCount != 10) {
          // HAL postEq holds the interpolated 10-band curve in 32/64-band mode.
          await _effectsChannel.setEqBandGains(
            EqPreset.interpolateGains(
              merged,
              targetFrequencies: customFrequencies,
            ),
          );
        } else {
          await _effectsChannel.setEqBandGains(merged);
        }
      }
      _abComparisonGains = [];
      await _savePreferences();
    }
  }

  Future<void> setCustomFrequencies(List<double> frequencies) async {
    if (!isValidCustomFrequencyList(frequencies, 10)) {
      ErrorLogger.log(
        'Rejected invalid custom frequencies (need 10 finite >0)',
        category: 'EqualizerManager',
      );
      return;
    }
    customFrequencies = List.from(frequencies);
    await _savePreferences();
  }

  Future<void> setCustom32Frequencies(List<double> frequencies) async {
    if (!isValidCustomFrequencyList(frequencies, 32)) {
      ErrorLogger.log(
        'Rejected invalid custom 32-band frequencies (need 32 finite >0)',
        category: 'EqualizerManager',
      );
      return;
    }
    custom32Frequencies = List.from(frequencies);
    await _savePreferences();
  }

  Future<void> setCustom64Frequencies(List<double> frequencies) async {
    if (!isValidCustomFrequencyList(frequencies, 64)) {
      ErrorLogger.log(
        'Rejected invalid custom 64-band frequencies (need 64 finite >0)',
        category: 'EqualizerManager',
      );
      return;
    }
    custom64Frequencies = List.from(frequencies);
    await _savePreferences();
  }

  Future<void> setArbitraryEq(
    bool enabled, {
    String? eqString,
    bool? linearPhase,
  }) async {
    final prevString = arbitraryEqString;
    final prevPhase = arbitraryEqLinearPhase;
    if (eqString != null) arbitraryEqString = eqString;
    if (linearPhase != null) arbitraryEqLinearPhase = linearPhase;
    try {
      if (PlatformCapabilities.isAndroid) {
        if ((eqString != null && eqString.isNotEmpty) ||
            (linearPhase != null && arbitraryEqString.isNotEmpty)) {
          final loaded = await _effectsChannel.loadArbitraryEq(
            eqString: arbitraryEqString,
            linearPhase: arbitraryEqLinearPhase,
          );
          if (!loaded) throw StateError('Arbitrary EQ response was rejected');
        }
        await _effectsChannel.setArbitraryEqEnabled(enabled);
      }
    } catch (_) {
      // Don't leave a rejected curve in state; it would be re-sent (and
      // persisted) on every restore/reattach.
      arbitraryEqString = prevString;
      arbitraryEqLinearPhase = prevPhase;
      rethrow;
    }
    isArbitraryEqEnabled = enabled;
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setLiveProg(
    bool enabled, {
    String? code,
  }) async {
    final prevCode = liveProgCode;
    if (code != null) liveProgCode = code;
    try {
      if (PlatformCapabilities.isAndroid) {
        if (code != null && code.isNotEmpty) {
          final status = await _effectsChannel.loadLiveProgCode(code);
          if (status != 'OK') throw StateError(status);
        }
        await _effectsChannel.setLiveProgEnabled(enabled);
      }
    } catch (_) {
      liveProgCode = prevCode; // don't keep code the engine rejected
      rethrow;
    }
    isLiveProgEnabled = enabled;
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setLiveProgSlider(int sliderIndex, double value) async {
    if (!isValidLiveProgSlider(sliderIndex, value)) return;
    liveProgSliders[sliderIndex] = value;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setLiveProgSlider(sliderIndex, value);
    }
    _debouncedSavePreferences();
  }

  Future<void> setStereoWidth(
    bool enabled, {
    double? width,
    bool? multiband,
    double? lowWidth,
    double? midWidth,
    double? highWidth,
    double? lowCrossoverHz,
    double? highCrossoverHz,
  }) async {
    // Central contract + finite guard (bare clamp() lets NaN through to native).
    if (width != null) stereoWidth = DspParamRanges.stereoWidth.clamp(width);
    if (multiband != null) stereoWidthMultiband = multiband;
    if (lowWidth != null) {
      stereoWidthLow = DspParamRanges.stereoWidthBand.clamp(lowWidth);
    }
    if (midWidth != null) {
      stereoWidthMid = DspParamRanges.stereoWidthBand.clamp(midWidth);
    }
    if (highWidth != null) {
      stereoWidthHigh = DspParamRanges.stereoWidthBand.clamp(highWidth);
    }
    if (lowCrossoverHz != null) {
      stereoWidthLowCrossoverHz =
          DspParamRanges.stereoWidthLowCrossoverHz.clamp(lowCrossoverHz);
    }
    if (highCrossoverHz != null) {
      stereoWidthHighCrossoverHz =
          DspParamRanges.stereoWidthHighCrossoverHz.clamp(highCrossoverHz);
    }
    if (stereoWidthLowCrossoverHz >= stereoWidthHighCrossoverHz) {
      stereoWidthHighCrossoverHz =
          (stereoWidthLowCrossoverHz + 200.0).clamp(1000.0, 10000.0);
      if (stereoWidthHighCrossoverHz <= stereoWidthLowCrossoverHz) {
        stereoWidthLowCrossoverHz =
            (stereoWidthHighCrossoverHz - 200.0).clamp(40.0, 1000.0);
      }
    }
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setStereoWidthParams(
        stereoWidth,
        multiband: stereoWidthMultiband,
        lowWidth: stereoWidthLow,
        midWidth: stereoWidthMid,
        highWidth: stereoWidthHigh,
        lowCrossoverHz: stereoWidthLowCrossoverHz,
        highCrossoverHz: stereoWidthHighCrossoverHz,
      );
      await _effectsChannel.setStereoWidthEnabled(enabled);
    }
    isStereoWidthEnabled = enabled;
    _debouncedSavePreferences();
    _syncPipeline();
  }
}
