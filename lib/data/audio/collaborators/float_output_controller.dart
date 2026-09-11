import 'package:just_audio/just_audio.dart';

/// Pushes the opt-in 24/32-bit float DSP-path preference to every playback
/// player.
///
/// Default OFF: callers pass `false`, which keeps today's 16-bit sink path
/// untouched. Each [AudioPlayer.dspSetFloatOutput] call is best-effort — a
/// player or platform that cannot honour float output keeps the 16-bit path,
/// and this function never throws so a fan-out failure can never interrupt
/// playback.
Future<void> pushFloatOutputToPlayers(
  bool enabled,
  Iterable<AudioPlayer> players,
) async {
  for (final player in players) {
    try {
      await player.dspSetFloatOutput(enabled);
    } catch (_) {
      // Keep today's 16-bit path on unsupported platforms.
    }
  }
}
