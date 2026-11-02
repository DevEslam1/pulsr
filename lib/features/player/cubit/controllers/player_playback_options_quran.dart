// lib/features/player/cubit/controllers/player_playback_options_quran.dart
part of 'player_playback_options_controller.dart';

/// Quran Mode DSP application and its restore-snapshot persistence. Extracted
/// from [PlayerPlaybackOptionsController] to keep that controller <= 400 lines.
extension PlayerPlaybackOptionsQuran on PlayerPlaybackOptionsController {
  bool _isCurrentQuranContext(int toggleGen, int styleGen) =>
      !isClosed &&
      toggleGen == _quranToggleGen &&
      styleGen == _reciterStyleGen &&
      _getState().isQuranModeEnabled;

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

  /// Records [message] as Quran Mode's own error so it can be cleared later
  /// without touching unrelated errors.
  String _quranErrorText(String message) {
    _lastQuranError = message;
    return message;
  }

  /// Persists only the adjustments the user actually changed ([ambience],
  /// [warmth], [speed]); the others keep whatever was stored, so touching one
  /// slider does not freeze the rest at their current values.
  ///
  /// Ambience is stored un-scaled: the live reverb already carries the earbud
  /// compensation ([_quranReverbScale]), and saving the scaled value would
  /// apply the compensation again on the next apply.
  Future<void> _persistCurrentQuranTuning(
    QuranReciterStyle style, {
    bool ambience = false,
    bool warmth = false,
    bool speed = false,
  }) async {
    final state = _getState();
    final existing = await _quranManager.getStyleTuning(style);
    final scale = _quranReverbScale > 0 ? _quranReverbScale : 1.0;
    final persisted = await _quranManager.setStyleTuning(
      style,
      QuranStyleTuning(
        ambience: ambience
            ? (state.isReverbEnabled
                ? (state.reverbWetDry / scale).clamp(0.0, 0.6).toDouble()
                : 0.0)
            : existing.ambience,
        warmth: warmth
            ? (state.isSaturationEnabled ? state.saturationMix : 0.0)
            : existing.warmth,
        playbackSpeed: speed ? state.playbackSpeed : existing.playbackSpeed,
      ),
    );
    if (!persisted && !isClosed && _getState().quranReciterStyle == style) {
      final current = _getState();
      _emit(current.copyWith(
        playback: current.playback
            .copyWith(errorMessage: _quranErrorText('Failed to save Quran style adjustments')),
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

  Future<EqPreset> _resolveSavedMusicPreset(PlayerState s) async {
    if (!QuranModeProfile.isQuranPresetName(s.eqPreset.name)) {
      return s.eqPreset;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(PrefsKeys.eqPresetName);
      if (name != null && !QuranModeProfile.isQuranPresetName(name)) {
        for (final p in EqPreset.defaultPresets) {
          if (p.name.toLowerCase() == name.toLowerCase()) {
            return p;
          }
        }
        final rawGains = prefs.getString(PrefsKeys.eqGains);
        if (rawGains != null) {
          final decoded = (jsonDecode(rawGains) as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList();
          return EqPreset(name: name, gains: decoded);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to resolve saved music preset',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
    }
    return EqPreset.defaultPresets.first;
  }

  Future<bool> _resolveSavedEqEnabled(PlayerState s) async {
    if (!QuranModeProfile.isQuranPresetName(s.eqPreset.name)) {
      return s.isEqEnabled;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(PrefsKeys.eqEnabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<QuranRestoreSnapshot> _captureQuranRestoreSnapshot(
      PlayerState s) async {
    final isQuran = QuranModeProfile.isQuranPresetName(s.eqPreset.name);
    final eqPreset = isQuran ? await _resolveSavedMusicPreset(s) : s.eqPreset;
    final isEqEnabled =
        isQuran ? await _resolveSavedEqEnabled(s) : s.isEqEnabled;

    return QuranRestoreSnapshot(
      eqPreset: eqPreset,
      isEqEnabled: isEqEnabled,
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
      final toggleGen = _quranToggleGen;
      final savedStyle = await _quranManager.getStyle();
      if (!isClosed) {
        final current = _getState();
        _emit(current.copyWith(
          dsp: current.dsp.copyWith(quranReciterStyle: savedStyle),
        ));
      }
      final profile = await _quranManager.restoreInitialState();
      if (isClosed) return;
      // The user (or a track change) already took over the toggle while the
      // preferences were loading; their decision wins over the stale restore.
      if (toggleGen != _quranToggleGen || _targetQuranModeEnabled != null) {
        return;
      }
      if (profile == null) {
        await _recoverInterruptedQuranRestore(toggleGen);
        return;
      }
      final s = _getState();
      if (s.isQuranModeEnabled) return;
      // Keep the snapshot captured when the mode was turned on; only capture a
      // fresh one when there is none (e.g. prefs were cleared) so a relaunch
      // never snapshots an already-Quran-shaped native DSP state.
      final persisted = await loadQuranSnapshot();
      final snapshot = persisted ?? await _captureQuranRestoreSnapshot(s);
      _quranManager.setRestoreSnapshot(snapshot);
      if (persisted == null) await _persistQuranSnapshot(snapshot);
      if (isClosed ||
          toggleGen != _quranToggleGen ||
          _targetQuranModeEnabled != null) {
        return;
      }
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
          expectedGen: toggleGen, expectedStyleGen: _reciterStyleGen);
    } catch (e, st) {
      ErrorLogger.log('Failed to restore Quran Mode on init',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
    }
  }

  /// Quran Mode is off at startup but a restore snapshot is still on disk: a
  /// previous disable was interrupted (crash) or the engine rejected the
  /// restore. Finish that restore so the music DSP is not left Quran-shaped.
  Future<void> _recoverInterruptedQuranRestore(int toggleGen) async {
    final snapshot = await loadQuranSnapshot();
    if (snapshot == null ||
        isClosed ||
        toggleGen != _quranToggleGen ||
        _targetQuranModeEnabled != null ||
        _getState().isQuranModeEnabled) {
      return;
    }
    _quranManager.setRestoreSnapshot(snapshot);
    final restored =
        await _restoreFromSnapshot(snapshot, expectedGen: toggleGen);
    if (restored && !isClosed && toggleGen == _quranToggleGen) {
      _quranManager.setRestoreSnapshot(null);
      await _clearQuranSnapshot();
    }
  }

  /// Reads the user's explicit on/off choice once per controller lifetime.
  /// The cache is kept in sync by [_rememberQuranUserOverride] so an auto
  /// trigger fired right after a manual toggle sees the new decision.
  Future<bool?> _loadQuranUserOverride() async {
    if (_quranUserOverrideLoaded) return _quranUserOverride;
    try {
      _quranUserOverride = await _quranManager.getUserOverride();
    } catch (e, st) {
      ErrorLogger.log('Failed to read Quran Mode user override',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
      _quranUserOverride = null;
    }
    _quranUserOverrideLoaded = true;
    return _quranUserOverride;
  }

  /// Updates the in-memory decision first so an automatic trigger that fires
  /// right after sees it; the manager logs a failed write and never throws.
  /// `null` clears the decision and hands control back to automatic mode.
  Future<void> _rememberQuranUserOverride(bool? value) async {
    _quranUserOverride = value;
    _quranUserOverrideLoaded = true;
    await _quranManager.setUserOverride(value);
  }

  /// Forgets the user's manual on/off decision so Quran Mode follows the
  /// playing track again, and applies that immediately to the current track.
  Future<void> resetQuranAutoMode() async {
    await _rememberQuranUserOverride(null);
    final song = _getState().currentSong;
    if (song != null && !isClosed) {
      await handleTrackChangeQuranMode(song, immediate: true);
    }
  }

  Future<void> setQuranModeEnabled(bool enabled,
      {bool isAutoTriggered = false}) async {
    // Automatic activation is a metadata heuristic (`isQuranTrack` matches
    // "quran", "surah", reciter names, ...). It may switch the mode on and off
    // for a user who never touched the toggle, but it must never override a
    // decision the user made by hand: otherwise a manually enabled mode is
    // switched off (and persisted as off) by the next unrelated track, and a
    // manually disabled mode comes back on its own.
    if (isAutoTriggered) {
      final override = await _loadQuranUserOverride();
      if (override != null && override != enabled) return;
    }

    final s = _getState();
    if (_targetQuranModeEnabled == enabled ||
        (_targetQuranModeEnabled == null && enabled == s.isQuranModeEnabled)) {
      return;
    }
    if (enabled && !checkDspGuard('Quran Mode')) return;

    _targetQuranModeEnabled = enabled;
    final gen = ++_quranToggleGen;

    try {
      if (!isAutoTriggered) {
        await _rememberQuranUserOverride(enabled);
      }
      if (enabled) {
        // A stored snapshot is only trustworthy while the engine still holds
        // the Quran curve (a disable is mid-flight). Once the music settings
        // are back, anything the user changed since must be captured afresh,
        // otherwise a failed earlier restore would roll those changes back on
        // the next disable.
        final engineIsQuranShaped =
            QuranModeProfile.isQuranPresetName(s.eqPreset.name);
        final existing = engineIsQuranShaped
            ? (_quranManager.restoreSnapshot ?? await loadQuranSnapshot())
            : null;
        final snapshot = existing ?? await _captureQuranRestoreSnapshot(s);
        _quranManager.setRestoreSnapshot(snapshot);
        if (existing == null) {
          await _persistQuranSnapshot(snapshot);
        }
        if (isClosed || gen != _quranToggleGen) return;

        final savedStyle = await _quranManager.getStyle();
        final current = _getState();
        _emit(current.copyWith(
          dsp: current.dsp.copyWith(
            isQuranModeEnabled: true,
            quranReciterStyle: savedStyle,
          ),
          playback: current.isShuffle
              ? current.playback.copyWith(isShuffle: false)
              : current.playback,
        ));

        final persisted = await _quranManager.setEnabled(true);
        if (!persisted && !isClosed && gen == _quranToggleGen) {
          final st = _getState();
          _emit(st.copyWith(
            playback: st.playback.copyWith(
                errorMessage: _quranErrorText('Failed to save Quran Mode setting')),
          ));
        }
        if (isClosed || gen != _quranToggleGen) return;

        final profile = QuranModeProfile.forStyle(savedStyle);
        final applied = await _applyQuranProfile(profile,
            expectedGen: gen, expectedStyleGen: _reciterStyleGen);
        if (isClosed || gen != _quranToggleGen) return;

        if (!applied) {
          // The engine rejected the Quran chain. Leaving the toggle "on" (and
          // persisted as on) would misreport what the user hears, so fall back
          // to the music settings and surface the failure.
          await _leaveQuranMode(gen);
          if (!isClosed && gen == _quranToggleGen) {
            final st = _getState();
            _emit(st.copyWith(
              playback: st.playback.copyWith(
                  errorMessage:
                      _quranErrorText('Failed to apply Quran audio profile')),
            ));
          }
          return;
        }

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
        await _leaveQuranMode(gen);
      }
    } finally {
      if (gen == _quranToggleGen) {
        _targetQuranModeEnabled = null;
      }
    }
  }

  /// Turns Quran Mode off and puts the user's music DSP back. Shared by the
  /// normal disable path and the rollback after a failed enable.
  Future<void> _leaveQuranMode(int gen) async {
    final current = _getState();
    _emit(current.copyWith(
      dsp: current.dsp.copyWith(isQuranModeEnabled: false),
    ));

    final persisted = await _quranManager.setEnabled(false);
    if (!persisted && !isClosed && gen == _quranToggleGen) {
      final st = _getState();
      _emit(st.copyWith(
        playback: st.playback.copyWith(
            errorMessage: _quranErrorText('Failed to save Quran Mode setting')),
      ));
    }
    if (isClosed || gen != _quranToggleGen) return;

    final snapshot = await loadQuranSnapshot() ?? _quranManager.restoreSnapshot;
    if (isClosed || gen != _quranToggleGen) return;

    if (snapshot != null) {
      final restored = await _restoreFromSnapshot(snapshot, expectedGen: gen);
      if (!restored && !isClosed && gen == _quranToggleGen) {
        final st = _getState();
        _emit(st.copyWith(
          playback: st.playback.copyWith(
              errorMessage: _quranErrorText(
                  'Failed to restore audio settings from Quran Mode')),
        ));
      }
      // Keep both copies until the engine has actually accepted the
      // music settings. The retry action needs this original snapshot.
      if (!restored) return;
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
              .copyWith(errorMessage: _quranErrorText('Failed to save Quran reciter style')),
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
    final toggleGen = _quranToggleGen;
    final styleGen = _reciterStyleGen;
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
      if (_isCurrentQuranContext(toggleGen, styleGen) &&
          gen == _quranWarmthGen &&
          _getState().isQuranModeEnabled &&
          _getState().quranReciterStyle == s.quranReciterStyle) {
        await _persistCurrentQuranTuning(s.quranReciterStyle, warmth: true);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set Quran vocal warmth',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
      if (!_isCurrentQuranContext(toggleGen, styleGen) ||
          gen != _quranWarmthGen) {
        return;
      }
      final current = _getState();
      _emit(current.copyWith(
        dsp: current.dsp.copyWith(
          isSaturationEnabled: prevDsp.isSaturationEnabled,
          saturationDrive: prevDsp.saturationDrive,
          saturationMix: prevDsp.saturationMix,
          saturationTilt: prevDsp.saturationTilt,
        ),
        playback: current.playback
            .copyWith(errorMessage: _quranErrorText('Failed to set Quran vocal warmth: $e')),
      ));
    }
  }

  Future<void> setQuranAmbience(double value) async {
    if (!value.isFinite || !_getState().isQuranModeEnabled) return;
    final gen = ++_quranAmbienceGen;
    final toggleGen = _quranToggleGen;
    final styleGen = _reciterStyleGen;
    final clamped = value.clamp(0.0, 0.6);
    final enable = clamped > 0.001;
    if (enable && !checkDspGuard('Quran Ambience')) return;
    final s = _getState();
    final prevDsp = s.dsp;
    final profile = QuranModeProfile.forStyle(s.quranReciterStyle);
    // The slider value is applied as-is, so no earbud compensation remains in
    // the live reverb until the next profile apply recomputes it.
    _quranReverbScale = 1.0;
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
      if (_isCurrentQuranContext(toggleGen, styleGen) &&
          gen == _quranAmbienceGen &&
          _getState().isQuranModeEnabled &&
          _getState().quranReciterStyle == s.quranReciterStyle) {
        await _persistCurrentQuranTuning(s.quranReciterStyle, ambience: true);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set Quran ambience',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
      if (!_isCurrentQuranContext(toggleGen, styleGen) ||
          gen != _quranAmbienceGen) {
        return;
      }
      final current = _getState();
      _emit(current.copyWith(
        dsp: current.dsp.copyWith(
          isReverbEnabled: prevDsp.isReverbEnabled,
          reverbPreset: prevDsp.reverbPreset,
          reverbWetDry: prevDsp.reverbWetDry,
        ),
        playback: current.playback
            .copyWith(errorMessage: _quranErrorText('Failed to set Quran ambience: $e')),
      ));
    }
  }

  Future<bool> _restoreFromSnapshot(QuranRestoreSnapshot snapshot,
      {int? expectedGen}) async {
    final s = _getState();
    final resolvedEqPreset = (snapshot.eqPreset == null ||
            QuranModeProfile.isQuranPresetName(snapshot.eqPreset!.name))
        ? await _resolveSavedMusicPreset(s)
        : snapshot.eqPreset!;
    final resolvedEqEnabled = (snapshot.eqPreset == null ||
            QuranModeProfile.isQuranPresetName(snapshot.eqPreset!.name))
        ? await _resolveSavedEqEnabled(s)
        : snapshot.isEqEnabled;
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isQuranModeEnabled: false,
        isEqEnabled: resolvedEqEnabled,
        eqPreset: resolvedEqPreset,
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
        await _audioHandler.setEqualizerEnabled(resolvedEqEnabled);
        await _audioHandler.applyPreset(resolvedEqPreset);
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
      if (!isClosed &&
          (expectedGen == null || expectedGen == _quranToggleGen)) {
        final current = _getState();
        if (_lastQuranError != null && current.errorMessage == _lastQuranError) {
          _emit(current.copyWith(
            playback: current.playback.copyWith(errorMessage: null),
          ));
        }
      }
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
    final defaultPreset = await _resolveSavedMusicPreset(s);
    final isEqEnabled = await _resolveSavedEqEnabled(s);
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isQuranModeEnabled: false,
        isEqEnabled: isEqEnabled,
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
        await _audioHandler.setEqualizerEnabled(isEqEnabled);
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

  /// Returns `false` only when the engine rejected the profile while this call
  /// was still the current one; stale or superseded applies count as handled.
  Future<bool> _applyQuranProfile(QuranModeProfile profile,
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
      return true;
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
    _quranReverbScale = caps.isLossyBluetooth ? caps.reverbScale : 1.0;

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
      if (!isClosed &&
          (expectedGen == null || expectedGen == _quranToggleGen) &&
          (expectedStyleGen == null || expectedStyleGen == _reciterStyleGen) &&
          _getState().isQuranModeEnabled &&
          _getState().quranReciterStyle == tunedProfile.style) {
        final current = _getState();
        if (_lastQuranError != null && current.errorMessage == _lastQuranError) {
          _emit(current.copyWith(
            playback: current.playback.copyWith(errorMessage: null),
          ));
        }
      }
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
          playback: current.playback.copyWith(
              errorMessage: _quranErrorText('Failed to apply Quran audio profile')),
        ));
        return false;
      }
    }
    return true;
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
    final gen = _quranToggleGen;
    final snapshot = await loadQuranSnapshot() ?? _quranManager.restoreSnapshot;
    if (isClosed || gen != _quranToggleGen || _getState().isQuranModeEnabled) {
      return;
    }
    if (snapshot != null) {
      final restored = await _restoreFromSnapshot(snapshot, expectedGen: gen);
      if (restored &&
          !isClosed &&
          gen == _quranToggleGen &&
          !_getState().isQuranModeEnabled) {
        _quranManager.setRestoreSnapshot(null);
        await _clearQuranSnapshot();
      }
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
              errorMessage: _quranErrorText('Failed to reset Quran style adjustments')),
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
    final gen = ++_quranSpeedGen;
    final toggleGen = _quranToggleGen;
    final styleGen = _reciterStyleGen;
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
      if (_isCurrentQuranContext(toggleGen, styleGen) &&
          gen == _quranSpeedGen &&
          _getState().isQuranModeEnabled &&
          _getState().quranReciterStyle == state.quranReciterStyle) {
        await _persistCurrentQuranTuning(state.quranReciterStyle, speed: true);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set Quran learning speed',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
      if (_isCurrentQuranContext(toggleGen, styleGen) &&
          gen == _quranSpeedGen) {
        final current = _getState();
        _emit(current.copyWith(
          playback: current.playback.copyWith(
            playbackSpeed: previous,
            errorMessage: _quranErrorText('Failed to set Quran learning speed'),
          ),
        ));
      }
    }
  }

  /// Automatically activates Quran Mode when playing a Quran recitation or radio
  /// broadcast, defaulting to Tajweed (Mujawwad) and preserving user preferences.
  /// Automatically deactivates and restores native DSP when switching to non-Quran tracks.
  ///
  /// A flip is held for [quranAutoDebounce] and dropped if a newer track change
  /// arrives first, so skipping through a mixed queue does not capture,
  /// apply and restore the whole DSP chain for every track. [immediate] skips
  /// the wait.
  Future<void> handleTrackChangeQuranMode(SongsTableData song,
      {bool immediate = false}) async {
    final gen = ++_quranAutoGen;
    final isQuran = isQuranTrack(song);
    if (isQuran == _getState().isQuranModeEnabled) return;

    if (!immediate && quranAutoDebounce > Duration.zero) {
      await Future<void>.delayed(quranAutoDebounce);
      if (isClosed || gen != _quranAutoGen) return;
    }
    if (isQuran == _getState().isQuranModeEnabled) return;
    await setQuranModeEnabled(isQuran, isAutoTriggered: true);
  }
}
