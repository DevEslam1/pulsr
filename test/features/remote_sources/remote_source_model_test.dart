// P0-1 remote sources: model normalization, validation and JSON round-trip.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/remote_source.dart';

void main() {
  group('RemoteSource.create', () {
    test('normalizes a pasted URL into host and root', () {
      final source = RemoteSource.create(
        kind: RemoteSourceKind.webdav,
        displayName: '  Living room NAS ',
        host: 'https://nas.local/Music/',
        port: 443,
        rootPath: 'Music//',
        useTls: true,
        username: ' media ',
      );

      expect(source.host, 'nas.local');
      expect(source.displayName, 'Living room NAS');
      expect(source.rootPath, '/Music');
      expect(source.username, 'media');
      expect(source.useTls, isTrue);
      expect(source.isValid, isTrue);
      expect(source.authority, 'nas.local:443');
      expect(source.secretKey, source.id);
    });

    test('falls back to the host when the name is blank', () {
      final source = RemoteSource.create(
        kind: RemoteSourceKind.ftp,
        displayName: '   ',
        host: 'ftp.example.com',
        port: 21,
      );

      expect(source.displayName, 'ftp.example.com');
      expect(source.rootPath, '/');
    });

    test('rejects an empty host', () {
      expect(
        () => RemoteSource.create(
          kind: RemoteSourceKind.webdav,
          displayName: 'x',
          host: '   ',
          port: 80,
        ),
        throwsArgumentError,
      );
    });

    test('rejects ports outside 1..65535', () {
      for (final port in [0, -1, 65536]) {
        expect(
          () => RemoteSource.create(
            kind: RemoteSourceKind.webdav,
            displayName: 'x',
            host: 'nas.local',
            port: port,
          ),
          throwsArgumentError,
          reason: 'port $port must be rejected',
        );
      }
    });

    test('derives a stable id from the endpoint', () {
      final first = RemoteSource.create(
        kind: RemoteSourceKind.webdav,
        displayName: 'A',
        host: 'nas.local',
        port: 443,
        rootPath: '/Music',
      );
      final second = RemoteSource.create(
        kind: RemoteSourceKind.webdav,
        displayName: 'A renamed',
        host: 'NAS.local',
        port: 443,
        rootPath: '/Music',
      );

      expect(second.id, first.id);
    });

    test('different roots produce different ids', () {
      final first = RemoteSource.create(
        kind: RemoteSourceKind.webdav,
        displayName: 'A',
        host: 'nas.local',
        port: 443,
        rootPath: '/Music',
      );
      final second = RemoteSource.create(
        kind: RemoteSourceKind.webdav,
        displayName: 'A',
        host: 'nas.local',
        port: 443,
        rootPath: '/Photos',
      );

      expect(second.id, isNot(first.id));
    });
  });

  group('RemoteSource JSON', () {
    test('round-trips every field and never contains a password', () {
      final source = RemoteSource.create(
        kind: RemoteSourceKind.smb,
        displayName: 'Studio share',
        host: '10.0.0.5',
        port: 445,
        rootPath: '/Music/Studio',
        username: 'eslam',
        credentialKey: 'slot-1',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final json = source.toJson();
      expect(json.containsKey('password'), isFalse);
      expect(json['kind'], 'smb');

      final restored = RemoteSource.fromJson(json);
      expect(restored.id, source.id);
      expect(restored.kind, RemoteSourceKind.smb);
      expect(restored.displayName, 'Studio share');
      expect(restored.host, '10.0.0.5');
      expect(restored.port, 445);
      expect(restored.rootPath, '/Music/Studio');
      expect(restored.username, 'eslam');
      expect(restored.credentialKey, 'slot-1');
      expect(restored.createdAt, source.createdAt);
      expect(restored.secretKey, 'slot-1');
    });

    test('rejects an unknown kind so the store can skip it', () {
      expect(
        () => RemoteSource.fromJson({'kind': 'gopher', 'host': 'a', 'port': 1}),
        throwsFormatException,
      );
    });

    test('rejects an empty host and an out-of-range port', () {
      expect(
        () => RemoteSource.fromJson({'kind': 'ftp', 'host': ' ', 'port': 21}),
        throwsFormatException,
      );
      expect(
        () => RemoteSource.fromJson({
          'kind': 'ftp',
          'host': 'a.example',
          'port': 70000,
        }),
        throwsFormatException,
      );
    });

    test('defaults a missing port to the kind default', () {
      final restored = RemoteSource.fromJson({
        'kind': 'smb',
        'host': 'fileserver',
        'rootPath': '/Share',
      });

      expect(restored.port, 445);
      expect(restored.rootPath, '/Share');
    });
  });

  group('RemoteSource validation helpers', () {
    test('validateHost rejects spaces and an inline port', () {
      expect(RemoteSource.validateHost(''), isNotNull);
      expect(RemoteSource.validateHost('my nas'), isNotNull);
      expect(RemoteSource.validateHost('nas.local:80'), isNotNull);
      expect(RemoteSource.validateHost('nas.local'), isNull);
      expect(RemoteSource.validateHost('192.168.1.10'), isNull);
    });

    test('validatePort only accepts 1..65535', () {
      expect(RemoteSource.validatePort(1), isNull);
      expect(RemoteSource.validatePort(65535), isNull);
      expect(RemoteSource.validatePort(0), isNotNull);
      expect(RemoteSource.validatePort(65536), isNotNull);
    });

    test('normalizeRootPath keeps a single leading slash', () {
      expect(RemoteSource.normalizeRootPath(''), '/');
      expect(RemoteSource.normalizeRootPath('/'), '/');
      expect(RemoteSource.normalizeRootPath('a/b/'), '/a/b');
      expect(RemoteSource.normalizeRootPath('/a/b//'), '/a/b');
    });

    test('normalizeHost strips brackets from an IPv6 literal', () {
      expect(RemoteSource.normalizeHost('[fd00::1]'), 'fd00::1');
    });
  });

  group('RemoteEntry', () {
    test('round-trips and normalizes the path', () {
      final entry = RemoteEntry.fromJson({
        'path': '/Music/Album/track.flac',
        'name': 'track.flac',
        'isDirectory': false,
        'sizeBytes': 42,
        'modifiedAt': 1700000000000,
        'etag': 'abc',
      });

      expect(entry.path, 'Music/Album/track.flac');
      expect(entry.sizeBytes, 42);
      expect(entry.modifiedAt, isNotNull);
      expect(entry.toJson()['etag'], 'abc');
      expect(entry.toJson()['sizeBytes'], 42);
    });

    test('compare sorts folders first then case-insensitive name', () {
      final entries = [
        const RemoteEntry(path: 'b.mp3', name: 'b.mp3', isDirectory: false),
        const RemoteEntry(path: 'Zed', name: 'Zed', isDirectory: true),
        const RemoteEntry(path: 'A.mp3', name: 'A.mp3', isDirectory: false),
        const RemoteEntry(path: 'alpha', name: 'alpha', isDirectory: true),
      ]..sort(RemoteEntry.compare);

      expect(entries.map((e) => e.name), ['alpha', 'Zed', 'A.mp3', 'b.mp3']);
    });
  });
}
