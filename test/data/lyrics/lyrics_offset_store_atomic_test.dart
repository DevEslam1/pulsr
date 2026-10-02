import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/lyrics/lyrics_offset_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('concurrent writes do not drop index entries', () async {
    final store = LyricsOffsetStore();
    final paths = List.generate(100, (i) => '/music/track_$i.flac');

    await Future.wait([
      for (var i = 0; i < paths.length; i++)
        store.setOffsetMs(paths[i], i - 50),
    ]);

    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList('lyrics_offset_index_v1') ?? const [];
    expect(index.length, paths.length,
        reason: 'every key must survive the concurrent read-modify-write');

    for (var i = 0; i < paths.length; i++) {
      expect(await store.getOffsetMs(paths[i]), i - 50);
    }
  });
}
