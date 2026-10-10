// lib/features/player/cubit/controllers/player_dsp_profiles.dart
part of 'player_dsp_controller.dart';

extension PlayerDspProfilesExtension on PlayerDspController {
  Future<void> onOutputDeviceChanged(AudioOutputInfo device) async {
    if (_isClosed()) return;
    // Route-aware DSP that must track EVERY device/codec change, independent of
    // the device-profile auto-switch services below (fix #1 crossfeed gating +
    // fix #2 codec-aware music compensation). Runs before the dedup/early
    // returns so a codec switch on the same device still re-gates.
    await reevaluateCrossfeedForRoute(device);
    if (_isClosed()) return;
    await applyCodecAwareMusicCompensation();
    final service = _deviceProfileService;
    final profilesService = _settingsProfilesService;
    if (service == null || profilesService == null || _isClosed()) return;
    try {
      final key = DeviceProfileService.deviceKeyFromInfo(device);
      await service.rememberDevice(key, device.deviceName);
      if (_lastAutoAppliedDeviceKey == key) return;
      _lastAutoAppliedDeviceKey = null;

      if (_getState().isQuranModeEnabled) {
        // Quran Mode has an active recitation DSP chain tailored to voice.
        // Prevent generic music device profiles or AutoEQ from overwriting it.
        return;
      }

      final smart = _smartAudioService;
      final smartEnabled = smart != null && await smart.isEnabled();

      if (await service.isAutoSwitchEnabled()) {
        final link = await service.linkForDeviceKey(key);
        if (link != null) {
          final profiles = await profilesService.getProfiles();
          SettingsProfile? profile;
          for (final p in profiles) {
            if (p.id == link.profileId) {
              profile = p;
              break;
            }
          }
          if (profile != null) {
            _lastAutoAppliedDeviceKey = key;
            final applied = await applyProfile(profile);
            if (!applied && !_isClosed()) {
              _lastAutoAppliedDeviceKey = null;
            }
            if (smartEnabled) {
              await _applySmartQuality(device, profile.headphoneProfileId);
            }
            return;
          }
        }
      }

      if (smartEnabled) {
        final matched = await _applySmartAutoEq(smart, key, device);
        await _applySmartQuality(device, matched?.id);
      }
    } catch (e, st) {
      ErrorLogger.log('Device profile auto-switch failed',
          error: e, stackTrace: st, category: 'PlayerDspController');
    }
  }

  Future<HeadphoneProfile?> _applySmartAutoEq(
    SmartAudioService smart,
    String key,
    AudioOutputInfo device,
  ) async {
    try {
      final repo = _headphoneProfilesRepo;
      await repo.loadProfiles();
      if (_isClosed() || repo.profiles.isEmpty) return null;

      HeadphoneProfile? profile;
      final saved = await smart.linkForDeviceKey(key);
      if (saved != null) {
        profile = repo.getProfileById(saved.profileId);
      }
      if (profile == null) {
        final match = HeadphoneDeviceMatcher.match(
          deviceName: device.deviceName,
          profiles: repo.profiles,
        );
        profile = match?.profile;
        if (profile == null) return null;
        await smart.rememberAutoEqLink(
          deviceKey: key,
          deviceLabel: device.deviceName,
          profileId: profile.id,
          score: match!.score,
        );
      }

      if (_isClosed()) return null;
      _lastAutoAppliedDeviceKey = key;
      await applyHeadphoneProfile(profile, showErrorOnGuard: false);
      return profile;
    } catch (e, st) {
      ErrorLogger.log('Smart Auto AutoEQ match failed',
          error: e, stackTrace: st, category: 'PlayerDspController');
      return null;
    }
  }

  Future<void> _applySmartQuality(
    AudioOutputInfo device,
    String? matchedProfileId,
  ) async {
    final settings = _settingsCubit;
    if (settings == null || _isClosed()) return;
    final song = _getState().currentSong;
    final plan = resolveSmartAudioPlan(
      mode: SmartAudioMode.auto,
      device: device,
      matchedHeadphoneProfileId: matchedProfileId,
      trackIsHiRes: smartAudioTrackIsHiRes(
        sampleRate: song?.sampleRate ?? 0,
        bitDepth: song?.bitDepth ?? 0,
      ),
      deviceSupportsBitPerfect: device.isBitPerfectSupported,
    );
    try {
      if (plan.preferBitPerfect) {
        if (!settings.state.bitPerfectOutput) {
          await settings.setBitPerfectOutput(true);
          // Only remember the auto-application when the route actually accepted
          // it; otherwise a later "de-arbitration" would disable a mode that
          // was never on and the next device change would re-attempt blindly.
          _smartAutoBitPerfectApplied = settings.state.bitPerfectOutput;
        }
      } else if (_smartAutoBitPerfectApplied) {
        if (settings.state.bitPerfectOutput) {
          await settings.setBitPerfectOutput(false);
        }
        _smartAutoBitPerfectApplied = false;
      }
    } catch (e, st) {
      ErrorLogger.log('Smart Audio quality arbitration failed',
          error: e, stackTrace: st, category: 'PlayerDspController');
    }
  }

  Future<bool> applyProfile(SettingsProfile profile,
      {bool manual = false}) async {
    // Transactional snapshot of the full pre-apply state (DSP slice + the two
    // transport settings this method touches). A failure at ANY step rolls the
    // whole profile back in a single reconciliation pass via [_rollbackProfile]
    // instead of leaving a half-applied mix of DSP stages.
    final PlayerState snapshot = _getState();
    final settings = _settingsCubit;
    final double prevCrossfade = settings?.state.crossfadeSeconds ?? 0.0;
    final bool prevBitPerfect = settings?.state.bitPerfectOutput ?? false;

    try {
      // Apply the output/transport settings FIRST. The guarded DSP setters
      // below no-op while an exclusive bit-perfect bitstream is active, whereas
      // crossfade / bit-perfect do not — applying transport first lets us gate
      // every DSP stage on the RESULTING guard state and apply them
      // all-or-nothing, instead of the old mixed state (DSP silently skipped
      // while bit-perfect still flipped).
      if (settings != null) {
        await settings.setCrossfade(
            profile.crossfadeEnabled ? profile.crossfadeSeconds : 0.0);
        await settings.setBitPerfectOutput(profile.bitPerfectEnabled);
      }

      // Null-field policy: a stage the profile leaves null is RESET TO DEFAULT
      // (effect OFF / value 0), NOT left at its previous value. A profile
      // therefore yields a deterministic, fully-specified DSP chain regardless
      // of what was active before. (This supersedes the earlier "null = don't
      // manage this stage / leave as-is" behaviour, which made profile results
      // depend on prior state.)
      if (dspBlockedReason() == null) {
        EqPreset preset = EqPreset.defaultPresets.first;
        for (final p in EqPreset.defaultPresets) {
          if (p.name == profile.eqPresetName) {
            preset = p;
            break;
          }
        }
        final okEq = await setEqualizerEnabled(true);
        final okPreset = await applyPreset(preset);
        await setVolumeBoost(profile.volumeBoost);
        await setSaturation(profile.saturationEnabled ?? false);
        await setStereoWidth(profile.stereoWidthEnabled ?? false);
        await setLoudnessContour(profile.loudnessContourEnabled ?? false);
        await setSubCrossover(profile.subCrossoverEnabled ?? false);
        await setDynamicEq(profile.dynamicEqEnabled ?? false);
        if (profile.crossfeedEnabled != null) {
          await setCrossfeed(
            profile.crossfeedEnabled!,
            delayUs: profile.crossfeedDelayUs,
            feedDb: profile.crossfeedFeedDb,
          );
        } else {
          await setCrossfeed(false);
        }
        bool okHp = true;
        if (profile.headphoneProfileId != null) {
          final repo = _headphoneProfilesRepo;
          await repo.loadProfiles();
          final hpProfile = repo.getProfileById(profile.headphoneProfileId!);
          okHp = await applyHeadphoneProfile(hpProfile);
        } else {
          okHp = await applyHeadphoneProfile(null);
        }
        if (!okEq || !okPreset || !okHp) {
          throw Exception('One or more DSP stages failed to apply');
        }
      }
      // When DSP is blocked (profile keeps bit-perfect/AAudio/DoP active) the
      // stages above are intentionally skipped in full — a consistent "all
      // bypassed" result, not a partial apply.
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to apply settings profile — rolling back',
          error: e, stackTrace: st, category: 'PlayerDspController');
      await _rollbackProfile(snapshot, prevCrossfade, prevBitPerfect);
      return false;
    }
  }

  /// Single rollback for [applyProfile]: re-pushes the pre-apply [snapshot] DSP
  /// chain and transport settings to the engine, then restores the UI/Dart DSP
  /// slice in one emit. Each engine step is isolated so a failure restoring one
  /// stage cannot abort the rest of the rollback.
  Future<void> _rollbackProfile(
    PlayerState snapshot,
    double crossfadeSeconds,
    bool bitPerfectOutput,
  ) async {
    final dsp = snapshot.dsp;
    Future<void> step(Future<void> Function() op) async {
      try {
        await op();
      } catch (e, st) {
        ErrorLogger.log('Profile rollback step failed',
            error: e, stackTrace: st, category: 'PlayerDspController');
      }
    }

    final settings = _settingsCubit;
    if (settings != null) {
      await step(() => settings.setBitPerfectOutput(bitPerfectOutput));
      await step(() => settings.setCrossfade(crossfadeSeconds));
    }
    await step(() => _audioHandler.setEqualizerEnabled(dsp.isEqEnabled));
    await step(() => _audioHandler.applyPreset(dsp.eqPreset));
    await step(() => _audioHandler.setVolumeBoost(dsp.volumeBoost));
    await step(() => _audioHandler.setSaturation(dsp.isSaturationEnabled,
        drive: dsp.saturationDrive,
        mix: dsp.saturationMix,
        tilt: dsp.saturationTilt,
        multiband: dsp.saturationMultiband));
    await step(() => _audioHandler.setStereoWidth(dsp.isStereoWidthEnabled,
        width: dsp.stereoWidth));
    await step(() => _audioHandler.setLoudnessContour(
        dsp.isLoudnessContourEnabled,
        intensity: dsp.loudnessContourIntensity));
    await step(() => _audioHandler.setSubCrossover(dsp.isSubCrossoverEnabled,
        cornerHz: dsp.subCrossoverCornerHz,
        slopeDbPerOct: dsp.subCrossoverSlopeDbPerOct,
        gain: dsp.subCrossoverGain));
    await step(() => _audioHandler.setDynamicEq(dsp.isDynamicEqEnabled));
    await step(() => _audioHandler.setCrossfeed(dsp.isCrossfeedEnabled,
        delayUs: dsp.crossfeedDelayUs,
        feedDb: dsp.crossfeedFeedDb,
        mode: dsp.crossfeedMode));
    await step(() =>
        _audioHandler.applyHeadphoneProfile(dsp.selectedHeadphoneProfile));

    if (_isClosed()) return;
    final s = _getState();
    _emit(s.copyWith(
      dsp: dsp,
      playback: s.playback.copyWith(
        errorMessage: 'Failed to apply profile — reverted to previous settings',
      ),
    ));
  }

  /// Re-pushes the route-gated crossfeed value to the engine on a route change
  /// WITHOUT touching the stored user preference (fix #1). The preference lives
  /// in state.isCrossfeedEnabled; only the engine value is gated so crossfeed
  /// auto-bypasses on speaker/car/HDMI and restores on headphones/BT.
  Future<void> reevaluateCrossfeedForRoute(AudioOutputInfo device) async {
    if (_isClosed()) return;
    final s = _getState();
    if (s.isQuranModeEnabled) return; // Quran owns its own chain
    if (dspBlockedReason() != null) return; // bit-perfect owns the chain
    final effective =
        s.isCrossfeedEnabled && PlayerDspController.routeWantsCrossfeed(device);
    // Avoid a redundant native round-trip when the engine already matches.
    if (effective == _audioHandler.isCrossfeedEnabled) return;
    try {
      await _audioHandler.setCrossfeed(effective,
          delayUs: s.crossfeedDelayUs,
          feedDb: s.crossfeedFeedDb,
          mode: s.crossfeedMode);
    } catch (e, st) {
      ErrorLogger.log('Crossfeed route re-evaluation failed',
          error: e, stackTrace: st, category: 'PlayerDspController');
    }
  }

  /// Route/codec-aware DSP for NORMAL music (fix #2). Mirrors the earbud
  /// adaptation Quran Mode already uses: for lossy Bluetooth (SBC/AAC) it
  /// overlays a gentle HF/presence lift and trims active reverb; for
  /// LDAC/aptX-HD/aptX-Adaptive (ultra-high-quality) and all wired/USB routes
  /// it applies nothing (and reverses anything previously applied). The overlay
  /// is merged on top of the user's current EQ/reverb (never replacing it) and
  /// is fully reversible via the _appliedMusicEqComp / _appliedMusicReverbScale
  /// trackers, so it never fights explicit user EQ or double-applies.
  ///
  /// device-validate: codec identity comes from the platform A2DP report; only
  /// the merge/subtract math is unit-tested here.
  Future<void> applyCodecAwareMusicCompensation() async {
    if (_isClosed()) return;
    final state = _getState();
    // Quran Mode owns its own codec adaptation (player_playback_options_quran).
    if (state.isQuranModeEnabled) return;
    // While a bit-perfect bypass owns the chain the engine ignores DSP writes;
    // drop tracking so a later unblocked pass recomputes from the true base.
    if (dspBlockedReason() != null) {
      _appliedMusicEqComp = null;
      _appliedMusicReverbScale = 1.0;
      _musicForcedEqEnabled = false;
      return;
    }

    final caps = _earbudService.detect(currentOutputInfo());
    final wantComp = caps.isLossyBluetooth && !caps.codec.isUltraHighQuality;

    await _applyMusicEqCompensation(caps, wantComp);
    if (_isClosed()) return;
    await _applyMusicReverbTrim(caps, wantComp);
  }

  Future<void> _applyMusicEqCompensation(
      EarbudCapabilities caps, bool wantComp) async {
    final state = _getState();
    final gains = List<double>.from(state.eqPreset.gains);
    final bandCount = EqPreset.centerFrequencies.length;
    // The compensation vector is defined on the standard 10-band graphic EQ;
    // skip (and reverse) in 32-band mode where band indices map to other freqs.
    final mappable = gains.length == bandCount;
    final oldComp = _appliedMusicEqComp;

    final newComp = (wantComp && mappable)
        ? _earbudService.eqCompensation(caps)
        : List<double>.filled(bandCount, 0.0);
    final newIsZero = newComp.every((g) => g == 0.0);
    if (oldComp == null && newIsZero) return; // already clean, nothing to do

    final n = gains.length;
    // Recover the user's base by removing the comp folded in last time, then
    // add the new comp. Any user edits since last pass survive as the new base.
    final effective = List<double>.generate(n, (i) {
      final old = (oldComp != null && i < oldComp.length) ? oldComp[i] : 0.0;
      final add = i < newComp.length ? newComp[i] : 0.0;
      return (gains[i] - old + add).clamp(-15.0, 15.0).toDouble();
    });

    final activating = !newIsZero;
    final wasEqEnabled = state.isEqEnabled;
    bool eqEnabledAfter = wasEqEnabled;
    try {
      if (activating && !wasEqEnabled && !_musicForcedEqEnabled) {
        // Enable EQ so the overlay is audible; remember WE forced it so the
        // reverse path can restore the user's "EQ off" state.
        await _audioHandler.setEqualizerEnabled(true);
        _musicForcedEqEnabled = true;
      }

      for (var i = 0; i < n; i++) {
        if ((effective[i] - gains[i]).abs() > 1e-6) {
          await _audioHandler.setBandGain(i, effective[i]);
        }
      }

      if (activating) {
        eqEnabledAfter = true;
      } else if (_musicForcedEqEnabled) {
        await _audioHandler.setEqualizerEnabled(false);
        _musicForcedEqEnabled = false;
        eqEnabledAfter = false;
      }

      if (_isClosed()) return;
      _appliedMusicEqComp = newIsZero ? null : List<double>.from(newComp);
      final cur = _getState();
      _emit(cur.copyWith(
        dsp: cur.dsp.copyWith(
          isEqEnabled: eqEnabledAfter,
          eqPreset: cur.eqPreset.copyWith(gains: effective),
        ),
      ));
    } catch (e, st) {
      ErrorLogger.log('Codec-aware music EQ compensation failed',
          error: e, stackTrace: st, category: 'PlayerDspController');
    }
  }

  Future<void> _applyMusicReverbTrim(
      EarbudCapabilities caps, bool wantComp) async {
    final state = _getState();
    // Only trim reverb that is actually running; a user who has no reverb is
    // left untouched. reverbScale is 1.0 (no change) off a lossy-BT route.
    final newScale = wantComp ? caps.reverbScale.clamp(0.1, 1.0) : 1.0;
    if (!state.isReverbEnabled) {
      _appliedMusicReverbScale = 1.0;
      return;
    }
    if ((newScale - _appliedMusicReverbScale).abs() < 1e-6) return;
    final currentWet = state.reverbWetDry;
    final baseWet = _appliedMusicReverbScale > 0
        ? currentWet / _appliedMusicReverbScale
        : currentWet;
    final targetWet = (baseWet * newScale).clamp(0.0, 1.0).toDouble();
    try {
      await _audioHandler.setReverb(true,
          preset: state.reverbPreset, wetDry: targetWet);
      if (_isClosed()) return;
      _appliedMusicReverbScale = newScale;
      final cur = _getState();
      _emit(cur.copyWith(dsp: cur.dsp.copyWith(reverbWetDry: targetWet)));
    } catch (e, st) {
      ErrorLogger.log('Codec-aware music reverb trim failed',
          error: e, stackTrace: st, category: 'PlayerDspController');
    }
  }
}
