// P1-8: the UPnP provider maps a ContentDirectory tree onto provider paths and
// streams the resource URI behind each item.
//
// The fake control point answers Browse by ObjectID, so the tests also prove
// that listing uses direct children, that stat/openRead use BrowseMetadata, and
// that non-audio or non-HTTP items never reach the browser.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pulsr/data/remote/upnp_content_directory.dart';
import 'package:pulsr/domain/interfaces/remote_fs_provider.dart';
import 'package:pulsr/domain/models/remote_source.dart';
import 'package:pulsr/features/remote_sources/upnp_fs_provider.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.handler);

  final Future<http.StreamedResponse> Function(http.Request request) handler;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    expect(request, isA<http.Request>());
    final typed = request as http.Request;
    requests.add(typed);
    return handler(typed);
  }
}

http.StreamedResponse _xml(String body, {int status = 200}) =>
    http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
      headers: const {'content-type': 'text/xml; charset="utf-8"'},
    );

String _browseResponse(String didl) => '<?xml version="1.0"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
    '<s:Body>'
    '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">'
    '<Result>${UpnpContentDirectory.escapeXml(didl)}</Result>'
    '<NumberReturned>1</NumberReturned><TotalMatches>1</TotalMatches>'
    '<UpdateID>3</UpdateID>'
    '</u:BrowseResponse>'
    '</s:Body></s:Envelope>';

String _fault(int code) => '<?xml version="1.0"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
    '<s:Body><s:Fault><faultcode>s:Client</faultcode>'
    '<faultstring>UPnPError</faultstring><detail>'
    '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'
    '<errorCode>$code</errorCode>'
    '<errorDescription>No such object</errorDescription>'
    '</UPnPError></detail></s:Fault></s:Body></s:Envelope>';

String _containerXml({required String id, required String title}) =>
    '<container id="$id" parentID="0" childCount="1">'
    '<dc:title>$title</dc:title>'
    '<upnp:class>object.container.album.musicAlbum</upnp:class>'
    '</container>';

String _itemXml({
  required String id,
  required String title,
  String? resource,
  String? klass = 'object.item.audioItem.musicTrack',
  int? size,
}) {
  final buffer = StringBuffer()
    ..write('<item id="$id" parentID="1">')
    ..write('<dc:title>$title</dc:title>');
  if (klass != null) buffer.write('<upnp:class>$klass</upnp:class>');
  if (resource != null) {
    buffer
      ..write('<res protocolInfo="http-get:*:audio/flac:*"')
      ..write(size == null ? '' : ' size="$size"')
      ..write('>$resource</res>');
  }
  buffer.write('</item>');
  return buffer.toString();
}

const String _audioResource = 'http://192.168.1.5:8200/MediaItems/10.flac';

String _childrenDidl() => '<DIDL-Lite>'
    '${_containerXml(id: '1', title: 'Albums')}'
    '${_itemXml(id: '10', title: 'Joga', resource: _audioResource, size: 500)}'
    '${_itemXml(id: '11', title: 'Camera', resource: 'rtsp://192.168.1.5:554/2')}'
    '${_itemXml(id: '12', title: 'Video', resource: 'http://192.168.1.5:8200/12.mp4', klass: 'object.item.videoItem')}'
    '</DIDL-Lite>';

String _albumDidl() => '<DIDL-Lite>'
    '${_itemXml(id: '10', title: 'Joga', resource: _audioResource, size: 500)}'
    '</DIDL-Lite>';

const String _controlUrl = 'http://192.168.1.5:8200/control/cds';

RemoteSource _source() => RemoteSource(
      id: 'upnp-1',
      kind: RemoteSourceKind.upnp,
      displayName: 'Living room NAS',
      host: '192.168.1.5',
      port: 8200,
      rootPath: '/control/cds',
      createdAt: DateTime.utc(2026),
    );

/// Parses a Browse request and answers it; other requests go to [resource].
_FakeHttpClient _server({
  http.StreamedResponse Function(http.Request request)? resource,
}) {
  return _FakeHttpClient((request) async {
    if (request.method != 'POST') {
      final handler = resource;
      if (handler == null) fail('the test did not expect a resource request');
      return handler(request);
    }
    final body = request.body;
    final id =
        RegExp(r'<ObjectID>([^<]*)</ObjectID>').firstMatch(body)?.group(1);
    final flag =
        RegExp(r'<BrowseFlag>([^<]*)</BrowseFlag>').firstMatch(body)?.group(1);
    if (flag == UpnpContentDirectory.browseMetadata) {
      if (id == '10') {
        return _xml(_browseResponse(
          '<DIDL-Lite>'
          '${_itemXml(id: '10', title: 'Joga', resource: _audioResource, size: 500)}'
          '</DIDL-Lite>',
        ));
      }
      if (id == '1') {
        return _xml(_browseResponse(
          '<DIDL-Lite>${_containerXml(id: '1', title: 'Albums')}</DIDL-Lite>',
        ));
      }
      return _xml(_fault(701));
    }
    if (id == UpnpContentDirectory.rootObjectId) {
      return _xml(_browseResponse(_childrenDidl()));
    }
    if (id == '1') return _xml(_browseResponse(_albumDidl()));
    return _xml(_fault(710));
  });
}

UpnpFsProvider _provider(_FakeHttpClient client) => UpnpFsProvider(
      _source(),
      controlUrl: Uri.parse(_controlUrl),
      client: client,
      timeout: const Duration(seconds: 2),
    );

void main() {
  test('the persisted source rebuilds the same control URL', () {
    expect(
      UpnpFsProvider.controlUrlFor(_source()),
      Uri.parse(_controlUrl),
    );
    expect(UpnpFsProvider.containerPath('1'), 'c/1');
    expect(UpnpFsProvider.itemPath('10'), 'i/10');
  });

  group('listing', () {
    test('root lists containers and playable audio items only', () async {
      final provider = _provider(_server());
      final entries = await provider.list('');

      expect(entries, hasLength(2));
      expect(entries.first.path, 'c/1');
      expect(entries.first.name, 'Albums');
      expect(entries.first.isDirectory, isTrue);
      expect(entries.last.path, 'i/10');
      expect(entries.last.name, 'Joga');
      expect(entries.last.isDirectory, isFalse);
      expect(entries.last.sizeBytes, 500);
      // The rtsp item and the video item are not playable in this pipeline.
      expect(entries.map((entry) => entry.path), isNot(contains('i/11')));
      expect(entries.map((entry) => entry.path), isNot(contains('i/12')));
    });

    test('a container lists its children through its object id', () async {
      final provider = _provider(_server());
      final entries = await provider.list('c/1');

      expect(entries.single.path, 'i/10');
      expect(entries.single.name, 'Joga');
    });

    test('a missing container is a typed not-found failure', () async {
      final provider = _provider(_server());

      await expectLater(
        provider.list('c/999'),
        throwsA(isA<RemoteNotFoundError>()),
      );
    });

    test('a malformed path is rejected', () async {
      final provider = _provider(_server());

      await expectLater(
        provider.list('x/1'),
        throwsA(isA<RemoteProtocolError>()),
      );
    });
  });

  group('stat', () {
    test('the root is a synthetic folder named after the source', () async {
      final provider = _provider(_server());
      final entry = await provider.stat('');

      expect(entry?.path, '');
      expect(entry?.name, 'Living room NAS');
      expect(entry?.isDirectory, isTrue);
    });

    test('an item reports the size its resource advertises', () async {
      final provider = _provider(_server());
      final entry = await provider.stat('i/10');

      expect(entry?.isDirectory, isFalse);
      expect(entry?.name, 'Joga');
      expect(entry?.sizeBytes, 500);
    });

    test('a container reports itself as a folder', () async {
      final provider = _provider(_server());
      final entry = await provider.stat('c/1');

      expect(entry?.isDirectory, isTrue);
      expect(entry?.name, 'Albums');
    });

    test('a vanished object is a miss, not an error', () async {
      final provider = _provider(_server());

      expect(await provider.stat('i/404'), isNull);
    });
  });

  group('openRead', () {
    final bytes = utf8.encode('0123456789');

    test('resolves the resource and forwards the Range header', () async {
      final client = _server(
        resource: (request) {
          expect(request.url, Uri.parse(_audioResource));
          expect(
            request.headers['range'] ?? request.headers['Range'],
            'bytes=2-5',
          );
          return http.StreamedResponse(
            Stream<List<int>>.value(bytes.sublist(2, 6)),
            206,
          );
        },
      );
      final provider = _provider(client);

      final received = await provider
          .openRead('i/10', start: 2, end: 5)
          .expand((chunk) => chunk)
          .toList();

      expect(received, bytes.sublist(2, 6));
    });

    test('skips locally when the server ignores Range', () async {
      final provider = _provider(
        _server(
          resource: (_) => http.StreamedResponse(
            Stream<List<int>>.value(bytes),
            200,
          ),
        ),
      );

      final received = await provider
          .openRead('i/10', start: 2, end: 5)
          .expand((chunk) => chunk)
          .toList();

      expect(received, bytes.sublist(2, 6));
    });

    test('a container is not streamable', () async {
      final provider = _provider(_server());

      await expectLater(
        provider.openRead('c/1').toList(),
        throwsA(isA<RemoteProtocolError>()),
      );
    });

    test('maps HTTP failures to the typed remote errors', () async {
      Future<void> expectFailure(int status, Matcher matcher) async {
        final provider = _provider(
          _server(
            resource: (_) => http.StreamedResponse(
              Stream<List<int>>.value(const <int>[]),
              status,
            ),
          ),
        );
        await expectLater(provider.openRead('i/10').toList(), matcher);
      }

      await expectFailure(401, throwsA(isA<RemoteAuthError>()));
      await expectFailure(404, throwsA(isA<RemoteNotFoundError>()));
      await expectFailure(416, throwsA(isA<RemoteProtocolError>()));
      await expectFailure(503, throwsA(isA<RemoteUnavailableError>()));
    });

    test('disables redirects to prevent redirect-SSRF', () async {
      bool? followRedirects;
      final provider = _provider(
        _server(
          resource: (request) {
            followRedirects = request.followRedirects;
            return http.StreamedResponse(
              Stream<List<int>>.value(const <int>[]),
              302,
              headers: const {'location': 'http://127.0.0.1:12345/secret'},
            );
          },
        ),
      );

      await expectLater(
        provider.openRead('i/10').toList(),
        throwsA(isA<RemoteProtocolError>()),
      );
      expect(followRedirects, isFalse);
    });
  });

  group('testConnection', () {
    test('browses the root once and reports success', () async {
      final client = _server();
      final provider = _provider(client);

      expect(await provider.testConnection(), isTrue);
      expect(client.requests, hasLength(1));
      expect(client.requests.single.method, 'POST');
    });

    test('returns false instead of throwing when the server is gone', () async {
      final provider = _provider(
        _FakeHttpClient((_) async => _xml('', status: 500)),
      );

      expect(await provider.testConnection(), isFalse);
    });
  });
}
