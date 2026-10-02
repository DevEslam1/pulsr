import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/repositories/prefs_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('unsupported value type throws ArgumentError instead of silent drop',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = PrefsRepository(prefs);

    await expectLater(
      repo.set<Object>('bad', DateTime.now(), immediate: true),
      throwsArgumentError,
    );
  });

  test('batched writes are flushed by dispose (not lost)', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = PrefsRepository(prefs);

    await repo.set('batched_key', 'batched_value');
    await repo.dispose();

    expect(prefs.getString('batched_key'), 'batched_value');
  });

  test('a bad batched value is surfaced by flush without dropping valid writes',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = PrefsRepository(prefs);

    await repo.set('valid_key', 'ok');
    await repo.set<Object>('invalid_key', DateTime.now());

    await expectLater(repo.flush(), throwsArgumentError);
    expect(prefs.getString('valid_key'), 'ok');
  });
}
