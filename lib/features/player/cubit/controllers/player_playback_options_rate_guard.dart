// lib/features/player/cubit/controllers/player_playback_options_rate_guard.dart
part of 'player_playback_options_controller.dart';

extension PlaybackRateBitPerfectGuard on PlayerPlaybackOptionsController {
  /// Refuses speed/pitch changes while the bit-perfect bypass is active; the
  /// engine would resample the exact bitstream. Resetting to 1.0× stays
  /// allowed so the user can always restore bit-perfect playback.
  bool checkPlaybackRateGuard(String feature, {bool showError = true}) {
    final reason = _playbackRateBlockedReason?.call();
    if (reason == null) return true;
    if (showError) {
      final s = _getState();
      _emit(s.copyWith(
        playback:
            s.playback.copyWith(errorMessage: '$feature blocked: $reason'),
      ));
    }
    return false;
  }
}
