// test/data/repositories/prefs_repository_flush_race_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/repositories/prefs_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('remove during an in-flight flush is not overwritten by the snapshot',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = PrefsRepository(prefs);

    await repo.set('a', 'va');
    await repo.set('b', 'vb');

    // flush() snapshots and starts writing 'a' synchronously; removing 'b'
    // now lands after the snapshot but before the flush reaches 'b'.
    final flushFuture = repo.flush();
    final removeFuture = repo.remove('b');

    await flushFuture;
    await removeFuture;

    expect(prefs.getString('b'), isNull,
        reason: 'the stale snapshot write must not resurrect removed keys');
    expect(prefs.getString('a'), 'va');
  });

  test('remove after flush still reaches disk', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = PrefsRepository(prefs);

    await repo.set('c', 'vc', immediate: true);
    expect(prefs.getString('c'), 'vc');

    await repo.remove('c');
    expect(prefs.getString('c'), isNull);
    expect(repo.getString('c'), isNull);
  });
}
