// Fixture-based tests for the UPnP ContentDirectory control point: exact SOAP
// bytes, DIDL-Lite parsing (nested containers, entities, sparse objects),
// SOAP faults, TotalMatches paging and malformed payloads.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pulsr/data/remote/upnp_content_directory.dart';

/// Fake transport: records every request and answers through [handler].
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

http.StreamedResponse _xmlResponse(String body, {int status = 200}) =>
    http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
      headers: const {'content-type': 'text/xml; charset="utf-8"'},
    );

String _browseResponse({
  String? didl,
  int? numberReturned,
  int? totalMatches,
  String? resultTagOverride,
}) {
  final buffer = StringBuffer()
    ..write('<?xml version="1.0"?>')
    ..write('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">')
    ..write('<s:Body>')
    ..write('<u:BrowseResponse '
        'xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">');
  if (resultTagOverride != null) {
    buffer.write(resultTagOverride);
  } else if (didl != null) {
    buffer.write('<Result>${UpnpContentDirectory.escapeXml(didl)}</Result>');
  }
  if (numberReturned != null) {
    buffer.write('<NumberReturned>$numberReturned</NumberReturned>');
  }
  if (totalMatches != null) {
    buffer.write('<TotalMatches>$totalMatches</TotalMatches>');
  }
  buffer
    ..write('<UpdateID>7</UpdateID>')
    ..write('</u:BrowseResponse></s:Body></s:Envelope>');
  return buffer.toString();
}

String _soapFault(int code, String description) => '<?xml version="1.0"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
    '<s:Body><s:Fault><faultcode>s:Client</faultcode>'
    '<faultstring>UPnPError</faultstring><detail>'
    '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'
    '<errorCode>$code</errorCode>'
    '<errorDescription>$description</errorDescription>'
    '</UPnPError></detail></s:Fault></s:Body></s:Envelope>';

const String _libraryDidl =
    '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"'
    ' xmlns:dc="http://purl.org/dc/elements/1.1/"'
    ' xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
    '<container id="64" parentID="0" childCount="2" restricted="1">'
    '<dc:title>Albums &amp; EPs &#8212; 2024</dc:title>'
    '<upnp:class>object.container.album.musicAlbum</upnp:class>'
    '<upnp:artist>Bj&#246;rk</upnp:artist>'
    '</container>'
    '<item id="64/1" parentID="64" restricted="1">'
    '<dc:title>J&#243;ga</dc:title>'
    '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
    '<dc:creator>Bj&#246;rk</dc:creator>'
    '<upnp:artist>Bj&#246;rk</upnp:artist>'
    '<upnp:album>Homogenic</upnp:album>'
    '<res protocolInfo="http-get:*:audio/flac:*"'
    ' duration="0:05:04.500" size="1234">'
    'http://192.168.1.5:8200/MediaItems/1.flac</res>'
    '</item>'
    '<item id="64/2" parentID="64" restricted="1">'
    '<dc:title>Camera</dc:title>'
    '<upnp:class>object.item.audioItem</upnp:class>'
    '<res protocolInfo="rtsp:*:*:*">rtsp://192.168.1.5:554/track/2</res>'
    '</item>'
    '<item id="64/3" parentID="64" restricted="1">'
    '<dc:title>Sparse</dc:title>'
    '</item>'
    '<item id="" parentID="64"><dc:title>No id</dc:title></item>'
    '</DIDL-Lite>';

void main() {
  final controlUrl = Uri.parse('http://192.168.1.5:8200/control/cds');

  group('Browse request', () {
    test('builds the exact SOAP envelope', () {
      expect(
        UpnpContentDirectory.buildBrowseEnvelope(objectId: '0'),
        '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
        ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">'
        '<ObjectID>0</ObjectID>'
        '<BrowseFlag>BrowseDirectChildren</BrowseFlag>'
        '<Filter>*</Filter>'
        '<StartingIndex>0</StartingIndex>'
        '<RequestedCount>200</RequestedCount>'
        '<SortCriteria></SortCriteria>'
        '</u:Browse>'
        '</s:Body>'
        '</s:Envelope>',
      );
    });

    test('entity-escapes an obfuscated object id', () {
      final envelope = UpnpContentDirectory.buildBrowseEnvelope(
        objectId: '0/<album>&"x"',
        startingIndex: 40,
        requestedCount: 25,
        sortCriteria: '+dc:title',
      );
      expect(
          envelope,
          contains('<ObjectID>0/&lt;album&gt;&amp;&quot;x&quot;'
              '</ObjectID>'));
      expect(envelope, contains('<StartingIndex>40</StartingIndex>'));
      expect(envelope, contains('<RequestedCount>25</RequestedCount>'));
      expect(envelope, contains('<SortCriteria>+dc:title</SortCriteria>'));
      expect(envelope, isNot(contains('<album>')));
    });

    test('posts with the quoted SOAPACTION and parses the page', () async {
      final fake = _FakeHttpClient((_) async => _xmlResponse(_browseResponse(
            didl: _libraryDidl,
            numberReturned: 4,
            totalMatches: 12,
          )));
      final client = UpnpContentDirectory(client: fake);

      final page = await client.browse(controlUrl: controlUrl);

      expect(fake.requests, hasLength(1));
      final request = fake.requests.single;
      expect(request.method, 'POST');
      expect(request.url, controlUrl);
      expect(
        request.headers['SOAPACTION'],
        '"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"',
      );
      expect(request.headers['Content-Type'], contains('text/xml'));
      expect(
          request.body,
          contains('<BrowseFlag>BrowseDirectChildren'
              '</BrowseFlag>'));
      expect(page.objects, hasLength(4));
      expect(page.numberReturned, 4);
      expect(page.totalMatches, 12);
      expect(page.startingIndex, 0);
      expect(page.hasMore, isTrue);
    });

    test('clamps negative paging arguments', () async {
      final fake = _FakeHttpClient(
          (_) async => _xmlResponse(_browseResponse(didl: _libraryDidl)));
      final client = UpnpContentDirectory(client: fake);

      final page = await client.browse(
        controlUrl: controlUrl,
        start: -10,
        count: -5,
      );

      expect(fake.requests.single.body,
          contains('<StartingIndex>0</StartingIndex>'));
      expect(fake.requests.single.body,
          contains('<RequestedCount>0</RequestedCount>'));
      expect(page.objects, hasLength(4));
    });
  });

  group('DIDL-Lite parsing', () {
    test('decodes entities and maps every metadata field', () {
      final objects = UpnpContentDirectory.parseDidlLite(_libraryDidl);

      final container = objects.first;
      expect(container.id, '64');
      expect(container.parentId, '0');
      expect(container.title, 'Albums & EPs \u2014 2024');
      expect(container.upnpClass, 'object.container.album.musicAlbum');
      expect(container.artist, 'Bj\u00f6rk');
      expect(container.album, isNull);
      expect(container.isContainer, isTrue);
      expect(container.childCount, 2);
      expect(container.resourceUrl, isNull);

      final track = objects[1];
      expect(track.id, '64/1');
      expect(track.parentId, '64');
      expect(track.title, 'J\u00f3ga');
      expect(track.upnpClass, 'object.item.audioItem.musicTrack');
      expect(track.artist, 'Bj\u00f6rk');
      expect(track.album, 'Homogenic');
      expect(track.duration,
          const Duration(minutes: 5, seconds: 4, milliseconds: 500));
      expect(track.resourceUrl, 'http://192.168.1.5:8200/MediaItems/1.flac');
      expect(track.protocolInfo, 'http-get:*:audio/flac:*');
      expect(track.isContainer, isFalse);
      expect(track.childCount, isNull);
      expect(track.isAudioItem, isTrue);
      expect(track.isHttpResource, isTrue);
      expect(track.resourceUri, Uri.parse(track.resourceUrl!));
    });

    test('tolerates missing fields and skips objects without an id', () {
      final objects = UpnpContentDirectory.parseDidlLite(_libraryDidl);

      expect(objects, hasLength(4),
          reason: 'the empty-id item cannot be addressed and is dropped');
      final sparse = objects.last;
      expect(sparse.id, '64/3');
      expect(sparse.title, 'Sparse');
      expect(sparse.upnpClass, isNull);
      expect(sparse.artist, isNull);
      expect(sparse.album, isNull);
      expect(sparse.duration, isNull);
      expect(sparse.resourceUrl, isNull);
      expect(sparse.protocolInfo, isNull);
      expect(sparse.childCount, isNull);
      expect(sparse.isAudioItem, isFalse);
    });

    test('preserves a non-HTTP resource and refuses to play it', () {
      final objects = UpnpContentDirectory.parseDidlLite(_libraryDidl);
      final camera = objects[2];

      expect(camera.resourceUrl, 'rtsp://192.168.1.5:554/track/2');
      expect(camera.resourceUri?.scheme, 'rtsp');
      expect(camera.isHttpResource, isFalse);
      expect(camera.playableHttpUri(), isNull);
      expect(
          camera.playableHttpUri(allowedHostSuffixes: {'192.168.1.5'}), isNull);
    });

    test('accepts unprefixed and default-namespaced metadata', () {
      const xml = '<DIDL-Lite><container id="a" parentID="0">'
          '<title>Plain</title><class>object.container</class>'
          '<artist>Nobody</artist></container></DIDL-Lite>';

      final object = UpnpContentDirectory.parseDidlLite(xml).single;

      expect(object.title, 'Plain');
      expect(object.upnpClass, 'object.container');
      expect(object.artist, 'Nobody');
      expect(object.isContainer, isTrue);
    });

    test('flattens nested containers in document order', () {
      const xml = '<DIDL-Lite>'
          '<container id="a" parentID="0"><title>Outer</title>'
          '<container id="b" parentID="a"><title>Inner</title>'
          '<upnp:artist>Hidden</upnp:artist>'
          '<item id="c" parentID="b"><title>Leaf</title></item>'
          '</container></container></DIDL-Lite>';

      final objects = UpnpContentDirectory.parseDidlLite(xml);

      expect(objects.map((o) => o.id), ['a', 'b', 'c']);
      expect(objects[0].artist, isNull,
          reason: 'a nested item artist must not leak into its container');
      expect(objects[1].artist, 'Hidden');
      expect(objects[2].parentId, 'b');
    });

    test('selects the first HTTP audio resource over companion entries', () {
      const xml = '<DIDL-Lite><item id="x" parentID="0"><title>Pick</title>'
          '<res protocolInfo="urn:schemas-upnp-org:track:1">urn:track:1</res>'
          '<res protocolInfo="http-get:*:audio/mpeg:*"'
          ' duration="0:01:00">http://h/a.mp3</res>'
          '<res protocolInfo="http-get:*:audio/flac:*"'
          ' duration="0:02:00">http://h/a.flac</res>'
          '</item></DIDL-Lite>';

      final object = UpnpContentDirectory.parseDidlLite(xml).single;

      expect(object.resourceUrl, 'http://h/a.mp3');
      expect(object.protocolInfo, 'http-get:*:audio/mpeg:*');
      expect(object.duration, const Duration(minutes: 1));
    });

    test('handles CDATA and a bare ampersand without failing the page', () {
      const xml = '<DIDL-Lite><item id="1"><title><![CDATA[Tom & Jerry '
          '<Live>]]></title></item><item id="2"><title>AC/DC & friends'
          '</title></item></DIDL-Lite>';

      final objects = UpnpContentDirectory.parseDidlLite(xml);

      expect(objects[0].title, 'Tom & Jerry <Live>');
      expect(objects[1].title, 'AC/DC & friends');
    });

    test('parses IN and OUT durations', () {
      expect(
        UpnpContentDirectory.parseUpnpDuration('0:05:04.500'),
        const Duration(minutes: 5, seconds: 4, milliseconds: 500),
      );
      expect(UpnpContentDirectory.parseUpnpDuration('93:20'),
          const Duration(hours: 1, minutes: 33, seconds: 20));
      expect(UpnpContentDirectory.parseUpnpDuration('NOT_IMPLEMENTED'), isNull);
      expect(UpnpContentDirectory.parseUpnpDuration(''), isNull);
      expect(UpnpContentDirectory.parseUpnpDuration('1:2:3:4'), isNull);
      expect(UpnpContentDirectory.parseUpnpDuration('a:b'), isNull);
    });

    test('reports malformed DIDL-Lite as a typed failure', () {
      expect(
        () => UpnpContentDirectory.parseDidlLite(
            '<DIDL-Lite><item id="1"><title>x</title></DIDL-Lite>'),
        throwsA(isA<UpnpBrowseError>()
            .having((error) => error.code, 'code', 'UPNP_XML_MALFORMED')),
      );
      expect(
        () => UpnpContentDirectory.parseDidlLite('<DIDL-Lite><item id="1">'),
        throwsA(isA<UpnpBrowseError>()
            .having((error) => error.code, 'code', 'UPNP_XML_MALFORMED')),
      );
      expect(
        () => UpnpContentDirectory.parseDidlLite('</DIDL-Lite>oops'),
        throwsA(isA<UpnpBrowseError>()
            .having((error) => error.code, 'code', 'UPNP_XML_MALFORMED')),
      );
    });

    test(
        'allows an exact LAN host through the resource policy only when '
        'allowlisted', () {
      final objects = UpnpContentDirectory.parseDidlLite(_libraryDidl);
      final track = objects[1];

      expect(track.playableHttpUri(), isNull,
          reason: 'a private address is not a safe target by default');
      expect(
        track.playableHttpUri(allowedHostSuffixes: {'192.168.1.5'}),
        Uri.parse('http://192.168.1.5:8200/MediaItems/1.flac'),
      );
      expect(track.playableHttpUri(requireHttps: true), isNull);
    });
  });

  group('Browse responses', () {
    test('handles an empty result with zero matches', () async {
      final fake = _FakeHttpClient((_) async => _xmlResponse(_browseResponse(
            didl: '',
            numberReturned: 0,
            totalMatches: 0,
          )));
      final client = UpnpContentDirectory(client: fake);

      final page = await client.browse(controlUrl: controlUrl);

      expect(page.objects, isEmpty);
      expect(page.isEmpty, isTrue);
      expect(page.totalMatches, 0);
      expect(page.numberReturned, 0);
      expect(page.hasMore, isFalse);
    });

    test('rejects a response without a Result element', () async {
      final fake = _FakeHttpClient((_) async => _xmlResponse(
          _browseResponse(resultTagOverride: '<UpdateID>1</UpdateID>')));
      final client = UpnpContentDirectory(client: fake);

      await expectLater(
        client.browse(controlUrl: controlUrl),
        throwsA(isA<UpnpBrowseError>()
            .having((error) => error.code, 'code', 'UPNP_BAD_RESPONSE')),
      );
    });

    test('throws the SOAP fault code from an HTTP 500 response', () async {
      final fake = _FakeHttpClient((_) async =>
          _xmlResponse(_soapFault(701, 'No such object'), status: 500));
      final client = UpnpContentDirectory(client: fake);

      await expectLater(
        client.browse(controlUrl: controlUrl),
        throwsA(isA<UpnpBrowseError>()
            .having((error) => error.code, 'code', 'UPNP_UPNP_ERROR_701')
            .having((error) => error.errorCode, 'errorCode', 701)
            .having((error) => error.errorDescription, 'description',
                'No such object')
            .having((error) => error.action, 'action', 'Browse')
            .having((error) => error.userMessage, 'message',
                'The media server does not have that object.')),
      );
    });

    test('throws a SOAP fault delivered with HTTP 200', () async {
      final fake = _FakeHttpClient(
          (_) async => _xmlResponse(_soapFault(720, 'Cannot process')));
      final client = UpnpContentDirectory(client: fake);

      await expectLater(
        client.browse(controlUrl: controlUrl),
        throwsA(isA<UpnpBrowseError>()
            .having((error) => error.code, 'code', 'UPNP_UPNP_ERROR_720')),
      );
    });

    test('falls back to the HTTP status for a non-XML error page', () async {
      final fake = _FakeHttpClient(
          (_) async => _xmlResponse('<html>nope</html>', status: 500));
      final client = UpnpContentDirectory(client: fake);

      await expectLater(
        client.browse(controlUrl: controlUrl),
        throwsA(isA<UpnpBrowseError>()
            .having((error) => error.code, 'code', 'UPNP_HTTP_500')),
      );
    });

    test('maps a timeout and a dead socket to typed failures', () async {
      final slow = UpnpContentDirectory(
        client:
            _FakeHttpClient((_) async => throw TimeoutException('no answer')),
        timeout: const Duration(milliseconds: 5),
      );
      await expectLater(
        slow.browse(controlUrl: controlUrl),
        throwsA(isA<UpnpBrowseError>()
            .having((error) => error.code, 'code', 'UPNP_TIMEOUT')),
      );

      final refused = UpnpContentDirectory(
        client: _FakeHttpClient(
            (_) async => throw const SocketException('connection refused')),
      );
      await expectLater(
        refused.browse(controlUrl: controlUrl),
        throwsA(isA<UpnpBrowseError>()
            .having((error) => error.code, 'code', 'UPNP_NETWORK_ERROR')),
      );
    });

    test('rejects credentials embedded in the control URL', () async {
      final fake = _FakeHttpClient((_) async => _xmlResponse(''));
      final client = UpnpContentDirectory(client: fake);

      await expectLater(
        client.browse(
            controlUrl: Uri.parse('http://user:secret@192.168.1.5:8200/c')),
        throwsA(isA<UpnpBrowseError>()
            .having(
                (error) => error.code, 'code', 'UPNP_CONTROL_URL_CREDENTIALS')
            .having((error) => error.userMessage, 'message',
                isNot(contains('secret')))),
      );
      expect(fake.requests, isEmpty);
    });

    test('applies the target policy to the control URL', () async {
      final fake = _FakeHttpClient(
          (_) async => _xmlResponse(_browseResponse(didl: _libraryDidl)));

      final untrusted = UpnpContentDirectory(
        client: fake,
        trustRequestHost: false,
      );
      await expectLater(
        untrusted.browse(controlUrl: controlUrl),
        throwsA(isA<UpnpBrowseError>().having(
            (error) => error.code, 'code', 'UPNP_CONTROL_URL_PRIVATENETWORK')),
      );

      final allowlisted = UpnpContentDirectory(
        client: fake,
        trustRequestHost: false,
        allowedHostSuffixes: {'192.168.1.5'},
      );
      final page = await allowlisted.browse(controlUrl: controlUrl);
      expect(page.objects, hasLength(4));

      final badScheme = UpnpContentDirectory(client: fake);
      await expectLater(
        badScheme.browse(controlUrl: Uri.parse('ftp://192.168.1.5/control')),
        throwsA(isA<UpnpBrowseError>().having(
            (error) => error.code, 'code', 'UPNP_CONTROL_URL_INVALIDSCHEME')),
      );
    });
  });

  group('browseAll paging', () {
    test('pages with TotalMatches and preserves order', () async {
      final tracks = List<String>.generate(5, (index) => 't$index');
      final starts = <int>[];
      final fake = _FakeHttpClient((request) async {
        final start = int.parse(RegExp(r'<StartingIndex>(\d+)</StartingIndex>')
            .firstMatch(request.body)!
            .group(1)!);
        final count = int.parse(
            RegExp(r'<RequestedCount>(\d+)</RequestedCount>')
                .firstMatch(request.body)!
                .group(1)!);
        starts.add(start);
        final page =
            tracks.sublist(start, math.min(start + count, tracks.length));
        final didl = '<DIDL-Lite>${page.map((id) => '<item id="$id" '
            'parentID="0"><dc:title>$id</dc:title></item>').join()}</DIDL-Lite>';
        return _xmlResponse(_browseResponse(
          didl: didl,
          numberReturned: page.length,
          totalMatches: tracks.length,
        ));
      });
      final client = UpnpContentDirectory(client: fake);

      final objects =
          await client.browseAll(controlUrl: controlUrl, pageSize: 2);

      expect(objects.map((object) => object.id), tracks);
      expect(starts, [0, 2, 4]);
      expect(fake.requests, hasLength(3));
    });

    test('stops on a short page when TotalMatches is absent', () async {
      final tracks = List<String>.generate(3, (index) => 's$index');
      var calls = 0;
      final fake = _FakeHttpClient((request) async {
        calls++;
        final start = int.parse(RegExp(r'<StartingIndex>(\d+)</StartingIndex>')
            .firstMatch(request.body)!
            .group(1)!);
        final count = int.parse(
            RegExp(r'<RequestedCount>(\d+)</RequestedCount>')
                .firstMatch(request.body)!
                .group(1)!);
        final page =
            tracks.sublist(start, math.min(start + count, tracks.length));
        final didl = '<DIDL-Lite>${page.map((id) => '<item id="$id" '
            'parentID="0"><dc:title>$id</dc:title></item>').join()}</DIDL-Lite>';
        return _xmlResponse(_browseResponse(
          didl: didl,
          numberReturned: page.length,
        ));
      });
      final client = UpnpContentDirectory(client: fake);

      final objects =
          await client.browseAll(controlUrl: controlUrl, pageSize: 2);

      expect(objects.map((object) => object.id), tracks);
      expect(calls, 2);
    });

    test('stops immediately on an empty first page', () async {
      final fake = _FakeHttpClient((_) async => _xmlResponse(
          _browseResponse(didl: '', numberReturned: 0, totalMatches: 0)));
      final client = UpnpContentDirectory(client: fake);

      final objects = await client.browseAll(controlUrl: controlUrl);

      expect(objects, isEmpty);
      expect(fake.requests, hasLength(1));
    });
  });

  group('result metadata', () {
    test('hasMore follows TotalMatches', () {
      expect(
        UpnpBrowseResult(
          objects: const [
            UpnpObject(id: 'x', parentId: '0', title: 'x'),
          ],
          totalMatches: 5,
          numberReturned: 2,
          startingIndex: 0,
          requestedCount: 2,
        ).hasMore,
        isTrue,
      );
      expect(
        UpnpBrowseResult(
          objects: const [
            UpnpObject(id: 'y', parentId: '0', title: 'y'),
          ],
          totalMatches: 5,
          numberReturned: 1,
          startingIndex: 4,
          requestedCount: 2,
        ).hasMore,
        isFalse,
      );
      expect(
        UpnpBrowseResult(
          objects: const [],
          totalMatches: 0,
          numberReturned: 2,
          startingIndex: 0,
        ).hasMore,
        isFalse,
      );
    });
  });
}
