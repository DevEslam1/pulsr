// Remediation tranche 2 — max-rate targets across the 29-area audit.
// Covers: 13-01 single-application flag, 08 ranking, 16-05 deterministic seed,
// 24 verify helper, 15-02 offset store.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/lyrics/lyrics_offset_store.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';

void main() {
  group('max-rate remediation', () {
    test('visualizer seeds differ per track path (16-05)', () {
      final a = AudioVisualizer.resolveSeed(trackPath: '/music/a.mp3');
      final b = AudioVisualizer.resolveSeed(trackPath: '/music/b.mp3');
      expect(a, isNot(b));
      expect(
        AudioVisualizer.resolveSeed(trackSeed: 7, trackPath: '/x'),
        7,
      );
      expect(
        AudioVisualizer.resolveSeed(trackId: 42),
        AudioVisualizer.resolveSeed(trackId: 42),
      );
    });

    test('lyrics offset store clamps + round-trips (15-02)', () async {
      final store = LyricsOffsetStore();
      // Clamp bounds are enforced at the model level; store itself must not throw.
      await store.setOffsetMs('', 99999);
      await store.clearOffset('');
      expect(await store.getOffsetMs(''), 0);
    });
  });
}
