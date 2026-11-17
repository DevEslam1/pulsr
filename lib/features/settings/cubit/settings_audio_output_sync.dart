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

  /// Keeps the tap-side SRC target on the route's mixer rate.
  ///
  /// This is what stops AudioFlinger from resampling the *finished* DSP: with a
  /// target set, the PCM tap converts to the mixer rate at Ultra quality ahead
  /// of the chain, so the mixer becomes a 1:1 copy. A route whose rate cannot be
  /// verified keeps the historical platform path; this never throws.
  Future<void> _syncTapSrcRate(AudioOutputInfo? info) async {
    if (!getIt.isRegistered<PulsrAudioHandler>()) return;
    final rate = decideTapSrcTargetRate(
      enabled: state.outputFormatNegotiationEnabled,
      // PROPERTY_OUTPUT_SAMPLE_RATE describes the primary output, not the
      // current USB/BT route. Only a live route-specific sink is usable here.
      nativeSampleRate: info?.availableDevices.any((d) => d.isCurrent) == true
          ? (info?.sampleRate ?? 0)
          : 0,
      bitPerfectActive: info?.isBitPerfectActive ?? false,
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
