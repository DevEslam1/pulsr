part of 'settings_cubit.dart';

mixin SettingsAudioActions on PulsrCubit<SettingsState> {
  Future<void> setReplayGainMode(ReplayGainMode mode) async {
    if (mode != ReplayGainMode.off) {
      final blocked = AudioConflicts.replayGainBlockedByBitPerfect(
        bitPerfectOutput: state.bitPerfectOutput,
        bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
        device: state.currentOutputDevice,
        aaudioEnabled: state.aaudioOutputEnabled,
      );
      if (blocked != null) {
        safeEmit(state.copyWith(errorMessage: blocked));
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsCubit._keyReplayGainMode, mode.name);
    // PlayerCubit reacts to this state emission by re-applying the gain. Save
    // first so AudioHandler's cached preferences cannot calculate using the
    // previous mode (which made ReplayGain look enabled but sound unchanged).
    safeEmit(state.copyWith(replayGainMode: mode, errorMessage: null));
  }

  Future<void> setReplayGainPreampWithRg(double db) async {
    final clamped = db.clamp(-15.0, 15.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(SettingsCubit._keyReplayGainPreampWithRg, clamped);
    safeEmit(state.copyWith(replayGainPreampWithRg: clamped));
  }

  Future<void> setReplayGainPreampWithoutRg(double db) async {
    final clamped = db.clamp(-15.0, 15.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(SettingsCubit._keyReplayGainPreampWithoutRg, clamped);
    safeEmit(state.copyWith(replayGainPreampWithoutRg: clamped));
  }

  Future<void> setStreamingQuality(YtmAudioQuality quality) async {
    safeEmit(state.copyWith(streamingQuality: quality));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsCubit._keyStreamingQuality, quality.name);
  }

  Future<void> setDownloadQuality(YtmAudioQuality quality) async {
    safeEmit(state.copyWith(downloadQuality: quality));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsCubit._keyDownloadQuality, quality.name);
  }

  Future<void> setWifiOnlyMode(bool enabled) async {
    safeEmit(state.copyWith(wifiOnlyMode: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsCubit._keyWifiOnlyMode, enabled);
  }

  Future<void> setOfflineOnlyMode(bool enabled) async {
    safeEmit(state.copyWith(offlineOnlyMode: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsCubit._keyOfflineOnlyMode, enabled);
  }

  /// Crossfade overlaps two tracks and would alter the bitstream, so turning on
  /// a bit-perfect path must clear any active crossfade rather than leaving both
  /// persisted and letting the engine overlap tracks anyway.
  Future<void> _forceCrossfadeOffForBitPerfect() async {
    if (state.crossfadeSeconds <= 0.01) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(SettingsCubit._keyCrossfade, 0.0);
    if (isClosed) return;
    safeEmit(state.copyWith(
      crossfadeSeconds: 0.0,
      errorMessage:
          'Crossfade disabled: it is not compatible with Bit-Perfect output.',
    ));
  }

  Future<void> setBitPerfectOutput(bool enabled) async {    if (enabled) {
      final block = AudioConflicts.bitPerfectBlockedReason(
        state.currentOutputDevice,
      );
      if (block != null) {
        safeEmit(state.copyWith(errorMessage: block));
        return;
      }
    }
    safeEmit(
      state.copyWith(
        bitPerfectOutput: enabled,
        errorMessage: null,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bitPerfectOutput, enabled);
    final applied = await _hiResAudioService.setBitPerfectMode(enabled);
    if (enabled && !applied) {
      // Device rejected bit-perfect (unsupported/route change). Revert the
      // optimistic state and pref so the UI and quality badge never claim
      // bit-perfect output that is not actually active.
      try {
        await prefs.setBool(PrefsKeys.bitPerfectOutput, false);
      } catch (_) {}
      if (!isClosed) {
        safeEmit(state.copyWith(
          bitPerfectOutput: false,
          errorMessage:
              'Bit-Perfect output is not supported by the current output device.',
        ));
      }
      await refreshOutputDevice();
      return;
    }
    if (enabled) {
      await _forceCrossfadeOffForBitPerfect();
    }
    // Wire bypass: when bit-perfect enabled and user wants bypass, force DSP off via native
    if (enabled && state.bypassDspOnBitPerfect) {
      try {
        if (getIt.isRegistered<EqualizerManager>()) {
          await getIt<EqualizerManager>().setBypassDspForBitPerfect(true);
        } else {
          await AudioEffectsChannel().setBypassDspForBitPerfect(true);
        }
      } catch (_) {}
      // Also force ReplayGain off — software gain breaks bit-perfect
      if (state.replayGainMode != ReplayGainMode.off) {
        await prefs.setString(SettingsCubit._keyReplayGainMode, ReplayGainMode.off.name);
        safeEmit(
          state.copyWith(
            replayGainMode: ReplayGainMode.off,
            errorMessage:
                'ReplayGain disabled: not compatible with Bit-Perfect bypass.',
          ),
        );
      }
    } else if (!enabled) {
      try {
        if (getIt.isRegistered<EqualizerManager>()) {
          await getIt<EqualizerManager>().setBypassDspForBitPerfect(false);
        } else {
          await AudioEffectsChannel().setBypassDspForBitPerfect(false);
        }
      } catch (_) {}
    }
    await refreshOutputDevice();
  }

  Future<void> setBypassDspOnBitPerfect(bool enabled) async {
    safeEmit(state.copyWith(bypassDspOnBitPerfect: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bypassDspOnBitPerfect, enabled);
    // Apply immediately if bit-perfect is currently active
    if (state.bitPerfectOutput) {
      try {
        if (getIt.isRegistered<EqualizerManager>()) {
          await getIt<EqualizerManager>().setBypassDspForBitPerfect(enabled);
        } else {
          await AudioEffectsChannel().setBypassDspForBitPerfect(enabled);
        }
      } catch (_) {}
    }
    await refreshOutputDevice();
  }

  Future<void> loadMqaDecodingPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      SettingsCubit.mqaEnabledCache = prefs.getBool(PrefsKeys.mqaDecodingEnabled) ?? true;
    } catch (e, st) {
      ErrorLogger.log('MQA preference load failed',
          error: e, stackTrace: st, category: 'Settings');
    }
    MqaDecoderHelper.isMqaEnabled = () => SettingsCubit.mqaEnabledCache;
  }

  Future<void> setMqaDecodingEnabled(bool enabled) async {
    SettingsCubit.mqaEnabledCache = enabled;
    MqaDecoderHelper.isMqaEnabled = () => SettingsCubit.mqaEnabledCache;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.mqaDecodingEnabled, enabled);
    } catch (e, st) {
      ErrorLogger.log('MQA preference save failed',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  /// T2: follow the current track's native sample rate on every track change.
  /// The actual native call happens in PlayerCubit (it owns the track-change
  /// stream and the de-dupe state); this only persists the preference.
  Future<void> setFollowTrackSampleRate(bool value) async {
    safeEmit(state.copyWith(followTrackSampleRate: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.followTrackSampleRate, value);
  }

  /// T4: select the DSD (DSF/DFF) output transport.
  ///
  /// Refuses DoP unless the native probe has confirmed a compatible USB DAC, so
  /// the persisted preference can never claim native DSD on a path that cannot
  /// carry it. PCM is always allowed and is the default.
  Future<void> setDsdOutputMode(DsdOutputMode mode) async {
    if (mode == DsdOutputMode.dop && !state.dsdDopSupported) {
      safeEmit(state.copyWith(
        errorMessage:
            'DoP output requires a connected USB DAC that supports DSD over PCM.',
      ));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.dsdOutputMode, mode.name);
    safeEmit(state.copyWith(dsdOutputMode: mode, errorMessage: null));
  }

  /// T3: strict bit-perfect (no resample). Enabling forces Bit-Perfect output,
  /// the DSP bypass and follow-track, then surfaces the conflict reason rather
  /// than silently muting stages. Disabled when the path cannot do bit-perfect.
  Future<void> setStrictBitPerfect(bool enabled) async {
    if (enabled) {
      final block = AudioConflicts.strictBitPerfectBlockedReason(
          state.currentOutputDevice);
      if (block != null) {
        safeEmit(state.copyWith(errorMessage: block));
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.strictBitPerfect, enabled);
    if (!enabled) {
      safeEmit(state.copyWith(strictBitPerfect: false, errorMessage: null));
      return;
    }
    safeEmit(state.copyWith(
      strictBitPerfect: true,
      bitPerfectOutput: true,
      bypassDspOnBitPerfect: true,
      followTrackSampleRate: true,
      errorMessage: null,
    ));
    await prefs.setBool(PrefsKeys.bitPerfectOutput, true);
    await prefs.setBool(PrefsKeys.bypassDspOnBitPerfect, true);
    await prefs.setBool(PrefsKeys.followTrackSampleRate, true);
    final applied = await _hiResAudioService.setBitPerfectMode(true);
    if (!applied) {
      // Strict bit-perfect is impossible on this device; revert rather than
      // persist a configuration the hardware cannot honour.
      try {
        await prefs.setBool(PrefsKeys.strictBitPerfect, false);
        await prefs.setBool(PrefsKeys.bitPerfectOutput, false);
      } catch (_) {}
      if (!isClosed) {
        safeEmit(state.copyWith(
          strictBitPerfect: false,
          bitPerfectOutput: false,
          errorMessage:
              'Strict Bit-Perfect is not supported by the current output device.',
        ));
      }
      await refreshOutputDevice();
      return;
    }
    try {
      if (getIt.isRegistered<EqualizerManager>()) {
        await getIt<EqualizerManager>().setBypassDspForBitPerfect(true);
      } else {
        await AudioEffectsChannel().setBypassDspForBitPerfect(true);
      }
    } catch (_) {}
    await _forceCrossfadeOffForBitPerfect();
    // Software gain would alter the bitstream; turn it off like the normal
    // Bit-Perfect path does.
    if (state.replayGainMode != ReplayGainMode.off) {
      await prefs.setString(SettingsCubit._keyReplayGainMode, ReplayGainMode.off.name);
      if (!isClosed) {
        safeEmit(state.copyWith(replayGainMode: ReplayGainMode.off));
      }
    }
    await refreshOutputDevice();
  }

  /// Requests the media route move to [deviceId]. Returns true only when the
  /// platform actually accepted it; otherwise the system output panel is opened
  /// so the user can switch, since an unprivileged app cannot force the route.
  Future<bool> selectOutputDevice(int deviceId) async {
    final res = await _hiResAudioService.selectOutputDevice(deviceId);
    if (!res.success && res.requiresSystemPicker) {
      await _hiResAudioService.openOutputSwitcher();
    }
    await refreshOutputDevice();
    return res.success;
  }

  Future<bool> openOutputSwitcher() => _hiResAudioService.openOutputSwitcher();

  Future<void> clearOutputDevice() async {
    await _hiResAudioService.clearOutputDevice();
    await refreshOutputDevice();
  }

  Future<void> setTargetOutputSampleRate(int sampleRate) async {
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            targetSampleRate: sampleRate,
          ),
        ),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('target_output_sample_rate', sampleRate);
    final bitDepth = state.currentOutputDevice?.targetBitDepth ?? 0;
    await _hiResAudioService.setTargetOutputFormat(
      sampleRate: sampleRate,
      bitDepth: bitDepth,
    );
    await refreshOutputDevice();
  }

  Future<void> setTargetOutputBitDepth(int bitDepth) async {
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            targetBitDepth: bitDepth,
          ),
        ),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('target_output_bit_depth', bitDepth);
    final sampleRate = state.currentOutputDevice?.targetSampleRate ?? 0;
    await _hiResAudioService.setTargetOutputFormat(
      sampleRate: sampleRate,
      bitDepth: bitDepth,
    );
    await refreshOutputDevice();
  }

  /// Returns true when the platform accepted the request; false means the
  /// stock ROM refused it (SystemApi) — caller must offer Developer Options.
  Future<bool> setBluetoothCodec(String codec) async {
    // Optimistic UI: update btCodecName immediately
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            btCodecName: codec,
          ),
        ),
      );
    }
    final ok = await _hiResAudioService.setBluetoothCodec(codec);
    await refreshOutputDevice();
    return ok;
  }

  Future<bool> setBluetoothSampleRate(int hz) async {
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            btSampleRateHz: hz,
          ),
        ),
      );
    }
    final ok = await _hiResAudioService.setBluetoothSampleRate(hz);
    await refreshOutputDevice();
    return ok;
  }

  Future<bool> setBluetoothBitDepth(int bits) async {
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            btBitDepth: bits,
          ),
        ),
      );
    }
    final ok = await _hiResAudioService.setBluetoothBitDepth(bits);
    await refreshOutputDevice();
    return ok;
  }

  Future<bool> setBluetoothLdacQuality(int mode) async {
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            btLdacQualityMode: mode,
          ),
        ),
      );
    }
    final ok = await _hiResAudioService.setBluetoothLdacQuality(mode);
    await refreshOutputDevice();
    return ok;
  }

  /// Triggers a runtime BLUETOOTH_CONNECT permission request (Android 12+).
  /// Falls back to opening app settings if already permanently denied.
  Future<void> requestBluetoothPermission() async {
    await _hiResAudioService.requestBluetoothPermission();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await refreshOutputDevice();
  }

  /// Opens Android Developer Options directly to the Bluetooth Audio Codec page.
  Future<void> openBluetoothDevOptions() async {
    await _hiResAudioService.openBluetoothDevOptions();
  }

  /// Probes the native DoP capability and stores the single [dop] gate in state.
  /// Used by the device-change listener; [refreshOutputDevice] folds the same
  /// probe into its emit.
  Future<void> _refreshDopSupport() async {
    final caps = await DsdDecoderHelper.probeDopCapabilities();
    if (isClosed) return;
    if (state.dsdDopSupported != caps.canUseDop) {
      safeEmit(state.copyWith(dsdDopSupported: caps.canUseDop));
    }
  }

  Future<void> refreshOutputDevice() async {
    final info = await _hiResAudioService.getAudioOutputInfo();
    final caps = await DsdDecoderHelper.probeDopCapabilities();
    final previous = state.currentOutputDevice;
    // Drop stale DAC targets when the route changes (e.g. USB -> speaker/BT);
    // otherwise a 192k DAC request is re-sent to the phone speaker.
    final routeChanged = previous != null &&
        (previous.deviceName != info.deviceName ||
            previous.activeDeviceType != info.activeDeviceType ||
            previous.isBluetooth != info.isBluetooth ||
            previous.isUsbDac != info.isUsbDac);
    final savedSampleRate = (!routeChanged &&
            previous?.targetSampleRate != null &&
            previous!.targetSampleRate > 0)
        ? previous.targetSampleRate
        : 0;
    final savedBitDepth = (!routeChanged &&
            previous?.targetBitDepth != null &&
            previous!.targetBitDepth > 0)
        ? previous.targetBitDepth
        : 0;

    if (isClosed) return;
    safeEmit(
      state.copyWith(
        currentOutputDevice: info.copyWith(
          targetSampleRate: info.targetSampleRate != 0
              ? info.targetSampleRate
              : savedSampleRate,
          targetBitDepth:
              info.targetBitDepth != 0 ? info.targetBitDepth : savedBitDepth,
        ),
        dsdDopSupported: caps.canUseDop,
      ),
    );
  }

  Future<void> setDspPreference(String preference) async {
    safeEmit(state.copyWith(dspPreference: preference));
    // EqualizerManager is the single writer for effect keys (including
    // dspPreference). Only persist directly when it is unavailable.
    if (getIt.isRegistered<EqualizerManager>()) {
      await getIt<EqualizerManager>().setDspPreference(preference);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsCubit._keyDspPreference, preference);
    await AudioEffectsChannel().setDspPreference(preference);
  }

  Future<void> setLookaheadLimiter(
    bool enabled, {
    double? thresholdDb,
    double? releaseMs,
    double? lookaheadMs,
  }) async {
    final newEnabled = enabled;
    final newThreshold = thresholdDb ?? state.limiterThresholdDb;
    final newRelease = releaseMs ?? state.limiterReleaseMs;
    final newLookahead = lookaheadMs ?? state.limiterLookaheadMs;
    safeEmit(
      state.copyWith(
        limiterEnabled: newEnabled,
        limiterThresholdDb: newThreshold,
        limiterReleaseMs: newRelease,
        limiterLookaheadMs: newLookahead,
      ),
    );
    // EqualizerManager owns the limiter keys + persistence; delegating keeps
    // a single writer so this screen cannot diverge from the effect engine.
    if (getIt.isRegistered<EqualizerManager>()) {
      await getIt<EqualizerManager>().setLookaheadLimiter(
        newEnabled,
        thresholdDb: newThreshold,
        releaseMs: newRelease,
        lookaheadMs: newLookahead,
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.lookaheadLimiterEnabled, newEnabled);
    await prefs.setDouble(PrefsKeys.lookaheadLimiterThresholdDb, newThreshold);
    await prefs.setDouble(PrefsKeys.lookaheadLimiterReleaseMs, newRelease);
    await prefs.setDouble(
      'setting_lookahead_limiter_lookahead_ms',
      newLookahead,
    );
    await AudioEffectsChannel().setLimiterParams(
      newLookahead,
      newThreshold,
      newRelease,
    );
    await AudioEffectsChannel().setLimiterEnabled(newEnabled);
  }

  Future<void> setSystemEffectsPolicy(String policy) async {
    safeEmit(state.copyWith(systemEffectsPolicy: policy));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.systemEffectsPolicy, policy);
    try {
      final status = await AudioEffectsChannel().setSystemEffectsPolicy(
        policy,
        isHiResOrBitPerfect: state.bitPerfectOutput,
      );
      if (!isClosed) {
        safeEmit(state.copyWith(systemEffectsStatus: status));
      }
    } catch (_) {}
  }

  Future<void> refreshSystemEffectsStatus() async {
    try {
      final result = await AudioEffectsChannel().detectSystemEffects();
      final status = result['status'] as String? ?? 'unknown';
      final bundles =
          (result['detectedBundles'] as List<dynamic>?)?.cast<String>() ?? [];
      if (!isClosed) {
        safeEmit(state.copyWith(
          systemEffectsStatus: status,
          systemEffectsBundles: bundles,
        ));
      }
    } catch (_) {}
  }

  Future<void> setBluetoothLatencyOffsetMs(int offsetMs) async {
    final clamped = offsetMs.clamp(0, 500);
    safeEmit(state.copyWith(bluetoothLatencyOffsetMs: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.bluetoothLatencyOffsetMs, clamped);
  }

  /// Toggles per-session audio telemetry. The logger reads this flag on every
  /// call, so disabling takes effect immediately with no re-wiring.
  Future<void> setSessionLogEnabled(bool enabled) async {
    safeEmit(state.copyWith(sessionLogEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.audioSessionLogEnabled, enabled);
  }

  /// Opt-in per-track output-format negotiation. Off by default so the manual
  /// device-global output format is untouched unless the user asks for it.
  Future<void> setOutputFormatNegotiationEnabled(bool enabled) async {
    safeEmit(state.copyWith(outputFormatNegotiationEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.outputFormatNegotiationEnabled, enabled);
  }

  /// Opt-in AAudio Direct output (bit-perfect; the DSP processor chain is
  /// bypassed). Persisted here and pushed to every player by the player
  /// layer; takes effect for newly built sinks.
  Future<void> setAaudioOutputEnabled(bool enabled) async {
    safeEmit(state.copyWith(aaudioOutputEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.aaudioOutputEnabled, enabled);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
          enabled,
          preferExclusive: state.aaudioPreferExclusive,
          targetBufferMs: state.aaudioTargetBufferMs,
        );
      }
    } catch (_) {
      // Player not available yet; boot/observer push covers it.
    }
  }

  /// Opt-in Direct Volume Control (DVC). Pins the Android media stream to
  /// maximum and applies the composed output gain in the native float DSP path.
  /// Unavailable on non-Android and while Bit-Perfect bypass is active.
  Future<void> setDvcEnabled(bool enabled) async {
    safeEmit(state.copyWith(dvcEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.dvcEnabled, enabled);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setDvcEnabled(enabled);
      }
    } catch (_) {
      // Player not available yet; boot/observer push covers it.
    }
  }

  /// Opt-in USB DAC hardware volume control. Persisted only; the USB settings
  /// widget applies it to the attached DAC when the toggle changes.
  Future<void> setUsbHardwareVolumeEnabled(bool enabled) async {
    safeEmit(state.copyWith(usbHardwareVolumeEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.usbHardwareVolumeEnabled, enabled);
  }

  /// Resampler quality (0=Fast/linear, 1=Standard, 2=High, 3=Ultra).
  Future<void> setSincResamplerQuality(int quality) async {
    final clamped = quality.clamp(0, 3);
    safeEmit(state.copyWith(sincResamplerQuality: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.sincResamplerQuality, clamped);
    await AudioEffectsChannel().setSincResamplerQuality(clamped);
  }

  /// BPM-synced crossfade toggle. Pushed straight to the crossfade manager.
  Future<void> setBpmSyncCrossfadeEnabled(bool enabled) async {
    safeEmit(state.copyWith(bpmSyncCrossfadeEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bpmSyncCrossfadeEnabled, enabled);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setBpmSyncCrossfadeEnabled(enabled);
      }
    } catch (_) {
      // Player not available yet; boot restore covers it.
    }
  }

  /// Whether the AAudio stream should attempt EXCLUSIVE sharing first.  /// Whether the AAudio stream should attempt EXCLUSIVE sharing first.
  Future<void> setAaudioPreferExclusive(bool value) async {
    safeEmit(state.copyWith(aaudioPreferExclusive: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.aaudioPreferExclusive, value);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
          state.aaudioOutputEnabled,
          preferExclusive: value,
          targetBufferMs: state.aaudioTargetBufferMs,
        );
      }
    } catch (_) {
      // Player not available yet; boot/observer push covers it.
    }
  }

  /// Target stream buffer capacity for the AAudio path (20-1000 ms).
  /// Re-pushed to running players so it applies without toggling output.
  Future<void> setAaudioTargetBufferMs(int ms) async {
    final clamped = ms.clamp(20, 1000);
    safeEmit(state.copyWith(aaudioTargetBufferMs: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.aaudioTargetBufferMs, clamped);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
          state.aaudioOutputEnabled,
          preferExclusive: state.aaudioPreferExclusive,
          targetBufferMs: clamped,
        );
      }
    } catch (_) {
      // Player not available yet; boot/observer push covers it.
    }
  }

  /// Opt-in 24/32-bit float DSP path. Off by default: with the flag off the
  /// vendored Android fork builds the same 16-bit sink as before. When on, the
  /// preference is persisted here and pushed to every player by the player
  /// layer's settings observer (and restored on boot by the audio handler).
  Future<void> setFloatOutputEnabled(bool enabled) async {
    safeEmit(state.copyWith(floatOutputEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.floatOutputEnabled, enabled);
    // Best-effort immediate push; the player layer also observes the state.
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setFloatOutputEnabled(enabled);
      }
    } catch (_) {
      // Player not available yet; boot/observer push covers it.
    }
  }

  // ── F3/F4/F7/F8/F9/F10 ──────────────────────────────────────────────
  Future<void> setHedgedResolutionEnabled(bool v) async {
    safeEmit(state.copyWith(hedgedResolutionEnabled: v));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.hedgedResolutionEnabled, v);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setHedgedResolutionEnabled(v);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply hedged resolution live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  Future<void> setAdaptiveQualityEnabled(bool v) async {
    safeEmit(state.copyWith(adaptiveQualityEnabled: v));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.adaptiveQualityEnabled, v);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setAdaptiveQualityEnabled(v);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply adaptive quality live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  Future<void> setDuckingMode(String mode) async {
    safeEmit(state.copyWith(duckingMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.duckingMode, mode);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setDuckingMode(mode);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply ducking mode live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  Future<void> setDuckingLevel(double level) async {
    final clamped = level.clamp(0.05, 1.0);
    safeEmit(state.copyWith(duckingLevel: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PrefsKeys.duckingLevel, clamped);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setDuckingLevel(clamped);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply ducking level live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  Future<void> setMultiOutputMode(String mode) async {
    final parsed = MultiOutputMode.values.firstWhere(
      (m) => m.name == mode,
      orElse: () => MultiOutputMode.systemDefault,
    );
    final prefs = await SharedPreferences.getInstance();
    var applied = parsed == MultiOutputMode.systemDefault;
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        applied = await getIt<PulsrAudioHandler>().setMultiOutputMode(parsed);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply multi-output routing live',
          error: e, stackTrace: st, category: 'Settings');
      applied = false;
    }
    if (parsed != MultiOutputMode.systemDefault && !applied) {
      // Android cannot route media to two outputs simultaneously. Revert the
      // selection instead of persisting an option that never takes effect.
      await prefs.setString(
          PrefsKeys.multiOutputMode, MultiOutputMode.systemDefault.name);
      if (!isClosed) {
        safeEmit(state.copyWith(
          multiOutputMode: MultiOutputMode.systemDefault.name,
          errorMessage:
              'This device cannot play to two outputs at once. Output stays on System default.',
        ));
      }
      return;
    }
    await prefs.setString(PrefsKeys.multiOutputMode, parsed.name);
    safeEmit(state.copyWith(multiOutputMode: parsed.name, errorMessage: null));
  }

  Future<void> setDspSnapshotEnabled(bool v) async {
    safeEmit(state.copyWith(dspSnapshotEnabled: v));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.dspSnapshotEnabled, v);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setDspSnapshotEnabled(v);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply DSP snapshot setting live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  Future<void> setSilenceSkipSensitivity(int v) async {
    final clamped = v.clamp(0, 100);
    safeEmit(state.copyWith(silenceSkipSensitivity: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.silenceSkipSensitivity, clamped);
  }

  /// F5: Bluetooth latency auto-calibration. Uses the codec latency table
  /// plus optional probe samples, then persists the winning offset.
  Future<int> autoCalibrateBluetoothLatency({Future<int> Function()? probe}) async {
    final codec = state.currentOutputDevice?.btCodecName;
    int codecEst = 180;
    try {
      const table = {
        'sbc': 220, 'aac': 200, 'aptx': 150, 'ldac': 250,
        'lc3': 60, 'opus': 100, 'lhdc': 180,
      };
      if (codec != null && codec.isNotEmpty) {
        final key = codec.toLowerCase();
        for (final e in table.entries) {
          if (key.contains(e.key)) {
            codecEst = e.value;
            break;
          }
        }
      }
    } catch (_) {}
    var combined = codecEst;
    if (probe != null) {
      final vals = <int>[];
      for (var i = 0; i < 5; i++) {
        try {
          final v = await probe();
          if (v >= 0 && v <= 1000) vals.add(v);
        } catch (_) {}
      }
      if (vals.isNotEmpty) {
        vals.sort();
        final trimmed =
            vals.length >= 4 ? vals.sublist(1, vals.length - 1) : vals;
        final avg = (trimmed.reduce((a, b) => a + b) / trimmed.length).round();
        combined = (codecEst * 0.6 + avg * 0.4).round();
      }
    }
    final clamped = combined.clamp(0, 500);
    await setBluetoothLatencyOffsetMs(clamped);
    return clamped;
  }

  /// Applies the "Maximum Quality" audiophile preset:
  /// Bit-perfect mode enabled, all DSP/EQ/ReplayGain/crossfade bypassed, gapless active.
  Future<void> applyMaximumQualityPreset() async {
    await setBitPerfectOutput(true);
    await setBypassDspOnBitPerfect(true);
    await setReplayGainMode(ReplayGainMode.off);
    await setGapless(true);
  }

  /// Applies the "Smooth Playback" preset:
  /// Standard crossfade, auto ReplayGain, adaptive buffering.
  Future<void> applySmoothPlaybackPreset() async {
    await setBitPerfectOutput(false);
    await setReplayGainMode(ReplayGainMode.auto);
    await setCrossfade(4.0);
  }

  /// Applies the "Poor Network" preset:
  /// Conservative data usage, zero crossfade, lower bitrate.
  Future<void> applyPoorNetworkPreset() async {
    await setCrossfade(0.0);
    await setGapless(false);
    await setStreamingQuality(YtmAudioQuality.low);
  }




















  // Requires: provided by the composing class (same library).
  HiResAudioService get _hiResAudioService;

  // Requires: provided by the composing class (same library).
  Future<void> setCrossfade(double seconds);

  // Requires: provided by the composing class (same library).
  Future<void> setGapless(bool value);
}
