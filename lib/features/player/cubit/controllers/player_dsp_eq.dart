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
    final hadHeadphoneProfile = state.dsp.selectedHeadphoneProfile != null;
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(
        isEqEnabled: true,
        eqPreset: preset,
        selectedHeadphoneProfile: null,
        preampDb: hadHeadphoneProfile ? 0.0 : state.dsp.preampDb,
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

  /// Track-change entry point for automatic DSP state.
  ///
  /// A per-song override wins. Otherwise the album/artist/genre snapshot (if
  /// one was saved and the feature is enabled) is recalled, after restoring
  /// the global preset baseline left behind by a previous override track.
  Future<void> applyTrackDspState(
    SongsTableData song, {
    String? perSongPresetName,
  }) async {
    if (_isClosed()) return;
    if (_getState().isQuranModeEnabled) return;
    final generation = ++_trackDspStateGen;
    final normalized = perSongPresetName?.trim();
    final hasOverride = normalized != null &&
        normalized.isNotEmpty &&
        normalized.toLowerCase() != 'none';
    if (hasOverride) {
      await applyPerSongEqOverride(
          songId: song.id, presetName: perSongPresetName);
      return;
    }
    await applyPerSongEqOverride(songId: song.id, presetName: null);
    if (_isClosed() || _getState().currentSong?.id != song.id) return;
    if (dspBlockedReason() != null) return;
    try {
      final recalled = await _audioHandler.recallDspSnapshotFor(song);
      // A newer track-change started while the snapshot was applying; do not
      // let this stale recall overwrite its state or DSP baseline.
      if (generation != _trackDspStateGen ||
          _isClosed() ||
          _getState().currentSong?.id != song.id) {
        return;
      }
      if (recalled) {
        // Recall restores the user's crossfeed preference; re-gate it against
        // the live route so a speaker/car session does not enable headphone
        // crossfeed just because the snapshot was captured on headphones.
        await reevaluateCrossfeedForRoute(currentOutputInfo());
        if (generation != _trackDspStateGen || _isClosed()) return;
        _syncAudioEffects();
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to recall DSP snapshot on track change',
          error: e, stackTrace: st, category: 'PlayerDspController');
    }
  }

  /// Applies (or clears) the per-song EQ override for [songId].
  ///
  /// When a song with an assigned preset name starts, its preset is applied
  /// while the user's global preset is backed up; moving to a song without an
  /// override restores that global preset. Called from the track-change hook so
  /// a stored per-song EQ actually reaches the engine.
  Future<void> applyPerSongEqOverride({
    required int songId,
    String? presetName,
  }) async {
    final gen = ++_perSongEqApplyGen;
    final normalized = presetName?.trim();
    final hasOverride = normalized != null &&
        normalized.isNotEmpty &&
        normalized.toLowerCase() != 'none';

    if (!hasOverride) {
      if (!perSongOverrideActive) return;
      final backup = globalEqBackup;
      final profileBackup = globalHeadphoneProfileBackup;
      if (backup == null) {
        perSongOverrideActive = false;
        globalHeadphoneProfileBackup = null;
        return;
      }
      if (!guardDsp('Equalizer Preset', showError: false)) return;
      final restored = profileBackup != null
          ? await applyHeadphoneProfile(
              profileBackup,
              isPerSongRestore: true,
              showErrorOnGuard: false,
            )
          : await applyPreset(backup, isPerSongRestore: true);
      if (gen != _perSongEqApplyGen) return;
      if (restored) {
        perSongOverrideActive = false;
        globalEqBackup = null;
        globalHeadphoneProfileBackup = null;
      }
      return;
    }

    // Already applied for this track — avoid a redundant re-apply (and pop).
    if (perSongOverrideActive &&
        _getState().eqPreset.name.toLowerCase() == normalized.toLowerCase()) {
      return;
    }

    EqPreset? preset;
    for (final p in EqPreset.defaultPresets) {
      if (p.name.toLowerCase() == normalized.toLowerCase()) {
        preset = p;
        break;
      }
    }
    HeadphoneProfile? profile;
    if (preset == null) {
      try {
        await _headphoneProfilesRepo.loadProfiles();
      } catch (e, st) {
        ErrorLogger.log('Failed to load headphone profiles for per-song EQ',
            error: e, stackTrace: st, category: 'PlayerDspController');
      }
      if (_isClosed() || gen != _perSongEqApplyGen) return;
      for (final hp in _headphoneProfilesRepo.profiles) {
        if (hp.name.toLowerCase() == normalized.toLowerCase()) {
          profile = hp;
          break;
        }
      }
    }
    // Stale override (preset/profile no longer exists): leave the current EQ
    // untouched rather than silently flattening it.
    if (preset == null && profile == null) return;
    if (!guardDsp('Equalizer Preset', showError: false)) return;
    if (_getState().currentSong?.id != songId) return;

    final wasActive = perSongOverrideActive;
    if (!wasActive) {
      final s = _getState();
      globalEqBackup = s.eqPreset;
      globalHeadphoneProfileBackup = s.selectedHeadphoneProfile;
      perSongOverrideActive = true;
    }
    final applied = profile != null
        ? await applyHeadphoneProfile(
            profile,
            isPerSongRestore: true,
            showErrorOnGuard: false,
          )
        : await applyPreset(preset!, isPerSongRestore: true);
    if (!applied && !wasActive) {
      perSongOverrideActive = false;
      globalEqBackup = null;
      globalHeadphoneProfileBackup = null;
    }
  }

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
    var clamped = DspParamRanges.preampDb.clamp(preampDb);
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
      final isParametric = profile.hasParametricFilters;
      List<double> targetFreqs = EqPreset.centerFrequencies;
      try {
        targetFreqs = _audioHandler.activeFrequencies;
      } catch (_) {}
      final sourceGains = isParametric
          ? profile.gainsFromFilters(centers: targetFreqs)
          : profile.gains;
      final resolvedGains = sourceGains.length == targetFreqs.length
          ? List<double>.unmodifiable(sourceGains)
          : List<double>.unmodifiable(
              EqPreset.interpolateGains(
                sourceGains,
                targetFrequencies: targetFreqs,
              ),
            );
      final resolvedPreamp =
          isParametric ? profile.computeSafePreamp() : profile.preampGain;
      if (perSongOverrideActive && !isPerSongRestore) {
        globalEqBackup = state.eqPreset.copyWith(
          name: profile.name,
          gains: resolvedGains,
          bassBoost: profile.bassBoost,
        );
        globalHeadphoneProfileBackup = profile;
      }
      _emit(state.copyWith(
        dsp: state.dsp.copyWith(
          isEqEnabled: true,
          selectedHeadphoneProfile: profile,
          preampDb: resolvedPreamp,
          eqPreset: state.eqPreset.copyWith(
            name: profile.name,
            gains: resolvedGains,
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
      final hadProfile = state.dsp.selectedHeadphoneProfile != null;
      if (!hadProfile) {
        try {
          await _audioHandler.applyHeadphoneProfile(null);
          return true;
        } catch (e, st) {
          ErrorLogger.log('Failed to reset headphone profile',
              error: e, stackTrace: st, category: 'PlayerDspController');
          return false;
        }
      }
      List<double> targetFreqs = EqPreset.centerFrequencies;
      try {
        targetFreqs = _audioHandler.activeFrequencies;
      } catch (_) {}
      _emit(state.copyWith(
        dsp: state.dsp.copyWith(
          selectedHeadphoneProfile: null,
          preampDb: 0.0,
          eqPreset: EqPreset(
            name: 'Flat',
            gains: List<double>.filled(targetFreqs.length, 0.0),
            bassBoost: 0.0,
          ),
        ),
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
    if (!gain.isFinite) return;
    final clamped = DspParamRanges.eqBandGainDb.clamp(gain);
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
        preampDb: 0.0,
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
