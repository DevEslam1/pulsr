// test/gapless_trim_codecs_test.dart
//
// Roadmap item B3: gapless trim for MP3/AAC encoder delay on top of the
// existing Opus/Vorbis handling. Verifies codec detection, trim values and
// the clamp safety net.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/gapless_trim_handler.dart';

void main() {
  group('GaplessTrimHandler codec trims', () {
    test('MP3 files get LAME encoder delay + padding', () {
      final trim = GaplessTrimHandler.trimFor(path: '/music/song.mp3');
      expect(trim.preSkip, GaplessTrimHandler.mp3EncoderDelay);
      expect(trim.postTrim, GaplessTrimHandler.mp3EncoderPadding);
      expect(trim.isEmpty, isFalse);
    });

    test('MP3 codec hint (no extension) is detected via codec string', () {
      final trim = GaplessTrimHandler.trimFor(
          path: '/music/stream_001', codec: 'mp3');
      expect(trim.preSkip, GaplessTrimHandler.mp3EncoderDelay);
    });

    test('AAC containers get iTunes-style priming pre-skip', () {
      for (final path in [
        '/music/song.aac',
        '/music/song.m4a',
        '/music/song.mp4',
      ]) {
        final trim = GaplessTrimHandler.trimFor(path: path);
        expect(trim.preSkip, GaplessTrimHandler.aacEncoderDelay,
            reason: 'path: $path');
        expect(trim.postTrim, Duration.zero);
      }
    });

    test('AAC codec hint is honoured', () {
      final trim = GaplessTrimHandler.trimFor(
          path: '/music/hls_segment', codec: 'mp4a.40.2');
      expect(trim.preSkip, GaplessTrimHandler.aacEncoderDelay);
    });

    test('Opus keeps its pre-skip', () {
      final trim = GaplessTrimHandler.trimFor(path: '/music/song.opus');
      expect(trim.preSkip, GaplessTrimHandler.opusPreSkip);
    });

    test('FLAC and unknown formats stay untrimmed', () {
      expect(
          GaplessTrimHandler.trimFor(path: '/music/song.flac').isEmpty, isTrue);
      expect(
          GaplessTrimHandler.trimFor(path: '/music/song.wav').isEmpty, isTrue);
    });

    test('explicit header overrides beat codec defaults', () {
      final trim = GaplessTrimHandler.trimFor(
        path: '/music/song.mp3',
        preSkipOverrideMs: 100,
        postTrimOverrideMs: 50,
      );
      expect(trim.preSkip, const Duration(milliseconds: 100));
      expect(trim.postTrim, const Duration(milliseconds: 50));
    });

    test('clampedTo never eats more than 20% of a short track', () {
      const trim = GaplessTrim(
        preSkip: Duration(milliseconds: 48),
        postTrim: Duration(milliseconds: 12),
      );
      final clamped = trim.clampedTo(const Duration(milliseconds: 200));
      // 60ms total > 20% of 200ms (40ms) -> scaled down.
      expect(clamped.total.inMilliseconds, lessThanOrEqualTo(40));
    });
  });
}
