part of 'settings_cubit.dart';

/// Bluetooth, DSP, AAudio/DVC, playback feature toggles, and audio presets
/// split out of [SettingsAudioActions] to keep each file cohesive and well
/// below the size ratchet.
mixin SettingsAudioDspActions on PulsrCubit<SettingsState>, SettingsAudioActions {
  /// Returns true when the platform accepted the request; false means the
  /// stock ROM refused it (SystemApi) — caller must offer Developer Options.
  Future<bool> setBluetoothCodec(String codec) async {
    // Optimistic UI: update btCodecName immediately
    final ok = await _hiResAudioService.setBluetoothCodec(codec);
    await refreshOutputDevice();
    return ok;
  }

  Future<bool> setBluetoothSampleRate(int hz) async {
    final ok = await _hiResAudioService.setBluetoothSampleRate(hz);
    await refreshOutputDevice();
    return ok;
  }

  Future<bool> setBluetoothBitDepth(int bits) async {
    final ok = await _hiResAudioService.setBluetoothBitDepth(bits);
    await refreshOutputDevice();
    return ok;
  }

  Future<bool> setBluetoothLdacQuality(int mode) async {
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

  /// Opens the platform screen where the Bluetooth audio codec can be changed
  /// (Bluetooth settings first, then Developer Options). Retail builds cannot
  /// write the codec directly, so this is the sanctioned deep-link.
  Future<bool> openBluetoothCodecSettings() async {
    final opened = await _hiResAudioService.openBluetoothCodecSettings();
    if (!opened) {
      safeEmit(state.copyWith(
          error: uiError(L10nHolder.current?.cannotOpenBluetoothCodecSettings ??
              'Could not open Bluetooth codec settings.')));
    }
    return opened;
  }

  /// Opt-in Bluetooth Hi-Res (best-effort). Bluetooth is a lossy codec link, so
  /// this can never be bit-perfect; it stops the app from making the link worse:
  ///   * item 1 - keeps the float DSP path on so 24/32-bit samples are not
  ///     truncated to 16-bit in-app before the codec encoder;
  ///   * item 5 - permits the native TPDF dither stage on BT at the codec depth;
  ///   * item 3 - the per-track codec-rate alignment is driven by the player
  ///     (see PlayerDspController.maybeFollowTrackSampleRate).
  Future<void> setBluetoothHiResEnabled(bool enabled) async {
    markDirty('bluetoothHiResEnabled');
    safeEmit(state.copyWith(bluetoothHiResEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bluetoothHiResEnabled, enabled);
    // Item 1: never truncate to 16-bit before the codec encoder.
    if (enabled && !state.floatOutputEnabled) {
      await setFloatOutputEnabled(true);
    }
    // Item 5: mirror the dither-on-BT permission into the effects layer so every
    // later dither push (and route resync) carries it.
    if (getIt.isRegistered<EqualizerManager>()) {
      final eq = getIt<EqualizerManager>();
      eq.isBluetoothDitherEnabled = enabled;
      if (eq.isDitherEnabled) {
        await eq.setDither(true, allowBluetoothDither: enabled);
      }
    }
  }

  Future<void> setDspPreference(String preference) async {
    markDirty('dspPreference');
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
    markDirty('limiterEnabled');
    markDirty('limiterThresholdDb');
    markDirty('limiterReleaseMs');
    markDirty('limiterLookaheadMs');
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
    markDirty('systemEffectsPolicy');
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
    } catch (e) {
      ErrorLogger.logSwallowed('SettingsAudioDspActions.setSystemEffectsPolicy', e);
    }
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
    } catch (e) {
      ErrorLogger.logSwallowed(
          'SettingsAudioDspActions.refreshSystemEffectsStatus', e);
    }
  }

  Future<void> setBluetoothLatencyOffsetMs(int offsetMs) async {
    markDirty('bluetoothLatencyOffsetMs');
    final clamped = offsetMs.clamp(0, 500);
    safeEmit(state.copyWith(bluetoothLatencyOffsetMs: clamped));
    final device = state.currentOutputDevice;
    if (device != null && device.isBluetooth) {
      _lastBtLatencyDeviceKey = DeviceProfileService.deviceKeyFromInfo(device);
      await _deviceProfileService.rememberBtLatency(
          _lastBtLatencyDeviceKey!, clamped);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(PrefsKeys.bluetoothLatencyOffsetMs, clamped);
    }
  }

  /// Toggles per-session audio telemetry. The logger reads this flag on every
  /// call, so disabling takes effect immediately with no re-wiring.
  Future<void> setSessionLogEnabled(bool enabled) async {
    markDirty('sessionLogEnabled');
    safeEmit(state.copyWith(sessionLogEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.audioSessionLogEnabled, enabled);
  }

  /// Per-track output-format negotiation, on by default. Also the gate for
  /// tap-side SRC: with it on, a track whose rate the mixer will not run at is
  /// converted in-app ahead of the DSP chain instead of by AudioFlinger after
  /// it, so turning this off restores the platform-resample path entirely.
  @override
  Future<void> setOutputFormatNegotiationEnabled(bool enabled) async {
    markDirty('outputFormatNegotiationEnabled');
    safeEmit(state.copyWith(outputFormatNegotiationEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.outputFormatNegotiationEnabled, enabled);
    await _syncTapSrcRate(state.currentOutputDevice);
  }

  /// Opt-in AAudio Direct output (bit-perfect; the DSP processor chain is
  /// bypassed). Persisted here and pushed to every player by the player
  /// layer; takes effect for newly built sinks.
  Future<void> setAaudioOutputEnabled(bool enabled) =>
      _audioModeMutex.protect(() => _setAaudioOutputEnabled(enabled));

  @override
  Future<void> _setAaudioOutputEnabled(bool enabled) async {
    markDirty('aaudioOutputEnabled');
    if (enabled) {
      // AAudio Direct bypasses the ExoPlayer DSP chain the direct-USB
      // Bit-Perfect tee lives in; enabling it would silence the DAC.
      if (_bitPerfectViaDirectStream) {
        safeEmit(state.copyWith(
            error: uiError(
                'Turn off Bit-Perfect before enabling AAudio Direct.')));
        return;
      }
    }
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        final applied = await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
          enabled,
          preferExclusive: state.aaudioPreferExclusive,
          targetBufferMs: state.aaudioTargetBufferMs,
        );
        if (!applied) {
          await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
            state.aaudioOutputEnabled,
            preferExclusive: state.aaudioPreferExclusive,
            targetBufferMs: state.aaudioTargetBufferMs,
          );
          safeEmit(state.copyWith(
              error:
                  uiError('AAudio output was rejected by a playback player.')));
          return;
        }
      }
    } catch (e) {
      safeEmit(
          state.copyWith(error: uiError('Failed to change AAudio output: $e')));
      return;
    }
    // Only after every player accepted the change: turning crossfade and DVC
    // off beforehand discarded settings for a mode that never came on.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.aaudioOutputEnabled, enabled);
    safeEmit(state.copyWith(aaudioOutputEnabled: enabled, error: null));
    if (enabled) {
      await _forceCrossfadeOff(
          reason: 'Crossfade disabled: AAudio Direct bypasses the DSP chain it '
              'is applied in.');
      if (state.dvcEnabled) await setDvcEnabled(false);
    }
  }

  /// Opt-in Direct Volume Control (DVC). Pins the Android media stream to
  /// maximum and applies the composed output gain in the native float DSP path.
  /// Unavailable on non-Android and while Bit-Perfect bypass is active.
  @override
  Future<void> setDvcEnabled(bool enabled) async {
    if (enabled &&
        (state.aaudioOutputEnabled ||
            (state.bitPerfectOutput && state.bypassDspOnBitPerfect))) {
      safeEmit(state.copyWith(
          error: uiError(
              'Direct Volume Control requires the active DSP output path.')));
      return;
    }
    markDirty('dvcEnabled');
    safeEmit(state.copyWith(dvcEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.dvcEnabled, enabled);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setDvcEnabled(enabled);
      }
    } catch (e) {
      // Player not available yet; boot/observer push covers it.
      ErrorLogger.logSwallowed('SettingsAudioDspActions.setDvcEnabled', e);
    }
  }

  Future<bool> setUsbHardwareVolumeEnabled(bool enabled) async {
    markDirty('usbHardwareVolumeEnabled');
    try {
      safeEmit(state.copyWith(usbHardwareVolumeEnabled: enabled));
      final prefs = await SharedPreferences.getInstance();
      final saved =
          await prefs.setBool(PrefsKeys.usbHardwareVolumeEnabled, enabled);
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().syncUsbHardwareVolumeState(enabled);
      } else if (!enabled) {
        await UsbExclusiveService().resetHardwareVolume();
      }
      return saved;
    } catch (e) {
      ErrorLogger.logSwallowed(
          'SettingsAudioDspActions.setUsbHardwareVolumeEnabled', e);
      return false;
    }
  }

  /// Resampler quality (0=Fast/linear, 1=Standard, 2=High, 3=Ultra).
  Future<void> setSincResamplerQuality(int quality) async {
    if (!AudioEffectsChannel().isPlaybackSincResamplerSupported) return;
    markDirty('sincResamplerQuality');
    final clamped = quality.clamp(0, 3);
    safeEmit(state.copyWith(sincResamplerQuality: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.sincResamplerQuality, clamped);
    await AudioEffectsChannel().setSincResamplerQuality(clamped);
  }

  /// BPM-synced crossfade toggle. Pushed straight to the crossfade manager.
  Future<void> setBpmSyncCrossfadeEnabled(bool enabled) async {
    markDirty('bpmSyncCrossfadeEnabled');
    safeEmit(state.copyWith(bpmSyncCrossfadeEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bpmSyncCrossfadeEnabled, enabled);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setBpmSyncCrossfadeEnabled(enabled);
      }
    } catch (e) {
      // Player not available yet; boot restore covers it.
      ErrorLogger.logSwallowed(
          'SettingsAudioDspActions.setBpmSyncCrossfadeEnabled', e);
    }
  }

  /// Automix / Smart Transitions toggle. Pushed straight to the crossfade manager.
  Future<void> setAutomixEnabled(bool enabled) async {
    markDirty('automixEnabled');
    safeEmit(state.copyWith(automixEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.automixEnabled, enabled);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setAutomixEnabled(enabled);
      }
    } catch (e) {
      // Player not available yet; boot restore covers it.
      ErrorLogger.logSwallowed('SettingsAudioDspActions.setAutomixEnabled', e);
    }
  }

  /// Whether the AAudio stream should attempt EXCLUSIVE sharing first.
  ///
  /// Serialized with [setAaudioOutputEnabled] and reading the enabled flag
  /// inside that lock: pushing the value the state held *before* an in-flight
  /// toggle would undo it.
  Future<void> setAaudioPreferExclusive(bool value) =>
      _audioModeMutex.protect(() async {
        markDirty('aaudioPreferExclusive');
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
        } catch (e) {
          // Player not available yet; boot/observer push covers it.
          ErrorLogger.logSwallowed(
              'SettingsAudioDspActions.setAaudioPreferExclusive', e);
        }
      });

  /// Target stream buffer capacity for the AAudio path (8-1000 ms).
  /// Re-pushed to running players so it applies without toggling output.
  ///
  /// Practical guidance:
  ///  - USB-C / wired DAC: 8–20 ms for lowest seek latency.
  ///  - Bluetooth A2DP:    150–300 ms to absorb codec/stack jitter.
  Future<void> setAaudioTargetBufferMs(int ms) =>
      _audioModeMutex.protect(() async {
        markDirty('aaudioTargetBufferMs');
        // Minimum 8 ms: achievable on USB-C DACs at 48 kHz (≈384 frames).
        // Maximum 1000 ms: generous headroom for worst-case BT stacks.
        final clamped = ms.clamp(8, 1000);
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
        } catch (e) {
          // Player not available yet; boot/observer push covers it.
          ErrorLogger.logSwallowed(
              'SettingsAudioDspActions.setAaudioTargetBufferMs', e);
        }
      });

  /// Opt-in 24/32-bit float DSP path. Off by default: with the flag off the
  /// vendored Android fork builds the same 16-bit sink as before. When on, the
  /// preference is persisted here and pushed to every player by the player
  /// layer's settings observer (and restored on boot by the audio handler).
  @override
  Future<void> setFloatOutputEnabled(bool enabled) async {
    if (!enabled && state.strictBitPerfect) {
      safeEmit(state.copyWith(
          error:
              uiError('Strict Bit-Perfect requires full decoder precision.')));
      return;
    }
    markDirty('floatOutputEnabled');
    safeEmit(state.copyWith(floatOutputEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.floatOutputEnabled, enabled);
    // Best-effort immediate push; the player layer also observes the state.
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setFloatOutputEnabled(enabled);
      }
    } catch (e) {
      // Player not available yet; boot/observer push covers it.
      ErrorLogger.logSwallowed(
          'SettingsAudioDspActions.setFloatOutputEnabled', e);
    }
  }

  // ── F3/F4/F7/F8/F9/F10 ──────────────────────────────────────────────
  Future<void> setHedgedResolutionEnabled(bool v) async {
    markDirty('hedgedResolutionEnabled');
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
    markDirty('adaptiveQualityEnabled');
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
    markDirty('duckingMode');
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
    markDirty('duckingLevel');
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
    markDirty('multiOutputMode');
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
      // FIX-M06: Emit systemDefault before prefs write to ensure UI updates immediately even if disk write hangs
      if (!isClosed) {
        safeEmit(state.copyWith(
          multiOutputMode: MultiOutputMode.systemDefault.name,
          error: uiError(
              'This device cannot play to two outputs at once. Output stays on System default.'),
        ));
      }
      await prefs.setString(
          PrefsKeys.multiOutputMode, MultiOutputMode.systemDefault.name);
      return;
    }
    await prefs.setString(PrefsKeys.multiOutputMode, parsed.name);
    safeEmit(state.copyWith(multiOutputMode: parsed.name, error: null));
  }

  Future<void> setDspSnapshotEnabled(bool v) async {
    markDirty('dspSnapshotEnabled');
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

  @override
  Future<void> setSilenceSkipSensitivity(int v) async {
    markDirty('silenceSkipSensitivity');
    final clamped = v.clamp(0, 100);
    if (clamped > 0) {
      final blocked = AudioConflicts.silenceSkipBlockedByBitPerfect(
        bitPerfectOutput: state.bitPerfectOutput,
        bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
        device: state.currentOutputDevice,
      );
      if (blocked != null) {
        safeEmit(state.copyWith(error: uiError(blocked)));
        return;
      }
    }
    safeEmit(state.copyWith(silenceSkipSensitivity: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.silenceSkipSensitivity, clamped);
    // B17: apply live so the slider actually drives the native silence skipper
    // instead of only persisting a value.
    try {
      await getIt<PulsrAudioHandler>().setSilenceSkipSensitivity(clamped);
    } catch (e, st) {
      ErrorLogger.log('Failed to apply silence-skip sensitivity live',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  /// F5: Bluetooth latency auto-calibration. Uses the codec latency table
  /// plus optional probe samples, then persists the winning offset.
  Future<int> autoCalibrateBluetoothLatency(
      {Future<int> Function()? probe}) async {
    final codec = state.currentOutputDevice?.btCodecName;
    int codecEst = 180;
    try {
      const table = {
        'sbc': 220,
        'aac': 200,
        'aptx': 150,
        'ldac': 250,
        'lc3': 60,
        'opus': 100,
        'lhdc': 180,
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
    } catch (e) {
      ErrorLogger.logSwallowed(
          'SettingsAudioDspActions.autoCalibrateBluetoothLatency.codec', e);
    }
    var combined = codecEst;
    if (probe != null) {
      final vals = <int>[];
      for (var i = 0; i < 5; i++) {
        try {
          final v = await probe();
          if (v >= 0 && v <= 1000) vals.add(v);
        } catch (e) {
          ErrorLogger.logSwallowed(
              'SettingsAudioDspActions.autoCalibrateBluetoothLatency.probe', e);
        }
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

  /// Applies the "Maximum Quality" audiophile preset: Bit-perfect output, then
  /// the DSP bypass, ReplayGain off and gapless. Every step is conditional on
  /// the one before it actually applying: when the platform refuses exclusive
  /// output, silently bypassing the user's EQ and gain would leave a chain with
  /// no processing and no bit-perfect either.
  Future<void> applyMaximumQualityPreset() =>
      _audioModeMutex.protect(() async {
        await SettingsAudioOutputSync(this).runMaximumQualityPreset();
      });

  /// Applies the "Smooth Playback" preset: no bit-perfect, automatic
  /// ReplayGain and a 4 s crossfade. Gapless is turned off first because
  /// crossfade is refused while gapless is on, and nothing here adapts the
  /// buffer (that is the separate "adaptive quality" toggle).
  Future<void> applySmoothPlaybackPreset() async {
    await setBitPerfectOutput(false);
    await setGapless(false);
    await setCrossfade(4.0);
    await setReplayGainMode(ReplayGainMode.auto);
  }

  /// Applies the "Poor Network" preset:
  /// Conservative data usage, zero crossfade, lower bitrate.
  Future<void> applyPoorNetworkPreset() async {
    await setCrossfade(0.0);
    await setGapless(false);
    await setStreamingQuality(YtmAudioQuality.low);
  }
}
