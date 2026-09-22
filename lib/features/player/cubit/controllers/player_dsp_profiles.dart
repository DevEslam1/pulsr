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
      final repo = HeadphoneProfilesRepository();
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
      await applyHeadphoneProfile(profile);
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
          _smartAutoBitPerfectApplied = true;
          await settings.setBitPerfectOutput(true);
        }
      } else if (_smartAutoBitPerfectApplied) {
        _smartAutoBitPerfectApplied = false;
        if (settings.state.bitPerfectOutput) {
          await settings.setBitPerfectOutput(false);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Smart Audio quality arbitration failed',
          error: e, stackTrace: st, category: 'PlayerDspController');
    }
  }

  Future<bool> applyProfile(SettingsProfile profile,
      {bool manual = false}) async {
    try {
      EqPreset preset = EqPreset.defaultPresets.first;
      for (final p in EqPreset.defaultPresets) {
        if (p.name == profile.eqPresetName) {
          preset = p;
          break;
        }
      }
      await setEqualizerEnabled(true);
      await applyPreset(preset);
      await setVolumeBoost(profile.volumeBoost);
      if (profile.saturationEnabled != null) {
        await setSaturation(profile.saturationEnabled!);
      }
      if (profile.stereoWidthEnabled != null) {
        await setStereoWidth(profile.stereoWidthEnabled!);
      }
      if (profile.loudnessContourEnabled != null) {
        await setLoudnessContour(profile.loudnessContourEnabled!);
      }
      if (profile.subCrossoverEnabled != null) {
        await setSubCrossover(profile.subCrossoverEnabled!);
      }
      if (profile.dynamicEqEnabled != null) {
        await setDynamicEq(profile.dynamicEqEnabled!);
      }
      if (profile.crossfeedEnabled != null) {
        await setCrossfeed(
          profile.crossfeedEnabled!,
          delayUs: profile.crossfeedDelayUs,
          feedDb: profile.crossfeedFeedDb,
        );
      }
      if (profile.headphoneProfileId != null) {
        final repo = HeadphoneProfilesRepository();
        await repo.loadProfiles();
        final hpProfile = repo.getProfileById(profile.headphoneProfileId!);
        await applyHeadphoneProfile(hpProfile);
      }
      final settings = _settingsCubit;
      if (settings != null) {
        await settings.setCrossfade(
            profile.crossfadeEnabled ? profile.crossfadeSeconds : 0.0);
        await settings.setBitPerfectOutput(profile.bitPerfectEnabled);
      }
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to apply settings profile',
          error: e, stackTrace: st, category: 'PlayerDspController');
      return false;
    }
  }
}
