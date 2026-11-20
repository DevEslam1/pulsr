// lib/data/audio/decoder_runtime_probe.dart
//
// Runtime decoder availability, distinct from the static capability table.
// A format can be recognized and still have no decoder on this device (notably
// ALAC over MediaCodec). Results are cached per MIME/sample-rate.

import 'audio_effects_channel.dart';

class DecoderRuntimeProbe {
  DecoderRuntimeProbe({
    Future<bool> Function(String mime, int sampleRate)? probe,
  }) : _probe = probe ?? _defaultProbe;

  final Future<bool> Function(String mime, int sampleRate) _probe;
  final Map<String, bool> _cache = <String, bool>{};

  Future<bool> supports(String mime, {int sampleRate = 0}) async {
    final key = '${mime.toLowerCase()}|$sampleRate';
    final cached = _cache[key];
    if (cached != null) return cached;
    bool result;
    try {
      result = await _probe(mime.toLowerCase(), sampleRate);
    } catch (_) {
      // An unreadable probe is "not available", never an optimistic yes.
      result = false;
    }
    _cache[key] = result;
    return result;
  }

  static Future<bool> _defaultProbe(String mime, int sampleRate) =>
      AudioEffectsChannel().probeAudioDecoder(mime, sampleRate: sampleRate);
}
