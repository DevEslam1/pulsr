// Regression test for P1-2.1: a renderer that stops answering must not leave
// the UI frozen on "Playing". After three failures the service exposes a stale
// state + error, and retrying resumes polling.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/features/dlna/dlna_renderer_service.dart';
import 'package:pulsr/features/dlna/ssdp_client.dart';

const String _descriptionXml = '<?xml version="1.0"?><root><device>'
    '<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>'
    '<friendlyName>Mock Renderer</friendlyName>'
    '<modelName>Pulsr Test</modelName>'
    '<UDN>uuid:mock-renderer</UDN>'
    '<serviceList><service>'
    '<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>'
    '<serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>'
    '<controlURL>control/avt</controlURL>'
    '</service></serviceList>'
    '</device></root>';

class _FakeSsdpClient extends SsdpClient {
  @override
  Future<List<SsdpResponse>> search({
    Duration timeout = const Duration(seconds: 3),
  }) async =>
      <SsdpResponse>[
        const SsdpResponse(
          location: 'http://192.168.1.5:5555/description.xml',
          searchTarget: 'urn:schemas-upnp-org:device:MediaRenderer:1',
          usn:
              'uuid:mock-renderer::urn:schemas-upnp-org:device:MediaRenderer:1',
          server: 'Test/1.0 UPnP/1.1',
          sourceAddress: '192.168.1.5',
          maxAgeSeconds: 1800,
        ),
      ];
}

String _soap(String body) => '<?xml version="1.0"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
    '<s:Body>$body</s:Body></s:Envelope>';

String _actionOf(http.Request request) {
  final header = request.headers['SOAPACTION'] ?? '';
  return header.replaceAll('"', '').split('#').last;
}

void main() {
  late Directory tempDir;
  late File mediaFile;
  late String transportState;
  late double relTimeSeconds;
  late bool failPolls;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_dlna_stale_');
    mediaFile = File('${tempDir.path}${Platform.pathSeparator}song.mp3');
    await mediaFile
        .writeAsBytes(List<int>.generate(1024, (index) => index % 251));
    transportState = 'STOPPED';
    relTimeSeconds = 1;
    failPolls = false;
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  DlnaRendererService buildService() {
    final client = MockClient((http.Request request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('description.xml')) {
        return http.Response(_descriptionXml, 200);
      }
      final action = _actionOf(request);
      if (failPolls &&
          (action == 'GetTransportInfo' || action == 'GetPositionInfo')) {
        return http.Response('renderer unavailable', 500);
      }
      switch (action) {
        case 'GetTransportInfo':
          return http.Response(
            _soap('<u:GetTransportInfoResponse'
                ' xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
                '<CurrentTransportState>$transportState</CurrentTransportState>'
                '</u:GetTransportInfoResponse>'),
            200,
          );
        case 'GetPositionInfo':
          final formatted =
              '0:00:${relTimeSeconds.toInt().toString().padLeft(2, '0')}';
          return http.Response(
            _soap('<u:GetPositionInfoResponse'
                ' xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
                '<TrackDuration>0:03:00</TrackDuration>'
                '<RelTime>$formatted</RelTime>'
                '</u:GetPositionInfoResponse>'),
            200,
          );
        case 'Play':
          transportState = 'PLAYING';
          return http.Response(_soap(''), 200);
        case 'SetAVTransportURI':
          return http.Response(_soap(''), 200);
        default:
          return http.Response(_soap(''), 200);
      }
    });

    return DlnaRendererService(
      ssdpClient: _FakeSsdpClient(),
      httpClient: client,
      pollInterval: const Duration(milliseconds: 25),
      discoveryTimeout: const Duration(milliseconds: 10),
      localAddressResolver: (String host, int port) async =>
          InternetAddress.loopbackIPv4,
    );
  }

  test('three failed polls expose a stale error and retry recovers', () async {
    final service = buildService();
    addTearDown(service.dispose);
    await service.discover();
    await service.select(service.devices.single);
    await service.playFile(mediaFile.path, title: 'Song');

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(service.isPollStale, isFalse);

    failPolls = true;
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(service.isPollStale, isTrue,
        reason: 'the loop must stop instead of freezing on Playing');
    expect(service.lastError?.code, 'dlna-poll-stale');

    // The renderer answers again: retry restarts the loop and clears the error.
    failPolls = false;
    relTimeSeconds = 33;
    expect(await service.retryPolling(), isTrue);

    expect(service.isPollStale, isFalse);
    expect(service.lastError, isNull);
    expect(service.position, const Duration(seconds: 33));
  });
}
