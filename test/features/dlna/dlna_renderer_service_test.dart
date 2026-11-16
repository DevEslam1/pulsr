// End-to-end orchestration: fake SSDP replies, mocked SOAP endpoint, and the
// real loopback media server that a renderer would fetch from.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/features/dlna/av_transport.dart';
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
  _FakeSsdpClient(this.responses);

  final List<SsdpResponse> responses;

  @override
  Future<List<SsdpResponse>> search({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    return responses;
  }
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
  late List<int> fileBytes;
  late List<http.Request> requests;
  late String transportState;
  late DlnaRendererService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_dlna_service_');
    fileBytes = List<int>.generate(2048, (index) => index % 253);
    mediaFile = File('${tempDir.path}${Platform.pathSeparator}song.mp3');
    await mediaFile.writeAsBytes(fileBytes);
    requests = <http.Request>[];
    transportState = 'STOPPED';
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  DlnaRendererService buildService({
    Duration pollInterval = const Duration(minutes: 1),
  }) {
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET' &&
          request.url.path.endsWith('description.xml')) {
        return http.Response(_descriptionXml, 200);
      }
      switch (_actionOf(request)) {
        case 'GetTransportInfo':
          return http.Response(
            _soap(
              '<u:GetTransportInfoResponse'
              ' xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
              '<CurrentTransportState>$transportState</CurrentTransportState>'
              '</u:GetTransportInfoResponse>',
            ),
            200,
          );
        case 'GetPositionInfo':
          return http.Response(
            _soap(
              '<u:GetPositionInfoResponse'
              ' xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
              '<TrackDuration>0:03:00</TrackDuration>'
              '<RelTime>0:00:12</RelTime>'
              '<CurrentTrackURI>http://192.168.1.5/media/token</CurrentTrackURI>'
              '</u:GetPositionInfoResponse>',
            ),
            200,
          );
        case 'Play':
          transportState = 'PLAYING';
          return http.Response(_soap(''), 200);
        case 'Pause':
          transportState = 'PAUSED_PLAYBACK';
          return http.Response(_soap(''), 200);
        case 'Stop':
          transportState = 'STOPPED';
          return http.Response(_soap(''), 200);
        case 'SetAVTransportURI':
        case 'Seek':
          return http.Response(_soap(''), 200);
        default:
          return http.Response('unsupported action', 500);
      }
    });

    return DlnaRendererService(
      ssdpClient: _FakeSsdpClient(<SsdpResponse>[
        const SsdpResponse(
          location: 'http://192.168.1.5:5555/description.xml',
          searchTarget: 'urn:schemas-upnp-org:device:MediaRenderer:1',
          usn: 'uuid:mock-renderer::urn:schemas-upnp-org:device:MediaRenderer:1',
          server: 'Test/1.0 UPnP/1.1',
          sourceAddress: '192.168.1.5',
          maxAgeSeconds: 1800,
        ),
      ]),
      httpClient: client,
      pollInterval: pollInterval,
      discoveryTimeout: const Duration(milliseconds: 10),
    );
  }

  test('discovers and selects a renderer', () async {
    service = buildService();
    addTearDown(service.dispose);

    await service.discover();
    expect(service.devices, hasLength(1));
    expect(service.devices.single.friendlyName, 'Mock Renderer');
    expect(service.state, DlnaState.idle);

    await service.select(service.devices.single);
    expect(service.selectedDevice, isNotNull);
    expect(service.state, DlnaState.stopped);
    expect(service.lastError, isNull);
  });

  test('playFile serves the file over HTTP and sends SetAVTransportURI + Play',
      () async {
    service = buildService(pollInterval: const Duration(minutes: 1));
    addTearDown(service.dispose);
    await service.discover();
    await service.select(service.devices.single);

    await service.playFile(
      mediaFile.path,
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
    );

    expect(service.state, DlnaState.playing);
    expect(service.nowPlayingTitle, 'Song');
    expect(service.mediaServer.isRunning, isTrue);

    final setUri = requests.firstWhere(
      (request) => _actionOf(request) == 'SetAVTransportURI',
    );
    final mediaUri = AvTransportClient.elementText(
      setUri.body,
      'CurrentURI',
    );
    expect(mediaUri, isNotNull);
    final parsed = Uri.parse(mediaUri!);
    expect(parsed.scheme, 'http');
    expect(parsed.pathSegments.first, 'media');
    expect(parsed.port, service.mediaServer.port);

    final metadata = AvTransportClient.elementText(
      setUri.body,
      'CurrentURIMetaData',
    );
    expect(metadata, contains('<dc:title>Song</dc:title>'));
    expect(metadata, contains('<upnp:artist>Artist</upnp:artist>'));
    expect(metadata, contains('<upnp:album>Album</upnp:album>'));

    final actions = requests.map(_actionOf).where((action) => action.isNotEmpty);
    expect(
      actions.toList().sublist(actions.toList().indexOf('SetAVTransportURI')),
      containsAllInOrder(<String>['SetAVTransportURI', 'Play']),
    );

    final client = HttpClient();
    final fetch = await client.getUrl(parsed.replace(host: '127.0.0.1'));
    final response = await fetch.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    client.close(force: true);
    expect(response.statusCode, 200);
    expect(body, fileBytes);
  });

  test('pause, resume, seek and stop drive the renderer', () async {
    service = buildService();
    addTearDown(service.dispose);
    await service.discover();
    await service.select(service.devices.single);
    await service.playFile(mediaFile.path, title: 'Song');

    await service.pause();
    expect(service.state, DlnaState.paused);

    await service.resume();
    expect(service.state, DlnaState.playing);

    await service.seek(const Duration(minutes: 1));
    expect(service.position, const Duration(minutes: 1));

    await service.stop();
    expect(service.state, DlnaState.stopped);
    expect(service.nowPlayingTitle, isNull);

    final actions = requests.map(_actionOf).toList();
    expect(actions, containsAll(<String>['Pause', 'Play', 'Seek', 'Stop']));
  });

  test('polls the renderer for position while playing', () async {
    service = buildService(pollInterval: const Duration(milliseconds: 40));
    addTearDown(service.dispose);
    await service.discover();
    await service.select(service.devices.single);
    await service.playFile(mediaFile.path, title: 'Song');

    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(service.position, const Duration(seconds: 12));
    expect(service.duration, const Duration(minutes: 3));
    expect(service.state, DlnaState.playing);
  });

  test('playFile without a selected device reports a typed error', () async {
    service = buildService();
    addTearDown(service.dispose);

    await service.playFile(mediaFile.path);

    expect(service.state, DlnaState.error);
    expect(service.lastError?.code, 'DLNA_NO_DEVICE');
  });

  test('dispose stops the media server', () async {
    service = buildService();
    await service.discover();
    await service.select(service.devices.single);
    await service.playFile(mediaFile.path, title: 'Song');
    expect(service.mediaServer.isRunning, isTrue);

    service.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(service.mediaServer.isRunning, isFalse);
  });
}
