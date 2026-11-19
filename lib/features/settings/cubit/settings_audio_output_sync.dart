part of 'settings_cubit.dart';

/// Output-route synchronization split out of [SettingsAudioActions] to keep
/// that mixin under its decomposition ratchet.
///
/// These methods share the mixin's private state (`_refreshOutputSeq`,
/// `_lastTapSrcTargetRate`, `_hiResAudioService`) because they are part of the
/// same library; the extension only moves the code.
extension SettingsAudioOutputSync on SettingsAudioActions {
  Future<void> refreshOutputDevice() async {
    final seq = ++_refreshOutputSeq;
    // FIX-C02: Guard against native crash or unhandled exception during device/DOP refresh
    try {
      var info = await _hiResAudioService.getAudioOutputInfo();
      final caps = await DsdDecoderHelper.probeDopCapabilities();
      if (isClosed || seq != _refreshOutputSeq) return;
      if (_bitPerfectViaDirectStream &&
          _lastDirectUsbFailure != null &&
          !info.isBitPerfectActive) {
        info = info.copyWith(bitPerfectFailureReason: _lastDirectUsbFailure);
      }
      safeEmit(
        state.copyWith(
          currentOutputDevice: info,
          dsdDopSupported: caps.canUseDop,
        ),
      );
      await _syncTapSrcRate(info);
      await _syncDynamicOutputBuffer(info);
    } catch (e, st) {
      ErrorLogger.log('Failed to refresh output device or probe DoP',
          error: e, stackTrace: st, category: 'Settings');
      return;
    }
  }

  /// Runs a Bit-Perfect / DSP-bypass transition with playback parked on a
  /// buffer boundary, suppressing intermediate tap-SRC flips so the sink is
  /// rebuilt at most once before playback resumes.
  Future<void> runSinkTransitionMuted({
    required bool disarmTapSrc,
    required Future<void> Function() body,
    bool syncTapSrcAfter = false,
  }) async {
    final handler = getIt.isRegistered<PulsrAudioHandler>()
        ? getIt<PulsrAudioHandler>()
        : null;
    var wasPlaying = false;
    if (handler != null) {
      try {
        wasPlaying = handler.playbackState.value.playing;
      } catch (_) {
        // A handler that cannot report its transport (early boot, test
        // doubles) is treated as paused: resuming on a guess would be worse
        // than the unmuted swap this envelope removes.
      }
    }
    if (wasPlaying) {
      try {
        await handler!.pause();
      } catch (_) {
        // Keep applying the policy; a failed pause only costs the mute.
      }
    }
    final prevSuppress = _suppressTapSrcSync;
    _suppressTapSrcSync = true;
    try {
      if (disarmTapSrc) await _disarmTapSrcRate();
      await body();
      if (syncTapSrcAfter) {
        // Push the final tap-SRC target ONCE before the single sink rebuild so
        // no secondary async requestModeChange races with play().
        _suppressTapSrcSync = false;
        await _syncTapSrcRate(state.currentOutputDevice);
        _suppressTapSrcSync = true;
      }
      // The bypass is latched by the sink's configure(), so a mid-track toggle
      // needs one rebuild to engage (or release) the integer path for THIS
      // track; without it the platform keeps reporting the mixer as inactive
      // until the next track. Still inside the pause, so the rebuild is silent.
      await handler?.reconfigurePlaybackSink();
    } finally {
      _suppressTapSrcSync = prevSuppress;
      if (wasPlaying) {
        try {
          await handler!.play();
        } catch (_) {
          // Resume is best-effort: the policy change itself already landed.
        }
      }
    }
    // Re-read the device AFTER resume so the published mixer/bypass/rate truth
    // reflects the live rebuilt AudioTrack instead of a paused [0,0,0] snapshot.
    if (handler != null) await refreshOutputDevice();
  }

  /// Runs the Bit-Perfect policy with the transport parked on a buffer
  /// boundary.
  ///
  /// The exclusive-mode swap and the native bypass flip both land at an
  /// arbitrary sample when issued mid-buffer, which is audible as a click or
  /// pop. `pause()` stops on a buffer boundary, so neither change can be
  /// heard, and `play()` resumes from the same position. This is deliberately
  /// not `withSmoothDspTransition`: that mutes the native processor, and the
  /// integer bit-perfect bypass runs no processor at all, so there is nothing
  /// for it to mute.
  Future<void> applyBitPerfectPolicyMuted(
    bool enabled, {
    bool keepPreferenceWhenDisabling = false,
  }) =>
      runSinkTransitionMuted(
        disarmTapSrc: enabled,
        syncTapSrcAfter: !enabled,
        body: () => _applyBitPerfectPolicy(
          enabled,
          keepPreferenceWhenDisabling: keepPreferenceWhenDisabling,
        ),
      );

  /// Runs the Strict Bit-Perfect policy through the same muted rebuild
  /// envelope so enabling/disabling Strict mid-track disarms tap-SRC, rebuilds
  /// the sink cleanly, and aligns the current track format.
  Future<void> applyStrictBitPerfectMuted(bool enabled) =>
      runSinkTransitionMuted(
        disarmTapSrc: enabled,
        syncTapSrcAfter: !enabled && !state.bitPerfectOutput,
        body: () => _applyStrictBitPerfectPolicy(enabled),
      );

  /// Runs a DSP-bypass-on-Bit-Perfect toggle through the muted rebuild
  /// envelope when Bit-Perfect is active, so the integer bypass engages or
  /// releases on the current track immediately.
  Future<void> applyBypassDspOnBitPerfectMuted(bool enabled) async {
    if (!state.bitPerfectOutput) {
      await _applyBypassDspOnBitPerfectPolicy(enabled);
      return;
    }
    await runSinkTransitionMuted(
      disarmTapSrc: enabled,
      body: () => _applyBypassDspOnBitPerfectPolicy(enabled),
    );
  }

  /// Body of `SettingsAudioActions.applyMaximumQualityPreset`, run while the
  /// mixin holds its audio-mode mutex: a concurrent user toggle can no longer
  /// interleave with the sequence. Every step uses the unlocked owner where one
  /// exists (awaiting a locked wrapper here would wait on a mutex this isolate
  /// already holds); `setFloatOutputEnabled`, `setCrossfade`,
  /// `setSilenceSkipSensitivity`, `setGapless` and `setReplayGainMode` take no
  /// lock at all. This lives here for the same reason as the rest of the file:
  /// the mixin is under a size ratchet.
  ///
  /// Depth first: with the float DSP path off Media3 inserts a 16-bit converter
  /// ahead of the native chain, so a 24/32-bit source would reach the DAC as
  /// 16-bit no matter what Bit-Perfect later reports. AAudio replaces the
  /// ExoPlayer sink the direct UAC2 tee lives in, so a USB DAC prefers the tee.
  /// Every step is conditional on the one before it actually applying: when the
  /// platform refuses exclusive output, silently bypassing the user's EQ and
  /// gain would leave a chain with no processing and no Bit-Perfect either.
  Future<void> runMaximumQualityPreset() async {
    if (!state.floatOutputEnabled) {
      await setFloatOutputEnabled(true);
    }
    if (state.aaudioOutputEnabled &&
        state.currentOutputDevice?.isUsbDac == true) {
      await _setAaudioOutputEnabled(false);
      if (state.aaudioOutputEnabled) return;
    }
    await _setBitPerfectOutput(true);
    if (!state.bitPerfectOutput) return;
    await _setBypassDspOnBitPerfect(true);
    if (!state.bypassDspOnBitPerfect) return;
    // These stages edit or overlap the stream; a bit-exact claim cannot coexist
    // with them. Order: crossfade before gapless (gapless refuses a non-zero
    // crossfade), silence skip before it is re-armed anywhere.
    await setCrossfade(0.0);
    if (state.silenceSkipSensitivity > 0) {
      await setSilenceSkipSensitivity(0);
    }
    await setGapless(true);
    await setReplayGainMode(ReplayGainMode.off);
  }

  /// Pushes an explicit "no resampling" target ahead of a Bit-Perfect enable.
  ///
  /// A resampler left armed by the previous route converts the source ahead of
  /// the native chain, and the route refresh cannot be trusted to clear it
  /// here: it decides from the platform echo, which reads false while paused
  /// or mid-swap. Never throws; the transport change that follows matters more.
  Future<void> _disarmTapSrcRate() async {
    if (!getIt.isRegistered<PulsrAudioHandler>()) return;
    try {
      await getIt<PulsrAudioHandler>().setTapSrcRate(0);
      _lastTapSrcTargetRate = 0;
    } catch (e, st) {
      ErrorLogger.log('Failed to disarm tap-side SRC for Bit-Perfect',
          error: e, stackTrace: st, category: 'SettingsAudioActions');
    }
  }

  /// Keeps the tap-side SRC target on the route's mixer rate.
  ///
  /// This is what stops AudioFlinger from resampling the *finished* DSP: with a
  /// target set, the PCM tap converts to the mixer rate at Ultra quality ahead
  /// of the chain, so the mixer becomes a 1:1 copy. A route whose rate cannot be
  /// verified keeps the historical platform path; this never throws.
  Future<void> _syncTapSrcRate(AudioOutputInfo? info) async {
    if (_suppressTapSrcSync) return;
    if (!getIt.isRegistered<PulsrAudioHandler>()) return;
    // PROPERTY_OUTPUT_SAMPLE_RATE (`nativeSampleRate`) describes the primary
    // built-in/wired mixer, NOT USB DACs (whose HAL negotiates per-track rates)
    // and NOT Bluetooth. Never pass `info.sampleRate`: that is the app's own
    // AudioTrack rate, which previously fed a previous track's rate back as an
    // SRC target and triggered mid-playback sink swaps / rate glitches.
    final isPrimaryOutput = info != null && !info.isUsbDac && !info.isBluetooth;
    final mixerRate = isPrimaryOutput ? (info.nativeSampleRate ?? 0) : 0;
    final rate = decideTapSrcTargetRate(
      enabled: state.outputFormatNegotiationEnabled,
      nativeSampleRate: mixerRate,
      // Decide from the REQUEST, not the polled echo: `isBitPerfectActive`
      // reads false while paused and during the enable transition, which used
      // to leave a resampler armed inside a bit-perfect session. Pulsr's own
      // UAC2 sink is bit-perfect by construction and disarms it as well.
      bitPerfectActive: state.bitPerfectOutput ||
          _bitPerfectViaDirectStream ||
          (info?.isBitPerfectActive ?? false),
      isBluetooth: info?.isBluetooth ?? false,
      deviceSampleRates: info?.supportedSampleRates ?? const <int>[],
    );
    if (rate == _lastTapSrcTargetRate) return;
    _lastTapSrcTargetRate = rate;
    try {
      await getIt<PulsrAudioHandler>().setTapSrcRate(rate);
    } catch (e, st) {
      _lastTapSrcTargetRate = null;
      ErrorLogger.log('Failed to sync tap-side SRC rate ($rate)',
          error: e, stackTrace: st, category: 'Settings');
    }
  }

  /// Dynamically raises the sink target buffer duration when streaming over a
  /// high-bitrate Bluetooth codec (LDAC 990kbps / aptX Lossless / LHDC) so the
  /// OS A2DP queue does not underrun, while preserving the user's configured
  /// floor when higher.
  Future<void> _syncDynamicOutputBuffer(AudioOutputInfo? info) async {
    if (info == null || !getIt.isRegistered<PulsrAudioHandler>()) return;
    if (!info.isBt) return;
    final rec = recommendedBluetoothBufferMs(
      codecName: info.btCodecName,
      bitrateKbps: info.btEstimatedBitrateKbps,
      sampleRateHz: info.btSampleRateHz ?? info.sampleRate,
      isLeAudio: info.isLeAudio,
    );
    final effectiveBuffer =
        rec > state.aaudioTargetBufferMs ? rec : state.aaudioTargetBufferMs;
    if (effectiveBuffer == state.aaudioTargetBufferMs) return;
    try {
      await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
        state.aaudioOutputEnabled,
        preferExclusive: state.aaudioPreferExclusive,
        targetBufferMs: effectiveBuffer,
      );
    } catch (e, st) {
      ErrorLogger.log(
          'Failed to apply dynamic BT buffer (${effectiveBuffer}ms)',
          error: e,
          stackTrace: st,
          category: 'Settings');
    }
  }
}
