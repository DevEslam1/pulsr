// lib/features/player/cubit/controllers/player_dsp_profiles.dart
part of 'player_dsp_controller.dart';

extension PlayerDspProfilesExtension on PlayerDspController {
  Future<void> onOutputDeviceChanged(AudioOutputInfo device) async {
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
}
