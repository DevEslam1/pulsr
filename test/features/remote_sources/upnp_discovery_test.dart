// P1-8: discovery is the half of SSDP the renderer path never needed — picking
// out MediaServer devices and resolving their ContentDirectory control URL.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pulsr/domain/interfaces/remote_fs_provider.dart';
import 'package:pulsr/features/dlna/ssdp_client.dart';
import 'package:pulsr/features/remote_sources/upnp_discovery.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.handler);

  final Future<http.StreamedResponse> Function(http.Request request) handler;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final typed = request as http.Request;
    requests.add(typed);
    return handler(typed);
  }
}

http.StreamedResponse _xml(String body) => http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      headers: const {'content-type': 'text/xml'},
    );

const String _mediaServerXml = '<?xml version="1.0"?>'
    '<root xmlns="urn:schemas-upnp-org:device-1-0">'
    '<URLBase>http://192.168.1.5:8200/</URLBase>'
    '<device>'
    '<deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>'
    '<friendlyName>Living room NAS</friendlyName>'
    '<modelName>DS220+</modelName>'
    '<UDN>uuid:nas-1</UDN>'
    '<serviceList><service>'
    '<serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>'
    '<serviceId>urn:upnp-org:serviceId:ContentDirectory</serviceId>'
    '<controlURL>/ctl/ContentDir</controlURL>'
    '</service></serviceList>'
    '</device></root>';

const String _rendererXml = '<?xml version="1.0"?>'
    '<root><device>'
    '<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>'
    '<friendlyName>Living room TV</friendlyName>'
    '<serviceList><service>'
    '<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>'
    '<controlURL>/ctl/AVTransport</controlURL>'
    '</service></serviceList>'
    '</device></root>';

SsdpResponse _response(String location, {String usn = 'uuid:device'}) =>
    SsdpResponse(
      location: location,
      searchTarget: 'ssdp:all',
      usn: usn,
      server: 'Linux UPnP/1.0',
      sourceAddress: '192.168.1.5',
    );

void main() {
  test('keeps media servers and resolves their control URL', () async {
    final client = _FakeHttpClient((request) async {
      switch (request.url.path) {
        case '/nas.xml':
          return _xml(_mediaServerXml);
        case '/tv.xml':
          return _xml(_rendererXml);
        default:
          fail('unexpected request ${request.url}');
      }
    });
    final discovery = UpnpDiscovery(
      search: (_) async => <SsdpResponse>[
        _response('http://192.168.1.5:8200/nas.xml', usn: 'uuid:nas-1'),
        _response('http://192.168.1.5:49152/tv.xml', usn: 'uuid:tv-1'),
      ],
      client: client,
    );
    addTearDown(discovery.close);

    final servers = await discovery.discover();

    expect(servers, hasLength(1));
    expect(servers.single.friendlyName, 'Living room NAS');
    expect(servers.single.modelName, 'DS220+');
    expect(
      servers.single.contentDirectoryControlUrl,
      Uri.parse('http://192.168.1.5:8200/ctl/ContentDir'),
    );
  });

  test('de-duplicates two replies for the same description', () async {
    final client = _FakeHttpClient((_) async => _xml(_mediaServerXml));
    final discovery = UpnpDiscovery(
      search: (_) async => <SsdpResponse>[
        _response('http://192.168.1.5:8200/nas.xml', usn: 'uuid:nas-1'),
        _response('http://192.168.1.5:8200/nas.xml', usn: 'uuid:nas-1'),
      ],
      client: client,
    );
    addTearDown(discovery.close);

    final servers = await discovery.discover();

    expect(servers, hasLength(1));
    expect(client.requests, hasLength(1));
  });

  test('ignores replies whose description cannot be used', () async {
    final client = _FakeHttpClient((_) async => _xml('<not-xml'));
    final discovery = UpnpDiscovery(
      search: (_) async => <SsdpResponse>[
        _response('http://192.168.1.5:8200/broken.xml'),
      ],
      client: client,
    );
    addTearDown(discovery.close);

    expect(await discovery.discover(), isEmpty);
  });

  test('an empty search is an empty result, not an error', () async {
    final discovery = UpnpDiscovery(
      search: (_) async => const <SsdpResponse>[],
      client: _FakeHttpClient((_) async => _xml('')),
    );
    addTearDown(discovery.close);

    expect(await discovery.discover(), isEmpty);
  });

  test('a failing SSDP socket is a typed unavailable failure', () async {
    final discovery = UpnpDiscovery(
      search: (_) async => throw const SocketException('no network'),
      client: _FakeHttpClient((_) async => _xml('')),
    );
    addTearDown(discovery.close);

    await expectLater(
      discovery.discover(),
      throwsA(isA<RemoteUnavailableError>()),
    );
  });
}
