import 'package:just_audio/just_audio.dart';

/// Pushes the opt-in AAudio "Direct" output preference to every playback
/// player.
///
/// Default OFF: callers pass `false`, which keeps today's DefaultAudioSink
/// path (with the native DSP chain) untouched. When on, newly built sinks use
/// the native AAudio stream (bit-perfect; the DSP processor chain is
/// bypassed). Each [AudioPlayer.dspSetAaudioOutput] call is best-effort - a
/// player or platform that cannot honour the mode keeps the historical sink,
/// and this function never throws so a fan-out failure can never interrupt
/// playback.
Future<void> pushAaudioOutputToPlayers(
  bool enabled, {
  bool preferExclusive = true,
  int targetBufferMs = 150,
  Iterable<AudioPlayer> players = const [],
}) async {
  for (final player in players) {
    try {
      await player.dspSetAaudioOutput(
        enabled,
        preferExclusive: preferExclusive,
        targetBufferMs: targetBufferMs,
      );
    } catch (_) {
      // Keep the historical sink path on unsupported platforms.
    }
  }
}
