// test/data/audio/store_reload_gates_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/bpm_override_store.dart';
import 'package:pulsr/data/audio/dsp_snapshot_store.dart';
import 'package:pulsr/data/audio/per_song_eq_store.dart';
import 'package:pulsr/data/audio/per_song_volume_store.dart';
import 'package:pulsr/data/audio/playback_bookmark_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PlaybackBookmarkStore ready gate', () {
    test('a save before load completes is not discarded', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        PlaybackBookmarkStore.prefsKey: jsonEncode({
          'id:1': {'pos': 10000, 'dur': 600000, 'at': now},
          'id:2': {'pos': 20000, 'dur': 600000, 'at': now},
        }),
      });

      final store = PlaybackBookmarkStore();
      store.save('id:3', 30000, durationMs: 600000);
      await store.ready;

      expect(store.recall('id:1'), isNotNull);
      expect(store.recall('id:2'), isNotNull);
      expect(store.recall('id:3'), isNotNull,
          reason: 'the pre-load save must survive the initial load');
    });

    test('reload picks up external writes and is idempotent', () async {
      final store = PlaybackBookmarkStore();
      await store.ready;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        PlaybackBookmarkStore.prefsKey,
        jsonEncode({
          'id:9': {
            'pos': 30000,
            'dur': 600000,
            'at': DateTime.now().millisecondsSinceEpoch,
          },
        }),
      );

      await store.reload();
      await store.reload();
      expect(store.recall('id:9'), isNotNull);
    });
  });

  group('DspSnapshotStore ready gate', () {
    test('a snapshot saved before load completes is not discarded', () async {
      final stored = DspSnapshot(
        presetName: 'Stored',
        gains: const [1.0, 2.0],
        savedAt: DateTime.now(),
      );
      SharedPreferences.setMockInitialValues({
        DspSnapshotStore.prefsKey: jsonEncode({'album:a::b': stored.toMap()}),
      });

      final store = DspSnapshotStore();
      store.save(
        'artist:x',
        DspSnapshot(
          presetName: 'Fresh',
          gains: const [3.0],
          savedAt: DateTime.now(),
        ),
      );
      await store.ready;

      expect(store.recall('album:a::b')?.presetName, 'Stored');
      expect(store.recall('artist:x')?.presetName, 'Fresh',
          reason: 'the pre-load save must survive the initial load');
    });

    test('reload picks up external writes and is idempotent', () async {
      final store = DspSnapshotStore();
      await store.ready;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        DspSnapshotStore.prefsKey,
        jsonEncode({
          'genre:rock': DspSnapshot(
            presetName: 'External',
            gains: const [2.0],
            savedAt: DateTime.now(),
          ).toMap(),
        }),
      );

      await store.reload();
      await store.reload();
      expect(store.recall('genre:rock')?.presetName, 'External');
    });
  });

  group('BpmOverrideStore reload', () {
    test('reload replaces the map with stored values and is idempotent',
        () async {
      SharedPreferences.setMockInitialValues({
        BpmOverrideStore.prefsKey: jsonEncode({'a': 120.0}),
      });
      final store = BpmOverrideStore();
      await store.ready;
      await store.setBpmForTrack('b', 140.0);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BpmOverrideStore.prefsKey, jsonEncode({'c': 90.0}));

      await store.reload();
      expect(store.getBpmForTrack('c'), 90.0);
      expect(store.getBpmForTrack('b'), isNull,
          reason: 'reload replaces, it does not merge');

      await store.reload();
      expect(store.getBpmForTrack('c'), 90.0);
    });
  });

  group('PerSongEqStore / PerSongVolumeStore reload', () {
    test('reload picks up external writes twice safely', () async {
      final eqStore = PerSongEqStore();
      final volumeStore = PerSongVolumeStore();
      await Future.wait<void>([eqStore.ready, volumeStore.ready]);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PerSongEqStore.prefsKey, jsonEncode({'7': 'Bass'}));
      await prefs.setString(
          PerSongVolumeStore.prefsKey, jsonEncode({'7': -4.0}));

      await eqStore.reload();
      await volumeStore.reload();
      await eqStore.reload();
      await volumeStore.reload();

      expect(eqStore.getPresetForTrack('7'), 'Bass');
      expect(volumeStore.getGainDbForTrack('7'), -4.0);
    });
  });
}
