part of 'player_dsp_controller.dart';

extension PlayerDspFollowRate on PlayerDspController {
  /// [H-18] Serializes concurrent follow-rate requests (e.g. rapid track
  /// changes) through a mutex so overlapping native output-format switches
  /// apply in strict order instead of racing one another.
  Future<void> maybeFollowTrackSampleRate(SongsTableData song) async {
    final service = _hiResAudioService;
    if (service == null || _settingsCubit == null) return;
    await _followSampleRateMutex.protect(() async {
      final settings = _settingsCubit!.state;
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
      // Negotiate the format against the advertised device caps so a device
      // that cannot honour the track's exact rate still receives the highest
      // supported tier instead of a flat exclusive-mixer rejection. Unknown
      // caps request the track rate unchanged (never invent a downgrade).
      final advertised = (device?.supportedSampleRates ?? const <int>[])
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
        final applied = await service.setTargetOutputFormat(
            sampleRate: decision.sampleRate, bitDepth: decision.bitDepth);
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
}
