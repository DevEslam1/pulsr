// P0-1 remote sources: SharedPreferences round-trip for the source list.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/remote_source.dart';
import 'package:pulsr/features/remote_sources/remote_source_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

RemoteSource _source({
  String host = 'nas.local',
  String root = '/Music',
  RemoteSourceKind kind = RemoteSourceKind.webdav,
  String name = 'NAS',
}) {
  return RemoteSource.create(
    kind: kind,
    displayName: name,
    host: host,
    port: kind.defaultPort,
    rootPath: root,
    username: 'media',
  );
}

Future<String?> _rawPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(RemoteSourceStore.prefsKey);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('add persists one JSON array without secrets', () async {
    final store = RemoteSourceStore();
    await store.add(_source());

    expect(store.list, hasLength(1));
    final raw = await _rawPrefs();
    expect(raw, isNotNull);
    expect(raw, isNot(contains('password')));
    final decoded = jsonDecode(raw!) as List<dynamic>;
    expect(decoded, hasLength(1));
    expect((decoded.single as Map<String, dynamic>)['kind'], 'webdav');
  });

  test('adding the same endpoint replaces instead of duplicating', () async {
    final store = RemoteSourceStore();
    await store.add(_source(name: 'First'));
    await store.add(_source(name: 'Second'));

    expect(store.list, hasLength(1));
    expect(store.list.single.displayName, 'Second');
    expect(jsonDecode((await _rawPrefs())!) as List<dynamic>, hasLength(1));
  });

  test('getById and remove work on a loaded list', () async {
    final store = RemoteSourceStore();
    final source = await store.add(_source());

    expect(store.getById(source.id)?.displayName, 'NAS');

    await store.remove(source.id);
    expect(store.list, isEmpty);
    expect(store.getById(source.id), isNull);
    expect(jsonDecode((await _rawPrefs())!) as List<dynamic>, isEmpty);
  });

  test('a second store instance reads what the first one wrote', () async {
    final first = RemoteSourceStore();
    await first.add(_source(root: '/Music/A'));
    await first.add(_source(root: '/Music/B'));

    final second = RemoteSourceStore();
    await second.ready;
    expect(second.list, hasLength(2));
    expect(
      second.list.map((s) => s.rootPath),
      containsAll(<String>['/Music/A', '/Music/B']),
    );
  });

  test('an unreadable entry is skipped without dropping its neighbours',
      () async {
    final good = _source();
    SharedPreferences.setMockInitialValues({
      RemoteSourceStore.prefsKey: jsonEncode([
        good.toJson(),
        {'kind': 'gopher', 'host': 'x', 'port': 70},
        'not-a-map',
      ]),
    });

    final store = RemoteSourceStore();
    await store.ready;

    expect(store.list, hasLength(1));
    expect(store.list.single.id, good.id);
    expect(store.loadFailed, isFalse);
  });

  test('a non-array payload marks the load as failed', () async {
    SharedPreferences.setMockInitialValues({
      RemoteSourceStore.prefsKey: jsonEncode({'nope': true}),
    });

    final store = RemoteSourceStore();
    await store.ready;

    expect(store.list, isEmpty);
    expect(store.loadFailed, isTrue);
  });

  test('invalid input is rejected before it reaches the disk', () async {
    final store = RemoteSourceStore();
    final invalid = RemoteSource(
      id: 'bad',
      kind: RemoteSourceKind.ftp,
      displayName: 'bad',
      host: '',
      port: 21,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    await expectLater(store.add(invalid), throwsStateError);
    expect(store.list, isEmpty);
    expect(await _rawPrefs(), isNull);
  });
}
