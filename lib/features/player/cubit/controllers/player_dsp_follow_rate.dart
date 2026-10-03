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
      try {
        final applied = await service.setTargetOutputFormat(
            sampleRate: rate, bitDepth: depth);
        if (!applied) {
          _lastFollowedSampleRate = null;
          await _settingsCubit!.refreshOutputDevice();
          return;
        }
        if (_isClosed()) return;
        _lastFollowedSampleRate = rate;
        _lastFollowedBitDepth = depth;
        _lastFollowedRoute = route;
        await _settingsCubit!.refreshOutputDevice();
      } catch (e, st) {
        _lastFollowedSampleRate = null;
        ErrorLogger.log('Follow-track sample rate failed ($rate)',
            error: e, stackTrace: st, category: 'PlayerDspController');
      }
    });
  }
}
