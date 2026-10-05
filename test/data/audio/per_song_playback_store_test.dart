import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/data/audio/per_song_playback_store.dart';

/// A-01: per-song playback memory (speed/pitch) persistence.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PerSongPlaybackStore', () {
    test('round-trips speed and pitch through prefs', () async {
      final store = PerSongPlaybackStore();
      await store.ready;
      await store.setSpeed('1', 1.5);
      await store.setPitch('1', 0.8);
      expect(store.getSpeed('1'), closeTo(1.5, 1e-9));
      expect(store.getPitch('1'), closeTo(0.8, 1e-9));

      final reloaded = PerSongPlaybackStore();
      await reloaded.ready;
      expect(reloaded.getSpeed('1'), closeTo(1.5, 1e-9));
      expect(reloaded.getPitch('1'), closeTo(0.8, 1e-9));
    });

    test('defaults return null and are not persisted', () async {
      final store = PerSongPlaybackStore();
      await store.ready;
      await store.setSpeed('2', 1.0);
      await store.setPitch('2', 1.0);
      expect(store.getSpeed('2'), isNull);
      expect(store.getPitch('2'), isNull);
      expect(store.snapshot().containsKey('2'), isFalse);
    });

    test('setting speed back to default clears the remembered entry', () async {
      final store = PerSongPlaybackStore();
      await store.ready;
      await store.setSpeed('3', 2.0);
      expect(store.getSpeed('3'), 2.0);
      await store.setSpeed('3', 1.0);
      expect(store.getSpeed('3'), isNull);
      expect(store.snapshot().containsKey('3'), isFalse);
    });

    test('clamps out-of-range values', () async {
      final store = PerSongPlaybackStore();
      await store.ready;
      await store.setSpeed('4', 99.0);
      await store.setPitch('4', 0.01);
      expect(store.getSpeed('4'), PerSongPlaybackStore.maxSpeed);
      expect(store.getPitch('4'), PerSongPlaybackStore.minPitch);
    });

    test('clearForTrack removes only the target entry', () async {
      final store = PerSongPlaybackStore();
      await store.ready;
      await store.setSpeed('5', 1.25);
      await store.setSpeed('6', 1.75);
      store.clearForTrack('5');
      await store.ready;
      expect(store.getSpeed('5'), isNull);
      expect(store.getSpeed('6'), closeTo(1.75, 1e-9));
    });

    test('corrupt prefs payload is ignored', () async {
      SharedPreferences.setMockInitialValues({
        PerSongPlaybackStore.prefsKey: 'not-json',
      });
      final store = PerSongPlaybackStore();
      await store.ready;
      expect(store.snapshot(), isEmpty);
    });
  });
}
