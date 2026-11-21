// lib/data/audio/equalizer_fir_ops.dart
part of 'equalizer_manager.dart';

/// Per-headphone AutoEQ FIR / PEQ ownership and application.
///
/// The FIR is synthesized by the native `ArbitraryResponseEq` from the
/// profile's target curve at the engine sample rate. The FIR target carries the
/// safe headroom itself, so the PEQ preamp stays at 0 while FIR is active and
/// the PEQ stage is disabled to prevent double correction.
extension EqualizerFirOps on EqualizerManager {
  Future<void> setHeadphoneProfile(HeadphoneProfile? profile) async {
    await _effectsLock.lock(() => _setHeadphoneProfileCore(profile));
  }

  Future<void> setAutoEqCorrectionMode(AutoEqCorrectionMode mode) async {
    if (autoEqCorrectionMode == mode) return;
    autoEqCorrectionMode = mode;
    _debouncedSavePreferences();
    if (selectedHeadphoneProfile != null) {
      await setHeadphoneProfile(selectedHeadphoneProfile);
    }
  }

  bool get isFirCorrectionActive =>
      selectedHeadphoneProfile != null &&
      isArbitraryEqEnabled &&
      (autoEqCorrectionMode == AutoEqCorrectionMode.firMinPhase ||
          autoEqCorrectionMode == AutoEqCorrectionMode.firLinear);

  Future<void> _setHeadphoneProfileCore(HeadphoneProfile? profile) async {
    final prevPreset = currentPreset;
    final prevProfile = selectedHeadphoneProfile;
    final prevArbEnabled = isArbitraryEqEnabled;
    final prevArbString = arbitraryEqString;
    final prevArbLinear = arbitraryEqLinearPhase;
    try {
      if (profile != null) {
        final bool isParametric = profile.hasParametricFilters;
        if (profile.gains.isEmpty && !isParametric) {
          ErrorLogger.log(
            'Headphone profile has empty gains — ignoring',
            category: 'EqualizerManager',
          );
          return;
        }
        if (profile.gains.any((g) => !g.isFinite)) {
          ErrorLogger.log(
            'Headphone profile contains non-finite gains — ignoring',
            category: 'EqualizerManager',
          );
          return;
        }
        final targetFreqs = activeFrequencies;
        final sourceGains = isParametric
            ? profile.gainsFromFilters(
                centers: targetFreqs,
                sampleRate: nativeSampleRate,
              )
            : profile.gains;
        final gains = sourceGains.length == targetFreqs.length
            ? List<double>.from(sourceGains)
            : EqPreset.interpolateGains(
                sourceGains,
                targetFrequencies: targetFreqs,
              );
        currentPreset = EqPreset(
          name: profile.name,
          gains: gains,
          bassBoost: profile.bassBoost,
        );
        comparisonSlots[activeComparisonSlot] = currentPreset;
        selectedHeadphoneProfile = profile;

        final bool firMode =
            autoEqCorrectionMode == AutoEqCorrectionMode.firMinPhase ||
                autoEqCorrectionMode == AutoEqCorrectionMode.firLinear;
        if (firMode) {
          final isLinear =
              autoEqCorrectionMode == AutoEqCorrectionMode.firLinear;
          final firPreamp = profile.computeFirPreamp(
            sampleRate: nativeSampleRate,
          );
          final graphicEq = profile.toGraphicEqString(
            sampleRate: nativeSampleRate,
            preampDb: firPreamp,
          );
          final loaded = await _effectsChannel.loadArbitraryEq(
            eqString: graphicEq,
            linearPhase: isLinear,
          );
          if (loaded) {
            await _effectsChannel.setArbitraryEqEnabled(true);
            // The FIR carries the correction; the PEQ stage must not stack on
            // top of it (and must not claim the profile's bands).
            if (PlatformCapabilities.isAndroid) {
              await _effectsChannel.setNativeEqEnabled(false);
              await _effectsChannel.setEqEnabled(false);
            }
            isArbitraryEqEnabled = true;
            arbitraryEqString = graphicEq;
            arbitraryEqLinearPhase = isLinear;
          } else {
            // A refused FIR load must not leave the UI claiming FIR while the
            // old correction plays. Fall back to the parametric path.
            ErrorLogger.log(
              'Native FIR rejected the AutoEQ target; falling back to PEQ',
              category: 'EqualizerManager',
            );
            autoEqCorrectionMode = AutoEqCorrectionMode.peq;
            isArbitraryEqEnabled = false;
            arbitraryEqString = '';
            arbitraryEqLinearPhase = false;
            await _effectsChannel.setArbitraryEqEnabled(false);
            if (PlatformCapabilities.isAndroid &&
                isEnabled &&
                !isBitPerfectBypass) {
              await _effectsChannel.setNativeEqEnabled(true);
              await _effectsChannel.setEqEnabled(true);
            }
            if (isParametric) {
              final applied = await _applyParametricProfile(profile);
              if (!applied) await _applyCurrentPresetCore();
            } else {
              await _applyCurrentPresetCore();
            }
          }
        } else if (isParametric) {
          await _disableFirCorrection(persist: false);
          if (PlatformCapabilities.isAndroid &&
              isEnabled &&
              !isBitPerfectBypass) {
            await _effectsChannel.setNativeEqEnabled(true);
            await _effectsChannel.setEqEnabled(true);
          }
          final applied = await _applyParametricProfile(profile);
          if (!applied) {
            await _applyCurrentPresetCore();
          }
        } else {
          await _disableFirCorrection(persist: false);
          if (PlatformCapabilities.isAndroid &&
              isEnabled &&
              !isBitPerfectBypass) {
            await _effectsChannel.setNativeEqEnabled(true);
            await _effectsChannel.setEqEnabled(true);
          }
          await _applyCurrentPresetCore();
        }
        await setBassBoost(profile.bassBoost);
        // FIR headroom is inside the target curve; PEQ keeps the profile's
        // preamp (clamped by its own range).
        final preamp = firMode && isArbitraryEqEnabled
            ? 0.0
            : (isParametric
                ? profile.computeSafePreamp()
                : profile.preampGain);
        await setPreamp(preamp);
      } else {
        if (prevProfile == null) return;
        selectedHeadphoneProfile = null;
        await _disableFirCorrection(persist: false);
        if (PlatformCapabilities.isAndroid &&
            isEnabled &&
            !isBitPerfectBypass) {
          await _effectsChannel.setNativeEqEnabled(true);
          await _effectsChannel.setEqEnabled(true);
        }
        final targetFreqs = activeFrequencies;
        currentPreset = EqPreset(
          name: 'Flat',
          gains: List<double>.filled(targetFreqs.length, 0.0),
          bassBoost: 0.0,
        );
        comparisonSlots[activeComparisonSlot] = currentPreset;
        await _applyCurrentPresetCore();
        await setBassBoost(0.0);
        await setPreamp(0.0);
      }
    } catch (e, st) {
      currentPreset = prevPreset;
      comparisonSlots[activeComparisonSlot] = prevPreset;
      selectedHeadphoneProfile = prevProfile;
      isArbitraryEqEnabled = prevArbEnabled;
      arbitraryEqString = prevArbString;
      arbitraryEqLinearPhase = prevArbLinear;
      ErrorLogger.log(
        'Failed to apply headphone profile',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
    _debouncedSavePreferences();
  }

  /// Disables and clears an AutoEQ FIR correction. [persist] is false while a
  /// caller is about to save the complete new state itself.
  Future<void> _disableFirCorrection({bool persist = true}) async {
    if (!isArbitraryEqEnabled && arbitraryEqString.isEmpty) return;
    isArbitraryEqEnabled = false;
    arbitraryEqString = '';
    arbitraryEqLinearPhase = false;
    if (PlatformCapabilities.isAndroid) {
      try {
        await _effectsChannel.setArbitraryEqEnabled(false);
        if (isEnabled && !isBitPerfectBypass) {
          await _effectsChannel.setNativeEqEnabled(true);
          await _effectsChannel.setEqEnabled(true);
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to disable the FIR correction',
            error: e, stackTrace: st, category: 'EqualizerManager');
      }
    }
    if (persist) _debouncedSavePreferences();
  }

  /// A manual preset/band edit owns the EQ again: stop the AutoEQ FIR and
  /// reset the mode so the sheet cannot claim a correction that is not live.
  /// Manual Arbitrary EQ authored independently of an AutoEQ headphone
  /// profile is preserved intact.
  Future<void> _clearFirForManualEdit() async {
    final firOwned = selectedHeadphoneProfile != null &&
        (autoEqCorrectionMode == AutoEqCorrectionMode.firMinPhase ||
            autoEqCorrectionMode == AutoEqCorrectionMode.firLinear);
    if (!firOwned) return;
    await _disableFirCorrection(persist: false);
    autoEqCorrectionMode = AutoEqCorrectionMode.peq;
    _debouncedSavePreferences();
  }
}
