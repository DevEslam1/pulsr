import 'package:just_audio/just_audio.dart';
import '../output_format_negotiation.dart';

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
///
/// Buffer sizing — two complementary knobs:
///  * [targetBufferMs]: explicit override (highest priority). Pass this when
///    the caller already knows the desired buffer size (e.g. from a persisted
///    user setting or a test stub). Preserved for full backward compatibility.
///  * [route]: used only when [targetBufferMs] is `null`. Selects a sensible
///    default per output route:
///      - [OutputRoute.wired] / [OutputRoute.speaker] → **8 ms** (USB-C DAC)
///      - [OutputRoute.bluetooth]                      → **150 ms** (A2DP jitter)
Future<bool> pushAaudioOutputToPlayers(
  bool enabled, {
  bool preferExclusive = true,

  /// Explicit buffer size in milliseconds. When non-null, this value is used
  /// directly and [route] is ignored. Preserves existing call sites that
  /// supply a numeric buffer.
  int? targetBufferMs,

  /// Route-aware default when [targetBufferMs] is null.
  /// Defaults to [OutputRoute.bluetooth] (150 ms) for backward compatibility.
  OutputRoute route = OutputRoute.bluetooth,
  Iterable<AudioPlayer> players = const [],
}) async {
  // Explicit override wins; fall back to route-derived default.
  final int bufferMs =
      targetBufferMs ?? (route == OutputRoute.bluetooth ? 150 : 8);

  var applied = true;
  for (final player in players) {
    try {
      final accepted = await player.dspSetAaudioOutput(
        enabled,
        preferExclusive: preferExclusive,
        targetBufferMs: bufferMs,
      );
      applied = accepted && applied;
    } catch (_) {
      applied = false;
    }
  }
  return applied;
}
