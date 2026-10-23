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
      final flatGains = List<double>.filled(targetFreqs.length, 0.0);
      await _effectsChannel.setNativeEqBandsBulk(
        frequencies: targetFreqs,
        gains: flatGains,
        qs: graphicEqQs(targetFreqs),
      );
      if (legacyMirrorEnabled) {
        final halFlatGains = List<double>.filled(customFrequencies.length, 0.0);
        await _effectsChannel.setEqBandGains(halFlatGains);
      }
    }
  }

  Future<void> endAbComparison() async {
    isAbComparisonActive = false;
    if (_abComparisonGains.isNotEmpty) {
      final targetFreqs = activeFrequencies;
      final live = currentPreset.gains;
      final sameLayout = live.length == _abComparisonGains.length;
      final merged = List<double>.from(sameLayout ? _abComparisonGains : live);
      bool userEdited = false;
      if (sameLayout) {
        for (int i = 0; i < merged.length; i++) {
          if (live[i] != _abComparisonGains[i]) {
            merged[i] = live[i];
            userEdited = true;
          }
        }
      }
      if (!listEquals(merged, currentPreset.gains)) {
        currentPreset = currentPreset.copyWith(gains: merged);
        comparisonSlots[activeComparisonSlot] = currentPreset;
      }
      if (PlatformCapabilities.isAndroid) {
        if (!userEdited && selectedHeadphoneProfile != null) {
          await applyHeadphoneProfile(selectedHeadphoneProfile!);
        } else {
          await _effectsChannel.setNativeEqBandsBulk(
            frequencies: targetFreqs,
            gains: merged,
            qs: graphicEqQs(targetFreqs),
          );
          if (legacyMirrorEnabled) {
            if (eqBandCount != 10) {
              await _effectsChannel.setEqBandGains(
                EqPreset.interpolateGains(
                  merged,
                  targetFrequencies: customFrequencies,
                  sourceFrequencies: targetFreqs,
                ),
              );
            } else {
              await _effectsChannel.setEqBandGains(merged);
            }
          }
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
    final prevEnabled = isArbitraryEqEnabled;

    final targetString = eqString ?? prevString;
    final targetPhase = linearPhase ?? prevPhase;

    try {
      if (PlatformCapabilities.isAndroid) {
        if (eqString != null ||
            (linearPhase != null && targetString.isNotEmpty)) {
          final loaded = await _effectsChannel.loadArbitraryEq(
            eqString: targetString,
            linearPhase: targetPhase,
          );
          if (!loaded) throw StateError('Arbitrary EQ response was rejected');
        }
        await _effectsChannel.setArbitraryEqEnabled(enabled);
      }
      arbitraryEqString = targetString;
      arbitraryEqLinearPhase = targetPhase;
      isArbitraryEqEnabled = enabled;
      _debouncedSavePreferences();
      _syncPipeline();
    } catch (_) {
      arbitraryEqString = prevString;
      arbitraryEqLinearPhase = prevPhase;
      isArbitraryEqEnabled = prevEnabled;
      rethrow;
    }
  }

  Future<void> setLiveProg(
    bool enabled, {
    String? code,
  }) async {
    final prevCode = liveProgCode;
    final prevEnabled = isLiveProgEnabled;
    final targetCode = code ?? prevCode;

    try {
      if (PlatformCapabilities.isAndroid) {
        if (code != null && code.isNotEmpty) {
          final status = await _effectsChannel.loadLiveProgCode(code);
          if (status != 'OK') throw StateError(status);
        }
        await _effectsChannel.setLiveProgEnabled(enabled);
      }
      liveProgCode = targetCode;
      isLiveProgEnabled = enabled;
      _debouncedSavePreferences();
      _syncPipeline();
    } catch (_) {
      liveProgCode = prevCode;
      isLiveProgEnabled = prevEnabled;
      rethrow;
    }
  }

  Future<void> setLiveProgSlider(int sliderIndex, double value) async {
    if (!isValidLiveProgSlider(sliderIndex, value)) return;
    final prevValue = liveProgSliders[sliderIndex];
    try {
      if (PlatformCapabilities.isAndroid) {
        await _effectsChannel.setLiveProgSlider(sliderIndex, value);
      }
      liveProgSliders[sliderIndex] = value;
      _debouncedSavePreferences();
    } catch (e, st) {
      if (prevValue != null) {
        liveProgSliders[sliderIndex] = prevValue;
      } else {
        liveProgSliders.remove(sliderIndex);
      }
      ErrorLogger.log('Failed to set LiveProg slider',
          error: e, stackTrace: st, category: 'EqualizerManager');
      rethrow;
    }
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
    final prevWidth = stereoWidth;
    final prevMultiband = stereoWidthMultiband;
    final prevLowWidth = stereoWidthLow;
    final prevMidWidth = stereoWidthMid;
    final prevHighWidth = stereoWidthHigh;
    final prevLowCrossoverHz = stereoWidthLowCrossoverHz;
    final prevHighCrossoverHz = stereoWidthHighCrossoverHz;
    final prevEnabled = isStereoWidthEnabled;

    final targetWidth =
        width != null ? DspParamRanges.stereoWidth.clamp(width) : prevWidth;
    final targetMultiband = multiband ?? prevMultiband;
    final targetLowWidth = lowWidth != null
        ? DspParamRanges.stereoWidthBand.clamp(lowWidth)
        : prevLowWidth;
    final targetMidWidth = midWidth != null
        ? DspParamRanges.stereoWidthBand.clamp(midWidth)
        : prevMidWidth;
    final targetHighWidth = highWidth != null
        ? DspParamRanges.stereoWidthBand.clamp(highWidth)
        : prevHighWidth;
    var targetLowCrossoverHz = lowCrossoverHz != null
        ? DspParamRanges.stereoWidthLowCrossoverHz.clamp(lowCrossoverHz)
        : prevLowCrossoverHz;
    var targetHighCrossoverHz = highCrossoverHz != null
        ? DspParamRanges.stereoWidthHighCrossoverHz.clamp(highCrossoverHz)
        : prevHighCrossoverHz;

    if (targetLowCrossoverHz >= targetHighCrossoverHz) {
      targetHighCrossoverHz =
          (targetLowCrossoverHz + 200.0).clamp(1000.0, 10000.0);
      if (targetHighCrossoverHz <= targetLowCrossoverHz) {
        targetLowCrossoverHz =
            (targetHighCrossoverHz - 200.0).clamp(40.0, 1000.0);
      }
    }

    try {
      if (PlatformCapabilities.isAndroid) {
        await _effectsChannel.setStereoWidthParams(
          targetWidth,
          multiband: targetMultiband,
          lowWidth: targetLowWidth,
          midWidth: targetMidWidth,
          highWidth: targetHighWidth,
          lowCrossoverHz: targetLowCrossoverHz,
          highCrossoverHz: targetHighCrossoverHz,
        );
        await _effectsChannel.setStereoWidthEnabled(enabled);
      }
      stereoWidth = targetWidth;
      stereoWidthMultiband = targetMultiband;
      stereoWidthLow = targetLowWidth;
      stereoWidthMid = targetMidWidth;
      stereoWidthHigh = targetHighWidth;
      stereoWidthLowCrossoverHz = targetLowCrossoverHz;
      stereoWidthHighCrossoverHz = targetHighCrossoverHz;
      isStereoWidthEnabled = enabled;
      _debouncedSavePreferences();
      _syncPipeline();
    } catch (e, st) {
      stereoWidth = prevWidth;
      stereoWidthMultiband = prevMultiband;
      stereoWidthLow = prevLowWidth;
      stereoWidthMid = prevMidWidth;
      stereoWidthHigh = prevHighWidth;
      stereoWidthLowCrossoverHz = prevLowCrossoverHz;
      stereoWidthHighCrossoverHz = prevHighCrossoverHz;
      isStereoWidthEnabled = prevEnabled;
      ErrorLogger.log('Failed to set stereo width',
          error: e, stackTrace: st, category: 'EqualizerManager');
      rethrow;
    }
  }
}
