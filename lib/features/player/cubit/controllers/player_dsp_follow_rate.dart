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
      final route =
          '${device?.deviceName}|${device?.activeDeviceType}|${device?.isUsbDac}';
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
      // Negotiate the format against the advertised device caps so a device
      // that cannot honour the track's exact rate still receives the highest
      // supported tier instead of a flat exclusive-mixer rejection. Unknown
      // caps request the track rate unchanged (never invent a downgrade).
      final advertised = directStreaming
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
      try {
        if (directStreaming) {
          final res = await usb.startStreaming(
            sampleRate: decision.sampleRate,
            bitDepth: decision.bitDepth,
          );
          if (!res.isOk) {
            _lastFollowedSampleRate = null;
            ErrorLogger.log(
                'Follow-track direct USB rate switch failed (${decision.sampleRate}, ${res.name})',
                category: 'PlayerDspController');
            await _settingsCubit!.refreshOutputDevice();
            return;
          }
        } else {
          final applied = await service.setTargetOutputFormat(
              sampleRate: decision.sampleRate, bitDepth: decision.bitDepth);
          if (!applied) {
            _lastFollowedSampleRate = null;
            await _settingsCubit!.refreshOutputDevice();
            return;
          }
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
      ErrorLogger.log(
          'Bluetooth codec rate alignment failed ($target)',
          error: e,
          stackTrace: st,
          category: 'PlayerDspController');
    }
  }
}
