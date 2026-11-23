// P0-1 remote sources: WebDAV PROPFIND parsing and ranged GET over loopback.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/interfaces/remote_fs_provider.dart';
import 'package:pulsr/domain/models/remote_source.dart';
import 'package:pulsr/features/remote_sources/webdav_fs_provider.dart';

const String _nextcloudXml = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns">
  <d:response>
    <d:href>/dav/Music/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
        <d:getlastmodified>Tue, 02 Jan 2024 03:04:05 GMT</d:getlastmodified>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/Albums/</d:href>
    <d:propstat><d:prop>
      <d:resourcetype><d:collection/></d:resourcetype>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/01%20Intro.mp3</d:href>
    <d:propstat><d:prop>
      <d:resourcetype/>
      <d:getcontentlength>1024</d:getcontentlength>
      <d:getlastmodified>Tue, 02 Jan 2024 03:04:05 GMT</d:getlastmodified>
      <d:getetag>"abc123"</d:getetag>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/one%20%26%20two.flac</d:href>
    <d:propstat><d:prop>
      <d:resourcetype/>
      <d:getcontentlength> 2048 </d:getcontentlength>
      <d:getetag>W/"weak-etag"</d:getetag>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';

const String _prefixlessXml = '''<?xml version="1.0"?>
<multistatus xmlns="DAV:">
  <response>
    <href>https://nas.local:5006/root/Sub%20Folder/</href>
    <propstat><prop><resourcetype><collection/></resourcetype></prop></propstat>
  </response>
  <response>
    <href>/root/a.mp3</href>
    <propstat><prop><resourcetype/><getcontentlength>5</getcontentlength></prop></propstat>
  </response>
</multistatus>''';

const String _upperCaseXml = '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/m/Live/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
</D:multistatus>''';

RemoteSource _sourceFor(int port, {String root = '/dav'}) {
  return RemoteSource.create(
    kind: RemoteSourceKind.webdav,
    displayName: 'Test DAV',
    host: '127.0.0.1',
    port: port,
    rootPath: root,
  );
}

void main() {
  group('parseMultiStatus', () {
    test('reads namespace-prefixed entries and skips the request target', () {
      final entries = WebDavFsProvider.parseMultiStatus(
        _nextcloudXml,
        rootPath: '/dav',
        requestPath: 'Music',
      );

      expect(entries.map((e) => e.name), ['Albums', '01 Intro.mp3', 'one & two.flac']);
      final album = entries.first;
      expect(album.isDirectory, isTrue);
      expect(album.path, 'Music/Albums');
      expect(album.sizeBytes, isNull);
      expect(
        album.modifiedAt,
        isNull,
        reason: 'the fixture omits getlastmodified for this collection',
      );

      final track = entries[1];
      expect(track.isDirectory, isFalse);
      expect(track.sizeBytes, 1024);
      expect(track.etag, 'abc123');
      expect(track.modifiedAt?.toUtc(), DateTime.utc(2024, 1, 2, 3, 4, 5));

      final escaped = entries[2];
      expect(escaped.name, 'one & two.flac');
      expect(escaped.sizeBytes, 2048);
      expect(escaped.etag, 'weak-etag');
    });

    test('reads prefix-less XML and absolute hrefs', () {
      final entries = WebDavFsProvider.parseMultiStatus(
        _prefixlessXml,
        rootPath: '/root',
        requestPath: '',
      );

      expect(entries.map((e) => e.path), ['Sub Folder', 'a.mp3']);
      expect(entries.first.isDirectory, isTrue);
      expect(entries.last.sizeBytes, 5);
    });

    test('accepts an upper-case prefix', () {
      final entries = WebDavFsProvider.parseMultiStatus(
        _upperCaseXml,
        rootPath: '/m',
        requestPath: '',
      );

      expect(entries, hasLength(1));
      expect(entries.single.path, 'Live');
      expect(entries.single.isDirectory, isTrue);
    });

    test('keeps the self entry when asked (Depth: 0 stat)', () {
      final entries = WebDavFsProvider.parseMultiStatus(
        _nextcloudXml,
        rootPath: '/dav',
        requestPath: 'Music/01 Intro.mp3',
        keepSelf: true,
      );

      expect(entries.map((e) => e.path), contains('Music/01 Intro.mp3'));
    });

    test('ignores entries outside the configured root', () {
      final entries = WebDavFsProvider.parseMultiStatus(
        _nextcloudXml,
        rootPath: '/other',
        requestPath: '',
      );

      expect(entries, isEmpty);
    });
  });

  group('HTTP behaviour', () {
    late HttpServer server;
    late WebDavFsProvider provider;
    String? authorization;
    String? depthHeader;
    String? rangeHeader;
    var requestCount = 0;
    final payload = List<int>.generate(32, (index) => index);

    setUp(() async {
      requestCount = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requestCount++;
        if (request.method == 'PROPFIND') {
          authorization =
              request.headers.value(HttpHeaders.authorizationHeader);
          depthHeader = request.headers.value('depth');
          await utf8.decoder.bind(request).join();
          request.response.statusCode = 207;
          request.response.headers.contentType =
              ContentType('application', 'xml', charset: 'utf-8');
          request.response.write(_nextcloudXml);
          await request.response.close();
          return;
        }
        if (request.method == 'GET') {
          rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
          final start = int.parse(
            RegExp(r'bytes=(\d+)-').firstMatch(rangeHeader!)!.group(1)!,
          );
          final end = int.parse(rangeHeader!.split('-').last);
          final slice = payload.sublist(start, end + 1);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${payload.length}',
          );
          request.response.add(slice);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
      });
      provider = WebDavFsProvider(
        _sourceFor(server.port),
        username: 'media',
        password: 's3cret',
      );
    });

    tearDown(() async {
      await provider.close();
      await server.close(force: true);
    });

    test('list sends Basic auth and Depth: 1', () async {
      final entries = await provider.list('');

      expect(
        authorization,
        'Basic ${base64Encode(utf8.encode('media:s3cret'))}',
      );
      expect(depthHeader, '1');
      expect(entries.map((e) => e.name), contains('Albums'));
    });

    test('openRead sends a Range header and returns the window', () async {
      final bytes = await provider
          .openRead('01 Intro.mp3', start: 4, end: 11)
          .expand((chunk) => chunk)
          .toList();

      expect(rangeHeader, 'bytes=4-11');
      expect(bytes, payload.sublist(4, 12));
    });

    test('stat uses Depth: 0 and returns the entry itself', () async {
      final entry = await provider.stat('Music/01 Intro.mp3');

      expect(depthHeader, '0');
      expect(entry?.path, 'Music/01 Intro.mp3');
      expect(entry?.sizeBytes, 1024);
    });

    test('a .. segment is rejected before any request is sent', () async {
      await expectLater(
        provider.list('../etc'),
        throwsA(isA<RemoteProtocolError>()),
      );
      expect(requestCount, 0);
    });

    test('a percent-encoded .. segment is rejected too', () async {
      await expectLater(
        provider.list('%2e%2e/etc'),
        throwsA(isA<RemoteProtocolError>()),
      );
      expect(requestCount, 0);
    });
  });

  group('status mapping', () {
    Future<void> expectStatus(int status, Matcher matcher) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = status;
        await request.response.close();
      });
      final provider = WebDavFsProvider(_sourceFor(server.port));
      try {
        await expectLater(provider.list(''), matcher);
      } finally {
        await provider.close();
        await server.close(force: true);
      }
    }

    test('401 becomes RemoteAuthError', () async {
      await expectStatus(401, throwsA(isA<RemoteAuthError>()));
    });

    test('404 becomes RemoteNotFoundError', () async {
      await expectStatus(404, throwsA(isA<RemoteNotFoundError>()));
    });

    test('503 becomes RemoteUnavailableError', () async {
      await expectStatus(503, throwsA(isA<RemoteUnavailableError>()));
    });

    test('418 becomes RemoteProtocolError', () async {
      await expectStatus(418, throwsA(isA<RemoteProtocolError>()));
    });
  });

  test('testConnection reports false instead of throwing', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 401;
      await request.response.close();
    });
    final provider = WebDavFsProvider(_sourceFor(server.port));

    expect(await provider.testConnection(), isFalse);

    await provider.close();
    await server.close(force: true);
  });

  test('rangeHeader builds open and closed windows', () {
    expect(WebDavFsProvider.rangeHeader(0, null), 'bytes=0-');
    expect(WebDavFsProvider.rangeHeader(10, 20), 'bytes=10-20');
  });

  test('does not follow HTTP 302 redirects (SSRF protection)', () async {
    var targetHits = 0;
    final targetServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    targetServer.listen((request) async {
      targetHits++;
      await request.drain<void>();
      request.response.statusCode = 200;
      request.response.write('secret');
      await request.response.close();
    });

    final redirectServer =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    redirectServer.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'http://127.0.0.1:${targetServer.port}/internal',
      );
      await request.response.close();
    });

    final provider = WebDavFsProvider(_sourceFor(redirectServer.port));
    try {
      await expectLater(
        provider.list(''),
        throwsA(isA<RemoteProtocolError>()),
      );
      expect(targetHits, 0);
    } finally {
      await provider.close();
      await redirectServer.close(force: true);
      await targetServer.close(force: true);
    }
  });

  test('skips 404/403 propstat responses, rejects .. hrefs, and decodes numeric XML entities',
      () async {
    const xml = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Music/denied.mp3</d:href>
    <d:propstat>
      <d:prop><d:resourcetype/></d:prop>
      <d:status>HTTP/1.1 404 Not Found</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/../etc/passwd</d:href>
    <d:propstat>
      <d:prop><d:resourcetype/></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/Rock%20&#x27;n&#39;%20Roll%20&amp;amp%3B.mp3</d:href>
    <d:propstat>
      <d:prop><d:resourcetype/><d:getcontentlength>42</d:getcontentlength></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

    final entries = WebDavFsProvider.parseMultiStatus(
      xml,
      rootPath: '/dav',
      requestPath: 'Music',
    );

    expect(entries, hasLength(1));
    expect(entries.single.name, "Rock 'n' Roll &amp;.mp3");
    expect(entries.single.sizeBytes, 42);
  });
}
