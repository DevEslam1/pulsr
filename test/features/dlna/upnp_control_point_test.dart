// Unit tests for UpnpControlPoint: setAvTransportUri, setNextAvTransportUri,
// play, pause, stop, seek, getPositionInfo, getTransportInfo, next, previous.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/features/dlna/av_transport.dart';
import 'package:pulsr/features/dlna/upnp_control_point.dart';
import 'package:pulsr/features/dlna/upnp_device.dart';

void main() {
  final device = UpnpDeviceDescription(
    friendlyName: 'Test Speaker',
    location: Uri.parse('http://192.168.1.100:8080/desc.xml'),
    avTransportControlUrl: Uri.parse('http://192.168.1.100:8080/control/avt'),
  );

  group('UpnpControlPoint actions', () {
    test('executes setAvTransportUri and play', () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        final action = (request.headers['SOAPACTION'] ?? '').replaceAll('"', '').split('#').last;
        requests.add(action);
        return http.Response(
          '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:${action}Response xmlns:u="${AvTransportClient.serviceType}"/></s:Body></s:Envelope>',
          200,
        );
      });

      final cp = UpnpControlPoint(client: client);
      addTearDown(cp.close);

      await cp.setAvTransportUri(device, 'http://192.168.1.5:8000/track1.mp3');
      await cp.play(device);

      expect(requests, ['SetAVTransportURI', 'Play']);
    });

    test('executes queue (setNextAvTransportUri), next and previous', () async {
      final requests = <String>[];
      final bodies = <String>[];
      final client = MockClient((request) async {
        final action = (request.headers['SOAPACTION'] ?? '').replaceAll('"', '').split('#').last;
        requests.add(action);
        bodies.add(request.body);
        return http.Response(
          '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:${action}Response xmlns:u="${AvTransportClient.serviceType}"/></s:Body></s:Envelope>',
          200,
        );
      });

      final cp = UpnpControlPoint(client: client);
      addTearDown(cp.close);

      await cp.setNextAvTransportUri(device, 'http://192.168.1.5:8000/track2.mp3');
      await cp.next(device);
      await cp.previous(device);

      expect(requests, ['SetNextAVTransportURI', 'Next', 'Previous']);
      expect(bodies[0], contains('SetNextAVTransportURI'));
      expect(bodies[0], contains('http://192.168.1.5:8000/track2.mp3'));
      expect(bodies[1], contains('Next'));
      expect(bodies[2], contains('Previous'));
    });

    test('executes pause, stop and seek', () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        final action = (request.headers['SOAPACTION'] ?? '').replaceAll('"', '').split('#').last;
        requests.add(action);
        return http.Response(
          '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:${action}Response xmlns:u="${AvTransportClient.serviceType}"/></s:Body></s:Envelope>',
          200,
        );
      });

      final cp = UpnpControlPoint(client: client);
      addTearDown(cp.close);

      await cp.pause(device);
      await cp.seek(device, const Duration(seconds: 45));
      await cp.stop(device);

      expect(requests, ['Pause', 'Seek', 'Stop']);
    });

    test('reads position and transport info', () async {
      final client = MockClient((request) async {
        final action = (request.headers['SOAPACTION'] ?? '').replaceAll('"', '').split('#').last;
        if (action == 'GetPositionInfo') {
          return http.Response(
            '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
            '<u:GetPositionInfoResponse xmlns:u="${AvTransportClient.serviceType}">'
            '<TrackDuration>0:04:15</TrackDuration>'
            '<RelTime>0:01:23</RelTime>'
            '<CurrentTrackURI>http://example.com/audio.flac</CurrentTrackURI>'
            '</u:GetPositionInfoResponse></s:Body></s:Envelope>',
            200,
          );
        } else if (action == 'GetTransportInfo') {
          return http.Response(
            '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
            '<u:GetTransportInfoResponse xmlns:u="${AvTransportClient.serviceType}">'
            '<CurrentTransportState>PLAYING</CurrentTransportState>'
            '</u:GetTransportInfoResponse></s:Body></s:Envelope>',
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final cp = UpnpControlPoint(client: client);
      addTearDown(cp.close);

      final pos = await cp.getPositionInfo(device);
      expect(pos.trackDuration, const Duration(minutes: 4, seconds: 15));
      expect(pos.position, const Duration(minutes: 1, seconds: 23));
      expect(pos.trackUri, 'http://example.com/audio.flac');

      final transport = await cp.getTransportInfo(device);
      expect(transport.state, TransportState.playing);
    });
  });
}
