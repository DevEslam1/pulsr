import 'package:just_audio/just_audio.dart';

/// Pushes the tap-side SRC target rate to every playback player.
///
/// [rate] is the sample rate the output mixer runs at; 0 disables conversion
/// and leaves the platform mixer to resample the finished DSP, which is
/// today's behaviour. Each [AudioPlayer.dspSetTapSrcRate] call is best-effort —
/// a player or platform that cannot honour it keeps the historical path, and
/// this never throws so a fan-out failure cannot interrupt playback.
Future<void> pushTapSrcRateToPlayers(
  int rate,
  Iterable<AudioPlayer> players,
) async {
  for (final player in players) {
    try {
      await player.dspSetTapSrcRate(rate);
    } catch (_) {
      // Keep the platform-resample path where the fork is unavailable.
    }
  }
}
