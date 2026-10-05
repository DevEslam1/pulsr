import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/data/audio/bpm_override_store.dart';

/// Unit tests for the manual per-track BPM source that feeds BPM-synced
/// crossfade (`CrossfadeManager.bpmOverrides` via the audio handler).
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('BpmOverrideStore', () {
    test('round-trips a BPM override through prefs', () async {
      final store = BpmOverrideStore();
      await store.ready;
      expect(await store.setBpmForTrack('1', 128.0), isTrue);
      expect(store.getBpmForTrack('1'), 128.0);

      final reloaded = BpmOverrideStore();
      await reloaded.ready;
      expect(reloaded.getBpmForTrack('1'), 128.0);
    });

    test('rejects out-of-range and non-finite BPM', () async {
      final store = BpmOverrideStore();
      await store.ready;
      for (final bad in [39.9, 240.1, 0.0, -120.0, double.nan]) {
        expect(await store.setBpmForTrack('1', bad), isFalse,
            reason: 'bpm=$bad');
      }
      expect(store.getBpmForTrack('1'), isNull);
      expect(await store.setBpmForTrack('1', 40.0), isTrue);
      expect(await store.setBpmForTrack('1', 240.0), isTrue);
    });

    test('null clears the override', () async {
      final store = BpmOverrideStore();
      await store.ready;
      await store.setBpmForTrack('7', 100.0);
      expect(store.getBpmForTrack('7'), 100.0);
      expect(await store.setBpmForTrack('7', null), isTrue);
      expect(store.getBpmForTrack('7'), isNull);
    });
  });
}
