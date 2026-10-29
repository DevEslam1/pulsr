// test/data/audio/dsp_snapshot_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dsp_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a toggle issued before the async load wins over the stored value',
      () async {
    SharedPreferences.setMockInitialValues(
        {'${DspSnapshotStore.prefsKey}_enabled': true});
    final store = DspSnapshotStore();

    // Runs synchronously, before load() resumes after its first await.
    store.enabled = false;
    await store.ready;

    expect(store.enabled, isFalse);
  });

  test('persist writes the toggled value and reload keeps it', () async {
    final store = DspSnapshotStore();
    await store.ready;
    store.enabled = false;
    await store.persist();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('${DspSnapshotStore.prefsKey}_enabled'), isFalse);

    await store.reload();
    expect(store.enabled, isFalse);
  });

  test('non-finite snapshot fields are sanitized on save and restore', () {
    final snapshot = DspSnapshot(
      presetName: 'Custom',
      gains: const [double.nan, 1.0],
      volumeBoost: double.infinity,
      bassBoost: double.nan,
      savedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final map = snapshot.toMap();
    expect(map['gains'], [0.0, 1.0]);
    expect(map['volumeBoost'], 0.0);
    expect(map['bassBoost'], 0.0);

    final restored = DspSnapshot.fromMap({
      ...map,
      'volumeBoost': double.infinity,
      'bassBoost': double.nan,
    });
    expect(restored, isNotNull);
    expect(restored!.volumeBoost, 0.0);
    expect(restored.bassBoost, 0.0);
  });

  test('scope keys are normalized and placeholder tags are rejected', () {
    expect(DspSnapshotStore.isUsableScope('Unknown Album'), isFalse);
    expect(DspSnapshotStore.isUsableScope('<unknown>'), isFalse);
    expect(DspSnapshotStore.isUsableScope('  '), isFalse);
    expect(DspSnapshotStore.isUsableScope('Abbey Road'), isTrue);
    expect(DspSnapshotStore.albumKey(' Abbey Road ', ' The Beatles '),
        'album:the beatles::abbey road');
  });
}
