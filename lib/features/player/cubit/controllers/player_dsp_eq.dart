// lib/features/player/cubit/controllers/player_dsp_eq.dart
part of 'player_dsp_controller.dart';

/// Equalizer preset, band-gain and headphone-profile application surface of the
/// DSP controller. Split out of player_dsp_controller.dart (pure code movement,
/// no behaviour change) to keep that file focused and within the controller
/// size budget. Lives in the same library (`part of`), so it can read the
/// shared `_audioHandler` / `_getState` / `_emit` members directly.
extension PlayerDspEqExtension on PlayerDspController {
  Future<bool> setEqualizerEnabled(bool enabled) => applyDspEffect(
        featureName: 'Equalizer',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(isEqEnabled: enabled),
        applyAudioHandler: () => _audioHandler.setEqualizerEnabled(enabled),
      );

  Future<bool> applyPreset(EqPreset preset,
      {bool isPerSongRestore = false}) async {
    markUserInteracting();
    if (!guardDsp('Equalizer Preset')) return false;
    if (perSongOverrideActive && !isPerSongRestore) {
      globalEqBackup = preset;
      globalHeadphoneProfileBackup = null;
    }
    final state = _getState();
    final previousDsp = state.dsp;
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(
        isEqEnabled: true,
        eqPreset: preset,
        selectedHeadphoneProfile: null,
      ),
      playback: state.playback.copyWith(errorMessage: null),
    ));
    try {
      await _audioHandler.setEqualizerEnabled(true);
      await _audioHandler.applyPreset(preset);
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to apply preset',
          error: e, stackTrace: st, category: 'PlayerDspController');
      final s = _getState();
      _emit(s.copyWith(
          dsp: previousDsp,
          playback:
              s.playback.copyWith(errorMessage: 'Failed to apply preset: $e')));
      return false;
    }
  }

  Future<bool> resetEqualizer() => applyPreset(EqPreset.defaultPresets.first);

  /// The engine-canonical EQ preamp (dB), read through the handler boundary
  /// (which returns the equalizer manager's value) — the single source of truth,
  /// kept in sync with native on every setPreamp, restore, snapshot recall and
  /// session reattach. Exposed so the cubit's reconciliation and the UI read ONE
  /// value instead of drifting.
  double get preampDb => _audioHandler.preampDb;

  /// Routes preamp through the shared guard/emit/rollback helper so it obeys
  /// the bit-perfect gate, marks user interaction and surfaces native failures
  /// like every other DSP setter (previously it bypassed all of this and let
  /// native exceptions escape into UI callers). Clamped defensively to the
  /// central ±15 dB contract ([DspParamRanges.preampDb]) and mirrored into
  /// PlayerState.dsp.preampDb so the reconciliation path and UI never drift from
  /// the engine (PlayerCubit._syncAudioEffects reads it back from the handler).
  Future<bool> setPreamp(double preampDb) {
    var clamped = DspParamRanges.preampDb.clampRaw(preampDb);
    if (clamped > 0) {
      clamped = GainStagingBudget.clampBoostDb(
        requestedBoostDb: clamped,
        committedStages: _activeGainStages(excludeEqPreamp: true),
      );
    }
    return applyDspEffect(
      featureName: 'Preamp',
      updateDsp: (dsp) => dsp.copyWith(preampDb: clamped),
      applyAudioHandler: () => _audioHandler.setPreamp(clamped),
    );
  }

  Future<bool> applyHeadphoneProfile(HeadphoneProfile? profile,
      {bool isPerSongRestore = false, bool showErrorOnGuard = true}) async {
    markUserInteracting();
    if (profile != null && !guardDsp('AutoEQ', showError: showErrorOnGuard)) {
      return false;
    }
    final state = _getState();
    final previousDsp = state.dsp;
    if (profile != null) {
      if (perSongOverrideActive && !isPerSongRestore) {
        globalEqBackup = state.eqPreset.copyWith(
          name: profile.name,
          gains: List<double>.unmodifiable(profile.gains),
          bassBoost: profile.bassBoost,
        );
        globalHeadphoneProfileBackup = profile;
      }
      _emit(state.copyWith(
        dsp: state.dsp.copyWith(
          isEqEnabled: true,
          selectedHeadphoneProfile: profile,
          eqPreset: state.eqPreset.copyWith(
            name: profile.name,
            gains: List<double>.unmodifiable(profile.gains),
            bassBoost: profile.bassBoost,
          ),
        ),
        playback: state.playback.copyWith(errorMessage: null),
      ));
      try {
        await _audioHandler.setEqualizerEnabled(true);
        await _audioHandler.applyHeadphoneProfile(profile);
        return true;
      } catch (e, st) {
        ErrorLogger.log('Failed to apply AutoEQ profile',
            error: e, stackTrace: st, category: 'PlayerDspController');
        final s = _getState();
        _emit(s.copyWith(
          dsp: previousDsp,
          playback: s.playback.copyWith(
            errorMessage: 'Failed to apply AutoEQ profile: $e',
          ),
        ));
        return false;
      }
    } else {
      _emit(state.copyWith(
        dsp: state.dsp.copyWith(selectedHeadphoneProfile: null),
      ));
      try {
        await _audioHandler.applyHeadphoneProfile(null);
        return true;
      } catch (e, st) {
        ErrorLogger.log('Failed to reset headphone profile',
            error: e, stackTrace: st, category: 'PlayerDspController');
        final s = _getState();
        _emit(s.copyWith(
          dsp: previousDsp,
          playback: s.playback.copyWith(
            errorMessage: 'Failed to reset headphone profile: $e',
          ),
        ));
        return false;
      }
    }
  }

  Future<bool> resetHeadphoneProfile() => applyHeadphoneProfile(null);

  Future<void> setBandGain(int bandIndex, double gain) async {
    markUserInteracting();
    if (!guardDsp('Band Gain', showError: false)) return;
    final clamped = gain.clamp(-15.0, 15.0);
    final state = _getState();
    final currentGains = List<double>.from(state.eqPreset.gains);
    if (bandIndex < 0 || bandIndex >= currentGains.length) return;
    final previousDsp = state.dsp;
    currentGains[bandIndex] = clamped;
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(
        eqPreset: state.eqPreset.copyWith(
          name: 'Custom',
          gains: List<double>.unmodifiable(currentGains),
        ),
        selectedHeadphoneProfile: null,
      ),
    ));
    try {
      await _audioHandler.setBandGain(bandIndex, clamped);
    } catch (e, st) {
      ErrorLogger.log('Failed to set band gain',
          error: e, stackTrace: st, category: 'PlayerDspController');
      final s = _getState();
      _emit(s.copyWith(
          dsp: previousDsp,
          playback: s.playback
              .copyWith(errorMessage: 'Failed to set band gain: $e')));
    }
  }

  Future<void> resetToFlat() async {
    markUserInteracting();
    final state = _getState();
    final previousDsp = state.dsp;
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(
        eqPreset: EqPreset.defaultPresets.first,
        selectedHeadphoneProfile: null,
      ),
    ));
    try {
      await _audioHandler.resetToFlat();
    } catch (e, st) {
      ErrorLogger.log('Failed to reset equalizer',
          error: e, stackTrace: st, category: 'PlayerDspController');
      final s = _getState();
      _emit(s.copyWith(
        dsp: previousDsp,
        playback:
            s.playback.copyWith(errorMessage: 'Failed to reset equalizer: $e'),
      ));
    }
  }
}
