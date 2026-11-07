part of 'player_dsp_controller.dart';

extension PlayerDspFollowRate on PlayerDspController {
  /// [H-18] Serializes concurrent follow-rate requests (e.g. rapid track
  /// changes) through a mutex so overlapping native output-format switches
  /// apply in strict order instead of racing one another.
  Future<void> maybeFollowTrackSampleRate(SongsTableData song) async {
    // Track start: re-evaluate codec-aware music compensation (fix #2) so each
    // new track picks up the current route's codec adaptation (and so a route
    // whose EQ base changed between tracks is re-merged). Fire-and-forget and
    // idempotent; no-ops on non-lossy / ultra-HQ / wired routes.
    unawaited(applyCodecAwareMusicCompensation());
    final service = _hiResAudioService;
    if (service == null || _settingsCubit == null) return;
    await _followSampleRateMutex.protect(() async {
      final settings = _settingsCubit!.state;
      // The user's "Per-Track Output Format Negotiation" switch is the master
      // gate: off means keep one manual/manufacturer output format for the
      // whole session instead of renegotiating per track. Strict bit-perfect
      // promises the track's own format, so it cannot be silently muted by
      // that switch.
      if (!settings.outputFormatNegotiationEnabled && !settings.strictBitPerfect) {
        return;
      }
      // Bluetooth Hi-Res: the A2DP link owns the format, so exclusive
      // bit-perfect is impossible, but when the codec advertises the track's
      // native rate we can ask it to switch — avoiding an unnecessary platform
      // resample. Never claims bit-perfect (BT is lossy).
      if (settings.bluetoothHiResEnabled &&
          settings.currentOutputDevice?.isBluetooth == true) {
        await _maybeAlignBluetoothCodecRate(song);
        return;
      }
      // The native side only accepts a target output format while exclusive
      // Bit-Perfect is requested. Without it the call is a guaranteed failure
      // plus a device refresh, so skip the whole round-trip (this is the
      // default state: follow-track defaults ON, Bit-Perfect OFF).
      if (!settings.bitPerfectOutput) return;
      final depth = (song.bitDepth != null && song.bitDepth! > 0)
          ? song.bitDepth!
          : PlayerConstants.defaultBitDepth;
      final device = settings.currentOutputDevice;
      // The mode belongs in the dedup key: switching Bit-Perfect off and on
      // reopens the output, so the previous confirmation is no longer valid.
      final route =
          '${device?.deviceName}|${device?.activeDeviceType}|${device?.isUsbDac}'
          '|${settings.bitPerfectOutput}|${settings.strictBitPerfect}';
      final rate = HiResAudioService.followTrackRateToApply(
        trackSampleRate: song.sampleRate,
        lastRequestedSampleRate:
            depth == _lastFollowedBitDepth && route == _lastFollowedRoute
                ? _lastFollowedSampleRate
                : null,
        isBluetooth: settings.currentOutputDevice?.isBluetooth == true,
        followTrackEnabled:
            settings.followTrackSampleRate || settings.strictBitPerfect,
      );
      if (rate == null) return;
      // The direct UAC2 sink (Bit-Perfect fallback) switches rate by
      // re-starting the isochronous stream; the platform mixer attributes are
      // not involved on that path.
      final usb = UsbExclusiveService();
      final directStreaming = usb.lastStatus.streamingActive;
      // Ownership survives a per-track suspend: the stream is stopped but the
      // preference and the sink claim stay armed for the next supported track.
      // The rate guard and the advertised-rate source must follow ownership,
      // not just the live stream, or a suspended session would renegotiate
      // against the mixer's caps and restart the sink at a rate the tee cannot
      // honour (the UAC2 path forwards decoded PCM with no resampler).
      bool directOwned = directStreaming;
      try {
        final cubit = _settingsCubit;
        if (cubit != null && cubit.bitPerfectViaDirectStream == true) {
          directOwned = true;
        }
      } catch (e) {
        directOwned = directStreaming;
      }
      // Negotiate the format against the advertised device caps so a device
      // that cannot honour the track's exact rate still receives the highest
      // supported tier instead of a flat exclusive-mixer rejection. Unknown
      // caps request the track rate unchanged (never invent a downgrade).
      final advertised = directOwned
          ? usb.lastStatus.supportedRates.where((r) => r > 0).toList()
          : (device?.supportedSampleRates ?? const <int>[])
              .where((r) => r > 0)
              .toList();
      final decision = negotiateOutputFormat(
        request: OutputFormatRequest(
          trackSampleRate: rate,
          trackBitDepth: depth,
          requestedSampleRate: rate,
          requestedBitDepth: depth,
        ),
        deviceSampleRates: advertised.isEmpty ? <int>[rate] : advertised,
        deviceMaxBitDepth: depth,
        route: OutputRoute.fromOutputInfo(device),
        // This decides the request FOR the exclusive path; enforcement stays on
        // the native side, so the deferral branch is not applicable here.
        bitPerfectActive: false,
      );
      if (!decision.applied) return;
      // Strict bit-perfect promises the track's own format. A negotiated
      // downgrade would be a silent resample behind a bit-perfect badge, so
      // refuse it through the mode owner rather than applying it anyway.
      if (settings.strictBitPerfect &&
          (decision.sampleRate != rate || decision.bitDepth < depth)) {
        _lastFollowedSampleRate = null;
        ErrorLogger.log(
            'Strict bit-perfect refused: output cannot carry $rate Hz/$depth-bit '
            '(negotiated ${decision.sampleRate} Hz/${decision.bitDepth}-bit)',
            category: 'PlayerDspController');
        await _settingsCubit!.setBitPerfectOutput(false);
        return;
      }
      try {
        if (directOwned && decision.sampleRate != rate) {
          // The UAC2 tee forwards decoded PCM at the track rate with no
          // resampler. Opening the endpoint at a negotiated rate would play the
          // whole track fast/slow (44.1k frames into a 48k stream), and leaving
          // the sink running while the mixer resamples would strand ownership.
          // Suspend instead of disabling: the endpoint is released (audio falls
          // back to the normal output path, never silence), the saved
          // preference stays, and the next supported track resumes the sink.
          _lastFollowedSampleRate = null;
          ErrorLogger.log(
              'USB DAC lacks track rate $rate Hz (negotiated '
              '${decision.sampleRate} Hz); suspending direct USB streaming',
              category: 'PlayerDspController');
          await _settingsCubit!.suspendDirectBitPerfectForTrack(
              'This track\'s $rate Hz is not supported by the USB DAC.');
          return;
        }
        // One owner applies the format and tears the mode down coherently if
        // the transport rejects it, instead of leaving a live endpoint behind.
        final producerChannels = await usb.getProducerChannels();
        final trackChannels = producerChannels > 0 ? producerChannels : 2;
        final applied = (trackChannels > 0 && trackChannels != 2)
            ? await _settingsCubit!.setBitPerfectTrackFormat(
                sampleRate: decision.sampleRate,
                bitDepth: decision.bitDepth,
                channels: trackChannels,
              )
            : await _settingsCubit!.setBitPerfectTrackFormat(
                sampleRate: decision.sampleRate,
                bitDepth: decision.bitDepth,
              );
        if (!applied) {
          _lastFollowedSampleRate = null;
          await _settingsCubit!.refreshOutputDevice();
          return;
        }
        if (_isClosed()) return;
        _lastFollowedSampleRate = decision.sampleRate;
        _lastFollowedBitDepth = depth;
        _lastFollowedRoute = route;
        await _settingsCubit!.refreshOutputDevice();
      } catch (e, st) {
        _lastFollowedSampleRate = null;
        ErrorLogger.log(
            'Follow-track sample rate failed (${decision.sampleRate})',
            error: e,
            stackTrace: st,
            category: 'PlayerDspController');
      }
    });
  }

  /// Bluetooth Hi-Res item 3: ask the A2DP codec to run at the track's native
  /// rate when it advertises that rate, so the platform does not resample.
  /// Best-effort — a refused request is logged, never surfaced as an error.
  Future<void> _maybeAlignBluetoothCodecRate(SongsTableData song) async {
    final service = _hiResAudioService;
    final settingsCubit = _settingsCubit;
    if (service == null || settingsCubit == null) return;
    final device = settingsCubit.state.currentOutputDevice;
    final trackRate = song.sampleRate ?? 0;
    if (trackRate <= 0) return;
    final plan = resolveBluetoothQualityPlan(
      bluetoothHiResEnabled: true,
      ditherEnabled: false,
      codecName: device?.btCodecName,
      codecSampleRateHz: device?.btSampleRateHz,
      codecBitDepth: device?.btBitDepth,
      isLeAudio: device?.isLeAudio ?? false,
      trackSampleRate: trackRate,
      trackBitDepth: song.bitDepth ?? 0,
      codecSelectableSampleRates: device?.btSelectableSampleRates ?? const [],
      codecSelectableBitDepths: device?.btSelectableBitDepths ?? const [],
    );
    final target = plan.alignCodecSampleRateTo;
    if (target == null || target == _lastFollowedBtCodecRate) return;
    try {
      final ok = await service.setBluetoothSampleRate(target);
      if (ok) {
        _lastFollowedBtCodecRate = target;
        await settingsCubit.refreshOutputDevice();
      } else {
        _lastFollowedBtCodecRate = null;
      }
    } catch (e, st) {
      _lastFollowedBtCodecRate = null;
      ErrorLogger.log('Bluetooth codec rate alignment failed ($target)',
          error: e, stackTrace: st, category: 'PlayerDspController');
    }
  }
}
