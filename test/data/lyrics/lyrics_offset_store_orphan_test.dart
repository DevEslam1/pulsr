// test/data/lyrics/lyrics_offset_store_orphan_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/lyrics/lyrics_offset_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a value with a missing owner marker reads zero and is cleaned up',
      () async {
    final store = LyricsOffsetStore();
    await store.setOffsetMs('/music/orphan.flac', 77);

    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getStringList('lyrics_offset_index_v1')!.single;
    await prefs.remove('${key}_path');
    expect(prefs.getInt(key), isNotNull,
        reason: 'precondition: the orphaned value is still stored');

    expect(await store.getOffsetMs('/music/orphan.flac'), 0);
    expect(prefs.getInt(key), isNull,
        reason:
            'the orphaned value must be removed, not served to a collision');
  });

  test('colliding owner still reads zero without deleting the other value',
      () async {
    final store = LyricsOffsetStore();
    await store.setOffsetMs('/music/owner.flac', 42);

    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getStringList('lyrics_offset_index_v1')!.single;
    await prefs.setString('${key}_path', '/music/intruder.flac');
    await prefs.setInt(key, 999);

    expect(await store.getOffsetMs('/music/owner.flac'), 0);
    expect(prefs.getInt(key), 999,
        reason: 'a conflicting owner must not destroy the other entry');
  });
}
