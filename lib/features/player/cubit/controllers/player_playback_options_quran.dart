// lib/features/player/cubit/controllers/player_playback_options_quran.dart
part of 'player_playback_options_controller.dart';

/// Quran Mode DSP application and its restore-snapshot persistence. Extracted
/// from [PlayerPlaybackOptionsController] to keep that controller <= 400 lines.
extension PlayerPlaybackOptionsQuran on PlayerPlaybackOptionsController {
  Future<QuranModeProfile> _profileWithPersonalTuning(
      QuranModeProfile profile) async {
    final tuning = await _quranManager.getStyleTuning(profile.style);
    final ambience = tuning.ambience;
    final warmth = tuning.warmth;
    return profile.copyWith(
      reverbEnabled: ambience == null ? null : ambience > 0.001,
      reverbWetDry: ambience,
      saturationEnabled: warmth == null ? null : warmth > 0.0,
      saturationMix: warmth,
      playbackSpeed: tuning.playbackSpeed,
    );
  }

  Future<void> _persistCurrentQuranTuning(QuranReciterStyle style) async {
    final state = _getState();
    final persisted = await _quranManager.setStyleTuning(
      style,
      QuranStyleTuning(
        ambience: state.isReverbEnabled ? state.reverbWetDry : 0.0,
        warmth: state.isSaturationEnabled ? state.saturationMix : 0.0,
        playbackSpeed: state.playbackSpeed,
      ),
    );
    if (!persisted && !isClosed && _getState().quranReciterStyle == style) {
      final current = _getState();
      _emit(current.copyWith(
        playback: current.playback
            .copyWith(errorMessage: 'Failed to save Quran style adjustments'),
      ));
    }
  }

  Future<void> _persistQuranSnapshot(QuranRestoreSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          PrefsKeys.quranRestoreSnapshot, jsonEncode(snapshot.toJson()));
    } catch (e, st) {
      ErrorLogger.log('Failed to persist Quran Mode restore snapshot',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
    }
  }

  Future<QuranRestoreSnapshot?> loadQuranSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefsKeys.quranRestoreSnapshot);
      if (raw == null || raw.isEmpty) return null;
      return QuranRestoreSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e, st) {
      ErrorLogger.log('Failed to load Quran Mode restore snapshot',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
      return null;
    }
  }

  Future<void> _clearQuranSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PrefsKeys.quranRestoreSnapshot);
    } catch (_) {}
  }

  QuranRestoreSnapshot _captureQuranRestoreSnapshot(PlayerState s) {
    return QuranRestoreSnapshot(
      eqPreset: s.eqPreset,
      isEqEnabled: s.isEqEnabled,
      headphoneProfile: s.selectedHeadphoneProfile,
      isReverbEnabled: s.isReverbEnabled,
      reverbPreset: s.reverbPreset,
      reverbWetDry: s.reverbWetDry,
      isDynamicsEnabled: s.isDynamicsEnabled,
      dynamicsPreset: s.dynamicsPreset,
      isSaturationEnabled: s.isSaturationEnabled,
      saturationDrive: s.saturationDrive,
      saturationMix: s.saturationMix,
      saturationTilt: s.saturationTilt,
      playbackSpeed: s.playbackSpeed,
      isShuffle: s.isShuffle,
      preampDb: s.preampDb,
    );
  }

  /// Restores the persisted Quran Mode selection on startup. When the mode was
  /// on at last exit, re-captures a pre-Quran snapshot and re-applies the saved
  /// reciter profile so the live DSP matches the toggle.
  Future<void> restoreQuranMode() async {
    try {
      final styleGen = _reciterStyleGen;
      final profile = await _quranManager.restoreInitialState();
      if (profile == null || isClosed) return;
      final s = _getState();
      if (s.isQuranModeEnabled) return;
      // Keep the snapshot captured when the mode was turned on; only capture a
      // fresh one when there is none (e.g. prefs were cleared) so a relaunch
      // never snapshots an already-Quran-shaped native DSP state.
      final persisted = await loadQuranSnapshot();
      final snapshot = persisted ?? _captureQuranRestoreSnapshot(s);
      _quranManager.setRestoreSnapshot(snapshot);
      if (persisted == null) await _persistQuranSnapshot(snapshot);
      if (isClosed) return;
      // A user can choose a style while startup restoration is waiting on
      // preferences. Preserve that newer choice instead of applying the
      // stale persisted profile after the interaction completes.
      final effectiveProfile = styleGen == _reciterStyleGen
          ? profile
          : QuranModeProfile.forStyle(_getState().quranReciterStyle);
      final restored = _getState();
      _emit(restored.copyWith(
        dsp: restored.dsp.copyWith(
          isQuranModeEnabled: true,
          quranReciterStyle: effectiveProfile.style,
        ),
      ));
      await _applyQuranProfile(effectiveProfile,
          expectedGen: _quranToggleGen, expectedStyleGen: _reciterStyleGen);
    } catch (e, st) {
      ErrorLogger.log('Failed to restore Quran Mode on init',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
    }
  }

  Future<void> setQuranModeEnabled(bool enabled) async {
    final s = _getState();
    if (_targetQuranModeEnabled == enabled ||
        (_targetQuranModeEnabled == null && enabled == s.isQuranModeEnabled)) {
      return;
    }
    if (enabled && !checkDspGuard('Quran Mode')) return;

    _targetQuranModeEnabled = enabled;
    final gen = ++_quranToggleGen;

    try {
      if (enabled) {
        final currentSnapshot =
            _quranManager.restoreSnapshot ?? await loadQuranSnapshot();
        final snapshot = currentSnapshot ?? _captureQuranRestoreSnapshot(s);
        _quranManager.setRestoreSnapshot(snapshot);
        if (currentSnapshot == null) {
          await _persistQuranSnapshot(snapshot);
        }
        if (isClosed || gen != _quranToggleGen) return;

        final current = _getState();
        _emit(current.copyWith(
          dsp: current.dsp.copyWith(isQuranModeEnabled: true),
          playback: current.isShuffle
              ? current.playback.copyWith(isShuffle: false)
              : current.playback,
        ));

        final persisted = await _quranManager.setEnabled(true);
        if (!persisted && !isClosed && gen == _quranToggleGen) {
          final st = _getState();
          _emit(st.copyWith(
            playback: st.playback
                .copyWith(errorMessage: 'Failed to save Quran Mode setting'),
          ));
        }
        if (isClosed || gen != _quranToggleGen) return;

        final profile = QuranModeProfile.forStyle(current.quranReciterStyle);
        await _applyQuranProfile(profile,
            expectedGen: gen, expectedStyleGen: _reciterStyleGen);
        if (isClosed || gen != _quranToggleGen) return;

        if (current.isShuffle) {
          try {
            await _audioHandler.setShuffleMode(AudioServiceShuffleMode.none);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(PrefsKeys.playbackShuffle, false);
          } catch (e, st) {
            ErrorLogger.log('Failed to persist shuffle state for Quran Mode',
                error: e,
                stackTrace: st,
                category: 'PlayerPlaybackOptionsQuran');
          }
        }
      } else {
        final current = _getState();
        _emit(current.copyWith(
          dsp: current.dsp.copyWith(isQuranModeEnabled: false),
        ));

        final persisted = await _quranManager.setEnabled(false);
        if (!persisted && !isClosed && gen == _quranToggleGen) {
          final st = _getState();
          _emit(st.copyWith(
            playback: st.playback
                .copyWith(errorMessage: 'Failed to save Quran Mode setting'),
          ));
        }
        if (isClosed || gen != _quranToggleGen) return;

        final snapshot =
            await loadQuranSnapshot() ?? _quranManager.restoreSnapshot;
        if (isClosed || gen != _quranToggleGen) return;

        if (snapshot != null) {
          final restored =
              await _restoreFromSnapshot(snapshot, expectedGen: gen);
          if (!restored && !isClosed && gen == _quranToggleGen) {
            final st = _getState();
            _emit(st.copyWith(
              playback: st.playback.copyWith(
                  errorMessage:
                      'Failed to restore audio settings from Quran Mode'),
            ));
          }
        } else {
          await _restoreSafeDefaults(expectedGen: gen);
        }

        // A re-enable that landed while this disable was in flight already
        // captured a fresh snapshot; the stale disable must not null it or
        // delete the persisted copy (the early returns above only cover the
        // pre-restore window).
        if (gen == _quranToggleGen) {
          _quranManager.setRestoreSnapshot(null);
          await _clearQuranSnapshot();
        }
      }
    } finally {
      if (gen == _quranToggleGen) {
        _targetQuranModeEnabled = null;
      }
    }
  }

  Future<void> setQuranReciterStyle(QuranReciterStyle style) async {
    final gen = ++_reciterStyleGen;
    final s = _getState();
    _emit(s.copyWith(dsp: s.dsp.copyWith(quranReciterStyle: style)));
    try {
      final persisted = await _quranManager.setStyle(style);
      if (isClosed || gen != _reciterStyleGen) return;
      if (!persisted) {
        final current = _getState();
        _emit(current.copyWith(
          dsp: current.dsp.copyWith(quranReciterStyle: s.quranReciterStyle),
          playback: current.playback
              .copyWith(errorMessage: 'Failed to save Quran reciter style'),
        ));
        return;
      }
      if (_getState().isQuranModeEnabled) {
        if (!checkDspGuard('Quran Mode')) return;
        final profile = QuranModeProfile.forStyle(style);
        await _applyQuranProfile(profile, expectedStyleGen: gen);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set Quran reciter style',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
    }
  }

  Future<void> setQuranWarmth(double value) async {
    if (!value.isFinite || !_getState().isQuranModeEnabled) return;
    final gen = ++_quranWarmthGen;
    final mix = value.clamp(0.0, 0.6);
    final enable = mix > 0.0;
    if (enable && !checkDspGuard('Quran Vocal Warmth')) return;
    final s = _getState();
    final prevDsp = s.dsp;
    final profile = QuranModeProfile.forStyle(s.quranReciterStyle);
    final drive =
        profile.saturationDrive > 0.0 ? profile.saturationDrive : 0.20;
    final tilt = profile.saturationTilt > 0.0 ? profile.saturationTilt : 0.30;
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isSaturationEnabled: enable,
        saturationDrive: drive,
        saturationMix: mix,
        saturationTilt: tilt,
      ),
      playback: s.playback.copyWith(errorMessage: null),
    ));
    try {
      if (!_getState().isQuranModeEnabled) return;
      await _audioHandler.setSaturation(enable,
          drive: drive, mix: mix, tilt: tilt);
      if (!isClosed &&
          gen == _quranWarmthGen &&
          _getState().isQuranModeEnabled &&
          _getState().quranReciterStyle == s.quranReciterStyle) {
        await _persistCurrentQuranTuning(s.quranReciterStyle);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set Quran vocal warmth',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
      if (isClosed || gen != _quranWarmthGen) return;
      final current = _getState();
      _emit(current.copyWith(
        dsp: current.dsp.copyWith(
          isSaturationEnabled: prevDsp.isSaturationEnabled,
          saturationDrive: prevDsp.saturationDrive,
          saturationMix: prevDsp.saturationMix,
          saturationTilt: prevDsp.saturationTilt,
        ),
        playback: current.playback
            .copyWith(errorMessage: 'Failed to set Quran vocal warmth: $e'),
      ));
    }
  }

  Future<void> setQuranAmbience(double value) async {
    if (!value.isFinite || !_getState().isQuranModeEnabled) return;
    final gen = ++_quranAmbienceGen;
    final clamped = value.clamp(0.0, 0.6);
    final enable = clamped > 0.001;
    if (enable && !checkDspGuard('Quran Ambience')) return;
    final s = _getState();
    final prevDsp = s.dsp;
    final profile = QuranModeProfile.forStyle(s.quranReciterStyle);
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isReverbEnabled: enable,
        reverbPreset: profile.reverbPreset.wireValue,
        reverbWetDry: clamped,
      ),
      playback: s.playback.copyWith(errorMessage: null),
    ));
    try {
      if (!_getState().isQuranModeEnabled) return;
      await _audioHandler.setReverb(
        enable,
        preset: profile.reverbPreset.wireValue,
        wetDry: clamped,
      );
      if (!isClosed &&
          gen == _quranAmbienceGen &&
          _getState().isQuranModeEnabled &&
          _getState().quranReciterStyle == s.quranReciterStyle) {
        await _persistCurrentQuranTuning(s.quranReciterStyle);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set Quran ambience',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
      if (isClosed || gen != _quranAmbienceGen) return;
      final current = _getState();
      _emit(current.copyWith(
        dsp: current.dsp.copyWith(
          isReverbEnabled: prevDsp.isReverbEnabled,
          reverbPreset: prevDsp.reverbPreset,
          reverbWetDry: prevDsp.reverbWetDry,
        ),
        playback: current.playback
            .copyWith(errorMessage: 'Failed to set Quran ambience: $e'),
      ));
    }
  }

  Future<bool> _restoreFromSnapshot(QuranRestoreSnapshot snapshot,
      {int? expectedGen}) async {
    final s = _getState();
    final eqPreset = snapshot.eqPreset;
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isQuranModeEnabled: false,
        isEqEnabled: eqPreset != null ? snapshot.isEqEnabled : s.isEqEnabled,
        eqPreset: eqPreset ?? s.eqPreset,
        selectedHeadphoneProfile: snapshot.headphoneProfile,
        isReverbEnabled: snapshot.isReverbEnabled,
        reverbPreset: snapshot.reverbPreset,
        reverbWetDry: snapshot.reverbWetDry,
        isSaturationEnabled: snapshot.isSaturationEnabled,
        saturationDrive: snapshot.saturationDrive,
        saturationMix: snapshot.saturationMix,
        saturationTilt: snapshot.saturationTilt,
        isDynamicsEnabled: snapshot.isDynamicsEnabled,
        dynamicsPreset: snapshot.dynamicsPreset,
        preampDb: snapshot.preampDb,
      ),
      playback: s.playback.copyWith(
        playbackSpeed: snapshot.playbackSpeed,
        isShuffle: snapshot.isShuffle,
      ),
    ));

    try {
      await _audioHandler.withSmoothDspTransition(() async {
        if (isClosed ||
            (expectedGen != null && expectedGen != _quranToggleGen)) {
          return;
        }
        if (eqPreset != null) {
          await _audioHandler.setEqualizerEnabled(snapshot.isEqEnabled);
          await _audioHandler.applyPreset(eqPreset);
        }
        await _audioHandler.applyHeadphoneProfile(snapshot.headphoneProfile);
        await _audioHandler.setPreamp(snapshot.preampDb);
        await _audioHandler.setReverb(
          snapshot.isReverbEnabled,
          preset: snapshot.reverbPreset,
          wetDry: snapshot.reverbWetDry,
        );
        await _audioHandler.setSaturation(
          snapshot.isSaturationEnabled,
          drive: snapshot.saturationDrive,
          mix: snapshot.saturationMix,
          tilt: snapshot.saturationTilt,
        );
        await _audioHandler.setDynamicsPreset(
          snapshot.dynamicsPreset,
          enabled: snapshot.isDynamicsEnabled,
        );
        await _audioHandler.setSpeed(snapshot.playbackSpeed);
        if (s.isShuffle != snapshot.isShuffle) {
          await _audioHandler.setShuffleMode(
            snapshot.isShuffle
                ? AudioServiceShuffleMode.all
                : AudioServiceShuffleMode.none,
          );
        }
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(PrefsKeys.playbackSpeed, snapshot.playbackSpeed);
      await prefs.setBool(PrefsKeys.playbackShuffle, snapshot.isShuffle);
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to restore from Quran snapshot',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
      return false;
    }
  }

  /// Fallback used when Quran Mode is disabled but no restorable snapshot
  /// exists (neither persisted nor in memory). Resets all Quran-controlled
  /// DSP stages to safe defaults, including neutral preamp and flat preset.
  Future<void> _restoreSafeDefaults({int? expectedGen}) async {
    final s = _getState();
    final defaultPreset = EqPreset.defaultPresets.first;
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isQuranModeEnabled: false,
        isEqEnabled: false,
        eqPreset: defaultPreset,
        selectedHeadphoneProfile: null,
        preampDb: 0.0,
        isReverbEnabled: false,
        reverbWetDry: 0.0,
        isSaturationEnabled: false,
        isDynamicsEnabled: false,
      ),
      playback: s.playback.copyWith(
        playbackSpeed: 1.0,
      ),
    ));

    try {
      await _audioHandler.withSmoothDspTransition(() async {
        if (isClosed ||
            (expectedGen != null && expectedGen != _quranToggleGen)) {
          return;
        }
        await _audioHandler.setPreamp(0.0);
        await _audioHandler.applyPreset(defaultPreset);
        await _audioHandler.applyHeadphoneProfile(null);
        await _audioHandler.setEqualizerEnabled(false);
        await _audioHandler.setReverb(false, wetDry: 0.0);
        await _audioHandler.setSaturation(false);
        await _audioHandler.setDynamicsPreset(s.dynamicsPreset, enabled: false);
        await _audioHandler.setSpeed(1.0);
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(PrefsKeys.playbackSpeed, 1.0);
    } catch (e, st) {
      ErrorLogger.log(
          'Failed to restore safe defaults while disabling Quran Mode',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsQuran');
    }
  }

  Future<void> _applyQuranProfile(QuranModeProfile profile,
      {int? expectedGen, int? expectedStyleGen}) async {
    // The audio handler restores its persisted music DSP inside its async
    // `_init()` and only signals `effectsReady` once that restore is done.
    // Applying the Quran chain before then let `_restorePreferences()`
    // overwrite it — the toggle flipped on but the engine stayed on the music
    // curve ("Quran mode has no effect on the sound"). Await effects-ready so
    // this apply is the last writer at cold start.
    final tunedProfile = await _profileWithPersonalTuning(profile);
    await _audioHandler.effectsReady;
    final caps = await detectEarbudCapabilities();
    // Re-read the state AFTER the async capability probe. Capturing it before
    // made every later emit use a stale snapshot, so a style/toggle change
    // that landed while this probe was in flight got clobbered back to its
    // previous value ("changing a value snaps back").
    if (isClosed ||
        (expectedGen != null && expectedGen != _quranToggleGen) ||
        (expectedStyleGen != null && expectedStyleGen != _reciterStyleGen) ||
        _getState().quranReciterStyle != tunedProfile.style ||
        !_getState().isQuranModeEnabled) {
      return;
    }
    final s = _getState();
    final earbudService = _earbudOptimizationService;
    final compensatedGains = earbudService != null && caps.isLossyBluetooth
        ? earbudService.mergeCompensation(tunedProfile.eqGains, caps)
        : tunedProfile.eqGains;
    final compensatedWetDry = caps.isLossyBluetooth
        ? (tunedProfile.reverbWetDry * caps.reverbScale).clamp(0.0, 0.6)
        : tunedProfile.reverbWetDry;
    final eqPreset = tunedProfile.toEqPreset(compensatedGains);

    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isQuranModeEnabled: true,
        isEqEnabled: true,
        eqPreset: eqPreset,
        selectedHeadphoneProfile: null,
        isReverbEnabled: tunedProfile.reverbEnabled,
        reverbPreset: tunedProfile.reverbPreset.wireValue,
        reverbWetDry: compensatedWetDry,
        isSaturationEnabled: tunedProfile.saturationEnabled,
        saturationDrive: tunedProfile.saturationDrive,
        saturationMix: tunedProfile.saturationMix,
        saturationTilt: tunedProfile.saturationTilt,
        isDynamicsEnabled: tunedProfile.dynamicsEnabled,
        dynamicsPreset: tunedProfile.dynamicsPreset,
        preampDb: tunedProfile.preampDb,
      ),
      playback: s.playback.copyWith(
        playbackSpeed: tunedProfile.playbackSpeed,
      ),
    ));

    try {
      await _audioHandler.withSmoothDspTransition(() async {
        if (isClosed ||
            (expectedGen != null && expectedGen != _quranToggleGen) ||
            (expectedStyleGen != null &&
                expectedStyleGen != _reciterStyleGen) ||
            _getState().quranReciterStyle != tunedProfile.style ||
            !_getState().isQuranModeEnabled) {
          return;
        }
        // Clear headphone profile in engine so AutoEQ curves don't conflict with Quran EQ
        await _audioHandler.applyHeadphoneProfile(null);
        await _audioHandler.setPreamp(tunedProfile.preampDb);
        await _audioHandler.setEqualizerEnabled(true);
        await _audioHandler.applyPreset(eqPreset);
        await _audioHandler.setReverb(
          tunedProfile.reverbEnabled,
          preset: tunedProfile.reverbPreset.wireValue,
          wetDry: compensatedWetDry,
        );
        await _audioHandler.setSaturation(
          tunedProfile.saturationEnabled,
          drive: tunedProfile.saturationDrive,
          mix: tunedProfile.saturationMix,
          tilt: tunedProfile.saturationTilt,
        );
        await _audioHandler.setDynamicsPreset(
          tunedProfile.dynamicsPreset,
          enabled: tunedProfile.dynamicsEnabled,
        );
        await _audioHandler.setSpeed(tunedProfile.playbackSpeed);
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to apply Quran profile',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
      if (!isClosed &&
          (expectedGen == null || expectedGen == _quranToggleGen) &&
          (expectedStyleGen == null || expectedStyleGen == _reciterStyleGen) &&
          _getState().isQuranModeEnabled &&
          _getState().quranReciterStyle == tunedProfile.style) {
        final current = _getState();
        _emit(current.copyWith(
          playback: current.playback
              .copyWith(errorMessage: 'Failed to apply Quran audio profile'),
        ));
      }
    }
  }

  Future<void> reapplyQuranProfile() async {
    final s = _getState();
    if (s.isQuranModeEnabled) {
      if (!checkDspGuard('Quran Mode')) return;
      final profile = QuranModeProfile.forStyle(s.quranReciterStyle);
      await _applyQuranProfile(profile,
          expectedGen: _quranToggleGen, expectedStyleGen: _reciterStyleGen);
      return;
    }
    final snapshot = await loadQuranSnapshot() ?? _quranManager.restoreSnapshot;
    if (snapshot != null) {
      await _restoreFromSnapshot(snapshot, expectedGen: _quranToggleGen);
    }
  }

  /// Removes the selected style's personal adjustments and restores the
  /// curated profile defaults. Normal music preferences remain untouched.
  Future<void> resetQuranProfile() async {
    final state = _getState();
    if (!state.isQuranModeEnabled) return;
    final cleared = await _quranManager.setStyleTuning(
      state.quranReciterStyle,
      const QuranStyleTuning(),
    );
    if (!cleared) {
      if (!isClosed) {
        final current = _getState();
        _emit(current.copyWith(
          playback: current.playback.copyWith(
              errorMessage: 'Failed to reset Quran style adjustments'),
        ));
      }
      return;
    }
    await _applyQuranProfile(
      QuranModeProfile.forStyle(state.quranReciterStyle),
      expectedGen: _quranToggleGen,
      expectedStyleGen: _reciterStyleGen,
    );
  }

  Future<void> setQuranPlaybackSpeed(double speed) async {
    if (!speed.isFinite || !_getState().isQuranModeEnabled) return;
    final clamped = speed.clamp(minPlaybackSpeed, maxPlaybackSpeed).toDouble();
    if ((clamped - 1.0).abs() >= 1e-9 &&
        !checkPlaybackRateGuard('Quran learning speed')) {
      return;
    }
    final state = _getState();
    final previous = state.playbackSpeed;
    _emit(state.copyWith(
      playback:
          state.playback.copyWith(playbackSpeed: clamped, errorMessage: null),
    ));
    try {
      await _audioHandler.setSpeed(clamped);
      if (!isClosed &&
          _getState().isQuranModeEnabled &&
          _getState().quranReciterStyle == state.quranReciterStyle) {
        await _persistCurrentQuranTuning(state.quranReciterStyle);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set Quran learning speed',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
      if (!isClosed) {
        final current = _getState();
        _emit(current.copyWith(
          playback: current.playback.copyWith(
            playbackSpeed: previous,
            errorMessage: 'Failed to set Quran learning speed',
          ),
        ));
      }
    }
  }
}
