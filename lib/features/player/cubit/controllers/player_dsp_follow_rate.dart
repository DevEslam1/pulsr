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
    // AUDIT-FIX (P0-6): attach catchError and wrap the entire mutex body so
    // early awaits cannot leak unhandled async zone errors.
    unawaited(applyCodecAwareMusicCompensation()
        .catchError((Object e, StackTrace st) {
      ErrorLogger.log('Codec-aware music compensation failed',
          error: e, stackTrace: st, category: 'PlayerDspController');
    }));
    final service = _hiResAudioService;
    if (service == null || _settingsCubit == null) return;
    await _followSampleRateMutex.protect(() async {
      try {
        if (_isClosed()) return;
        final settings = _settingsCubit!.state;
        // Log real-time 4-stage signal path telemetry per track start (no-op if disabled).
        final outputDevice = settings.currentOutputDevice;
        final usbSnapshot = _usbExclusiveService.lastStatus;
        final sourceRate = effectiveSourceSampleRate(
          tagged: song.sampleRate ?? 0,
          decoded: outputDevice?.decodedSampleRate ?? 0,
        );
        final sourceDepth = effectiveSourceBitDepth(
          tagged: song.bitDepth ?? 0,
          decoded: outputDevice?.decodedBitDepth ?? 0,
        );
        // Same observed facts as the audio-quality sheet, and the same single
        // assembler: the session log records the verified tier, never the
        // preference flag, so it can never disagree with the live sheet about
        // the stream both are describing.
        final directUsb = usbSnapshot.streamingActive &&
            outputDevice?.isUsbDac == true &&
            outputDevice?.isBluetooth != true;
        final sourceCodecState = AudioConflicts.classifySourceCodec(
            path: song.path, codec: song.codec);
        final gain = _audioHandler.effectiveSoftwareGain;
        final dspBypassed = settings.strictBitPerfect ||
            AudioConflicts.dspBypassActive(
              bitPerfectOutput: settings.bitPerfectOutput,
              bypassDspOnBitPerfect: settings.bypassDspOnBitPerfect,
              device: outputDevice,
            );
        final facts = BitPerfectOutputFacts(
          requested: settings.bitPerfectOutput ||
              (outputDevice?.bitPerfectRequested ?? false),
          sinkActive: directUsb || outputDevice?.isBitPerfectActive == true,
          directUsbActive: directUsb,
          bluetooth: outputDevice?.isBluetooth == true,
          sourceSampleRate: sourceRate,
          sourceBitDepth: sourceDepth,
          sourceFloat:
              AudioConflicts.classifySourceSampleFormat(codec: song.codec) ==
                  AudioSourceSampleFormat.float,
          sinkSampleRate: outputDevice?.sinkSampleRate ?? 0,
          sinkBitDepth: outputDevice?.sinkBitDepth ?? 0,
          directStreamSampleRate: usbSnapshot.streamingSampleRate,
          directStreamBitDepth: usbSnapshot.streamingBitDepth,
          directRawPcmBitDepth: usbSnapshot.rawPcmBitDepth,
          floatCarrierDecodesSource:
              outputDevice?.floatCarrierDecodesSource == true,
          sinkIntegerBypass: outputDevice?.integerBypassActive == true,
          halStagesActive: outputDevice?.halStagesActive ?? 0,
          systemEffectsCompromised:
              outputDevice?.systemEffectsCompromised == true,
          softwareGain: gain,
          dspProcessing: !dspBypassed && _getState().dsp.isDspActive,
          transportSamplesModified: _audioHandler.transportSamplesModified,
          channelsAltered: directUsb && usbSnapshot.channelMismatchFrames > 0,
          rateVerified: !directUsb || usbSnapshot.rateVerified,
          isDsdDop: AudioQualityInfo.dsdDopActive,
          sourceLossy: song.source == SongSource.radio ||
              sourceCodecState == AudioSourceCodecState.lossy,
          sourceCodecUnconfirmed:
              sourceCodecState == AudioSourceCodecState.unknown,
          failureReason: outputDevice?.bitPerfectFailureReason,
        );
        final bitPerfectState = resolveBitPerfectOutput(facts);
        final signalPath = AudioSignalPath.fromOutputInfo(
          sourceCodec: song.codec ?? '',
          sourceSampleRate: sourceRate,
          sourceBitDepth: sourceDepth,
          isDsdSource: (song.codec ?? '').toUpperCase().contains('DSD') ||
              song.path.toLowerCase().endsWith('.dsf') ||
              song.path.toLowerCase().endsWith('.dff'),
          output: outputDevice,
          uac2DirectActive: usbSnapshot.streamingActive,
          aaudioEnabled: settings.aaudioOutputEnabled,
          floatOutputEnabled: settings.floatOutputEnabled,
          bitPerfectState: bitPerfectState,
        );
        unawaited(AudioSessionLog.instance.updateOutputInfo(
          routeType:
              AudioSessionLog.routeTypeForInfo(settings.currentOutputDevice),
          bluetoothCodec: settings.currentOutputDevice?.btCodecName,
          sampleRate: signalPath.hardwareSampleRate > 0
              ? signalPath.hardwareSampleRate
              : null,
          bitDepth: signalPath.hardwareBitDepth > 0
              ? signalPath.hardwareBitDepth
              : null,
          sourceCodec: signalPath.sourceCodec,
          sourceSampleRate: signalPath.sourceSampleRate > 0
              ? signalPath.sourceSampleRate
              : null,
          sourceBitDepth:
              signalPath.sourceBitDepth > 0 ? signalPath.sourceBitDepth : null,
          decoderSampleRate: signalPath.decoderSampleRate > 0
              ? signalPath.decoderSampleRate
              : null,
          decoderBitDepth: signalPath.decoderBitDepth > 0
              ? signalPath.decoderBitDepth
              : null,
          decoderEncoding: signalPath.decoderEncodingName,
          driverPath: signalPath.driverPath,
          isBitPerfect: signalPath.isBitPerfect,
          signalPathSummary: signalPath.toChainString(),
        ));
        if (settings.bitPerfectOutput &&
            !await _settingsCubit!.validateBitPerfectTrackSource(song)) {
          _lastFollowedSampleRate = null;
          return;
        }
        if (_isClosed()) return;
        final following = settings.strictBitPerfect ||
            (settings.outputFormatNegotiationEnabled &&
                settings.followTrackSampleRate);
        final effectiveTrackRate = effectiveSourceSampleRate(
          tagged: song.sampleRate ?? 0,
          decoded: settings.currentOutputDevice?.decodedSampleRate ?? 0,
        );
        final usb = _usbExclusiveService;
        final usbStatus = usb.lastStatus;
        final directStreaming = usbStatus.streamingActive;
        // Ownership survives a per-track suspend: the stream is stopped but the
        // preference and the sink claim stay armed for the next supported track.
        var directOwned = directStreaming;
        try {
          final cubit = _settingsCubit;
          if (cubit != null && cubit.bitPerfectViaDirectStream == true) {
            directOwned = true;
          }
        } catch (_) {
          directOwned = directStreaming;
        }
        if (!directOwned) {
          _lockedDirectUsbRate = null;
        } else if (directStreaming && usbStatus.streamingSampleRate > 0) {
          _lockedDirectUsbRate = usbStatus.streamingSampleRate;
        }
        if (!following &&
            directStreaming &&
            effectiveTrackRate > 0 &&
            usbStatus.streamingSampleRate != effectiveTrackRate) {
          if (usbStatus.streamingSampleRate > 0) {
            _lockedDirectUsbRate = usbStatus.streamingSampleRate;
          }
          final notice = L10nHolder
                  .current?.directUsbFollowFormatSuspendedNotice ??
              'Direct USB requires the source rate; follow-format is disabled.';
          await _settingsCubit!.suspendDirectBitPerfectForTrack(notice);
          if (_isClosed()) return;
          final s = _getState();
          _emit(s.copyWith(
            playback: s.playback.copyWith(error: uiError(notice)),
          ));
          _lastFollowedSampleRate = null;
          return;
        }
        final expectedLockedRate = _lockedDirectUsbRate ??
            (settings.currentOutputDevice?.targetSampleRate ?? 0);
        final canResumeSuspendedDirect = !following &&
            directOwned &&
            !directStreaming &&
            settings.bitPerfectOutput &&
            effectiveTrackRate > 0 &&
            (expectedLockedRate <= 0 ||
                expectedLockedRate == effectiveTrackRate) &&
            (usbStatus.supportedRates.isEmpty ||
                usbStatus.supportedRates.contains(effectiveTrackRate));
        // The user's "Per-Track Output Format Negotiation" switch is the master
        // gate: off means keep one manual/manufacturer output format for the
        // whole session instead of renegotiating per track. Strict bit-perfect
        // promises the track's own format, so it cannot be silently muted by
        // that switch. Direct USB may also resume when a following track matches
        // the locked sample rate after a transient per-track suspend.
        if (!following && !canResumeSuspendedDirect) {
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
        // Validate EVERY source, even identical rate/depth. A codec or channel
        // change is not a redundant format request, and missing metadata must not
        // leave an exclusive endpoint clocked at the previous track's rate.
        final device = settings.currentOutputDevice;
        // The direct UAC2 sink (Bit-Perfect fallback) switches rate by
        // re-starting the isochronous stream; the platform mixer attributes
        // are not involved on that path (resolved above alongside directOwned).
        final activeDevice =
            device?.availableDevices.where((d) => d.isCurrent).firstOrNull;
        final deviceDepth =
            activeDevice?.maxBitDepth ?? (device?.bitDepth ?? 0);
        // An unread track depth is not a 16-bit track. Resolve it against the
        // live direct stream and the route's advertised depth so a 24-bit file
        // with missing metadata is never silently narrowed on the exclusive
        // path.
        final depth = resolveFollowBitDepth(
          trackBitDepth: effectiveSourceBitDepth(
              tagged: song.bitDepth ?? 0,
              decoded: device?.decodedBitDepth ?? 0),
          streamingBitDepth:
              directStreaming ? usb.lastStatus.streamingBitDepth : 0,
          deviceBitDepth: deviceDepth,
        );
        // The mode belongs in the dedup key: switching Bit-Perfect off and on
        // reopens the output, so the previous confirmation is no longer valid.
        final producerChannels =
            directOwned ? await usb.getProducerChannels() : 2;
        if (_isClosed()) return;
        final trackChannels = producerChannels > 0 ? producerChannels : 2;
        final route =
            '${activeDevice?.id}|${usb.lastStatus.deviceId}|${device?.activeDeviceType}'
            '|${settings.bitPerfectOutput}|${settings.strictBitPerfect}'
            '|${song.codec}|${song.path.split('?').first.split('#').first.split('.').last}'
            '|${device?.decodedPcmEncoding}|$trackChannels';
        final rate = HiResAudioService.followTrackRateToApply(
          trackSampleRate:
              effectiveTrackRate > 0 ? effectiveTrackRate : song.sampleRate,
          lastRequestedSampleRate: canResumeSuspendedDirect
              ? null
              : (depth == _lastFollowedBitDepth && route == _lastFollowedRoute
                  ? _lastFollowedSampleRate
                  : null),
          isBluetooth: settings.currentOutputDevice?.isBluetooth == true,
          followTrackEnabled: following || canResumeSuspendedDirect,
        );
        if (rate == null) return;
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
          final notice = L10nHolder.current
                  ?.strictBitPerfectRefusedNotice(rate, depth) ??
              'Strict bit-perfect disabled: device cannot carry $rate Hz/$depth-bit without resampling.';
          await _settingsCubit!.setBitPerfectOutput(false);
          if (_isClosed()) return;
          final s = _getState();
          _emit(s.copyWith(
            playback: s.playback.copyWith(error: uiError(notice)),
          ));
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
            final notice =
                L10nHolder.current?.directUsbUnsupportedRateNotice(rate) ??
                    'This track\'s $rate Hz is not supported by the USB DAC.';
            await _settingsCubit!.suspendDirectBitPerfectForTrack(notice);
            if (_isClosed()) return;
            final s = _getState();
            _emit(s.copyWith(
              playback: s.playback.copyWith(error: uiError(notice)),
            ));
            return;
          }
          // One owner applies the format and tears the mode down coherently if
          // the transport rejects it, instead of leaving a live endpoint behind.
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
      } catch (e, st) {
        _lastFollowedSampleRate = null;
        ErrorLogger.log('Follow-track sample rate failed',
            error: e, stackTrace: st, category: 'PlayerDspController');
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
    final targetDepth = plan.alignCodecBitDepthTo;
    if (target == null && targetDepth == null) return;
    final rateAlreadyOk = target == null ||
        (target == _lastFollowedBtCodecRate &&
            device?.btSampleRateHz == target &&
            (device?.btBitDepth ?? 0) > 0);
    final depthAlreadyOk =
        targetDepth == null || device?.btBitDepth == targetDepth;
    if (rateAlreadyOk && depthAlreadyOk) {
      return;
    }
    try {
      var rateOk = true;
      var depthOk = true;
      if (!rateAlreadyOk) {
        rateOk = await service.setBluetoothSampleRate(target);
      }
      if (!depthAlreadyOk) {
        depthOk = await service.setBluetoothBitDepth(targetDepth);
      }
      if (rateOk || depthOk) {
        await settingsCubit.refreshOutputDevice();
        final actual = settingsCubit.state.currentOutputDevice;
        // Dispatch is not negotiation. Cache only a readback on the same route
        // and codec with a known negotiated depth.
        if (target != null) {
          _lastFollowedBtCodecRate = actual?.isBluetooth == true &&
                  actual?.deviceName == device?.deviceName &&
                  actual?.btCodecName == device?.btCodecName &&
                  actual?.btSampleRateHz == target &&
                  (actual?.btBitDepth ?? 0) > 0
              ? target
              : null;
        }
      } else {
        _lastFollowedBtCodecRate = null;
      }
    } catch (e, st) {
      _lastFollowedBtCodecRate = null;
      ErrorLogger.log('Bluetooth codec alignment failed ($target/$targetDepth)',
          error: e, stackTrace: st, category: 'PlayerDspController');
    }
  }
}
