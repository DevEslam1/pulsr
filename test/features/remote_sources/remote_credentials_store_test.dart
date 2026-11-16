// P0-1 remote sources: secure credential storage behind a testable interface.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/remote_sources/remote_credentials_store.dart';

class _FakeStorage implements RemoteCredentialStorage {
  final Map<String, String> values = <String, String>{};
  bool failWrites = false;
  bool failReads = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('keystore unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('keystore unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('save then read returns the same pair under a per-source key', () async {
    final storage = _FakeStorage();
    final store = RemoteCredentialsStore(storage);

    await store.save('src-1', const RemoteCredentials(
      username: 'media',
      password: 's3cret',
    ));

    final restored = await store.read('src-1');
    expect(restored?.username, 'media');
    expect(restored?.password, 's3cret');
    expect(
      storage.values.keys.single,
      RemoteCredentialsStore.keyFor('src-1'),
    );
    expect(
      storage.values.keys.single,
      startsWith(RemoteCredentialsStore.keyPrefix),
    );
  });

  test('sources do not share a slot', () async {
    final storage = _FakeStorage();
    final store = RemoteCredentialsStore(storage);

    await store.save('a', const RemoteCredentials(username: 'a', password: '1'));
    await store.save('b', const RemoteCredentials(username: 'b', password: '2'));

    expect((await store.read('a'))?.password, '1');
    expect((await store.read('b'))?.password, '2');
  });

  test('delete removes only that source', () async {
    final storage = _FakeStorage();
    final store = RemoteCredentialsStore(storage);

    await store.save('a', const RemoteCredentials(username: 'a', password: '1'));
    await store.save('b', const RemoteCredentials(username: 'b', password: '2'));
    await store.delete('a');

    expect(await store.read('a'), isNull);
    expect(await store.read('b'), isNotNull);
  });

  test('read returns null for a missing or malformed blob', () async {
    final storage = _FakeStorage();
    final store = RemoteCredentialsStore(storage);

    expect(await store.read('missing'), isNull);

    storage.values[RemoteCredentialsStore.keyFor('broken')] = 'not json';
    expect(await store.read('broken'), isNull);

    storage.values[RemoteCredentialsStore.keyFor('array')] = jsonEncode([1]);
    expect(await store.read('array'), isNull);
  });

  test('a keystore read failure degrades to anonymous access', () async {
    final storage = _FakeStorage()..failReads = true;
    final store = RemoteCredentialsStore(storage);

    expect(await store.read('a'), isNull);
  });

  test('a keystore write failure surfaces as a StateError', () async {
    final storage = _FakeStorage()..failWrites = true;
    final store = RemoteCredentialsStore(storage);

    await expectLater(
      store.save('a', const RemoteCredentials(username: 'a', password: '1')),
      throwsStateError,
    );
  });

  test('credentials toString never prints the password', () {
    const credentials =
        RemoteCredentials(username: 'media', password: 's3cret');

    expect(credentials.toString(), isNot(contains('s3cret')));
    expect(credentials.toString(), contains('media'));
    expect(credentials.isEmpty, isFalse);
    expect(
      const RemoteCredentials(username: '', password: '').isEmpty,
      isTrue,
    );
  });
}
