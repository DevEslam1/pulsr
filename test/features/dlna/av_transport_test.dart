// AVTransport SOAP exactness and response parsing, including UPnP faults.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/features/dlna/av_transport.dart';

const String _expectedSetUri = '<?xml version="1.0" encoding="utf-8"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
    ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
    '<s:Body>'
    '<u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
    '<InstanceID>0</InstanceID>'
    '<CurrentURI>http://192.168.1.5:5555/media/pulsr-0</CurrentURI>'
    '<CurrentURIMetaData>&lt;DIDL-Lite/&gt;</CurrentURIMetaData>'
    '</u:SetAVTransportURI>'
    '</s:Body>'
    '</s:Envelope>';

const String _expectedPlay = '<?xml version="1.0" encoding="utf-8"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
    ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
    '<s:Body>'
    '<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
    '<InstanceID>0</InstanceID>'
    '<Speed>1</Speed>'
    '</u:Play>'
    '</s:Body>'
    '</s:Envelope>';

const String _expectedSeek = '<?xml version="1.0" encoding="utf-8"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
    ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
    '<s:Body>'
    '<u:Seek xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
    '<InstanceID>0</InstanceID>'
    '<Unit>REL_TIME</Unit>'
    '<Target>00:01:02</Target>'
    '</u:Seek>'
    '</s:Body>'
    '</s:Envelope>';

const String _positionResponse = '<?xml version="1.0"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
    '<s:Body>'
    '<u:GetPositionInfoResponse'
    ' xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
    '<Track>1</Track>'
    '<TrackDuration>0:03:45</TrackDuration>'
    '<TrackURI>http://192.168.1.5:5555/media/pulsr-0</TrackURI>'
    '<RelTime>0:00:12</RelTime>'
    '<CurrentTrackURI>http://192.168.1.5:5555/media/pulsr-0</CurrentTrackURI>'
    '</u:GetPositionInfoResponse>'
    '</s:Body>'
    '</s:Envelope>';

const String _transportResponse = '<?xml version="1.0"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
    '<s:Body>'
    '<u:GetTransportInfoResponse'
    ' xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
    '<CurrentTransportState>PAUSED_PLAYBACK</CurrentTransportState>'
    '<CurrentTransportStatus>OK</CurrentTransportStatus>'
    '</u:GetTransportInfoResponse>'
    '</s:Body>'
    '</s:Envelope>';

const String _faultResponse = '<?xml version="1.0"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
    '<s:Body>'
    '<s:Fault>'
    '<faultcode>s:Client</faultcode>'
    '<faultstring>UPnPError</faultstring>'
    '<detail>'
    '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'
    '<errorCode>714</errorCode>'
    '<errorDescription>Illegal seek target</errorDescription>'
    '</UPnPError>'
    '</detail>'
    '</s:Fault>'
    '</s:Body>'
    '</s:Envelope>';

void main() {
  final controlUrl = Uri.parse('http://192.168.1.5:5555/control/avt');

  group('envelope builders', () {
    test('builds an exact SetAVTransportURI envelope', () {
      expect(
        AvTransportClient.buildSetAvTransportUriEnvelope(
          uri: 'http://192.168.1.5:5555/media/pulsr-0',
          didlMetadata: '<DIDL-Lite/>',
        ),
        _expectedSetUri,
      );
    });

    test('builds an exact Play envelope', () {
      expect(AvTransportClient.buildPlayEnvelope(), _expectedPlay);
    });

    test('builds an exact Seek envelope with a REL_TIME target', () {
      expect(
        AvTransportClient.buildSeekEnvelope(
          position: const Duration(minutes: 1, seconds: 2),
        ),
        _expectedSeek,
      );
    });

    test('builds DIDL-Lite metadata with escaped text fields', () {
      expect(
        AvTransportClient.buildDidlLiteMetadata(
          url: 'http://192.168.1.5:5555/media/pulsr-0',
          title: 'Rock & Roll',
          artist: 'AC/DC',
          album: 'Back in Black',
          mimeType: 'audio/mpeg',
        ),
        '<DIDL-Lite'
        ' xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"'
        ' xmlns:dc="http://purl.org/dc/elements/1.1/"'
        ' xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="0" restricted="1">'
        '<dc:title>Rock &amp; Roll</dc:title>'
        '<dc:creator>AC/DC</dc:creator>'
        '<upnp:artist>AC/DC</upnp:artist>'
        '<upnp:album>Back in Black</upnp:album>'
        '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
        '<res protocolInfo="http-get:*:audio/mpeg:*">'
        'http://192.168.1.5:5555/media/pulsr-0</res>'
        '</item>'
        '</DIDL-Lite>',
      );
    });

    test('adds res@size and res@duration when known and escapes them', () {
      final metadata = AvTransportClient.buildDidlLiteMetadata(
        url: 'http://192.168.1.5:5555/media/abc?x=1&y=2',
        title: 'A & B <C>',
        artist: 'Artist "Q"',
        album: "Album's",
        mimeType: 'audio/flac',
        size: 123456,
        duration: const Duration(minutes: 3, seconds: 45),
        itemId: 'a&b',
      );

      expect(
        metadata,
        contains(
          '<item id="a&amp;b" parentID="0" restricted="1">',
        ),
      );
      expect(metadata, contains('<dc:title>A &amp; B &lt;C&gt;</dc:title>'));
      expect(metadata, contains('<dc:creator>Artist &quot;Q&quot;</dc:creator>'));
      expect(metadata, contains('<upnp:album>Album&apos;s</upnp:album>'));
      expect(
        metadata,
        contains(
          '<res protocolInfo="http-get:*:audio/flac:*" size="123456" '
          'duration="00:03:45">'
          'http://192.168.1.5:5555/media/abc?x=1&amp;y=2</res>',
        ),
      );
    });
  });

  group('AvTransportClient requests', () {
    test('sends exact SOAPACTION, content type and body', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          '<?xml version="1.0"?><s:Envelope'
          ' xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body/>'
          '</s:Envelope>',
          200,
        );
      });
      final av = AvTransportClient(controlUrl, client: client);
      addTearDown(av.close);

      await av.setAvTransportUri(
        'http://192.168.1.5:5555/media/pulsr-0',
        '<DIDL-Lite/>',
      );
      await av.play();

      expect(requests, hasLength(2));
      final setUri = requests[0];
      expect(setUri.method, 'POST');
      expect(setUri.url, controlUrl);
      expect(
        setUri.headers['SOAPACTION'],
        '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
      );
      expect(setUri.headers['Content-Type'], 'text/xml; charset="utf-8"');
      expect(setUri.body, _expectedSetUri);

      final play = requests[1];
      expect(
        play.headers['SOAPACTION'],
        '"urn:schemas-upnp-org:service:AVTransport:1#Play"',
      );
      expect(play.body, _expectedPlay);
    });
  });

  group('AvTransportClient responses', () {
    test('parses position, duration and current track URI', () async {
      final av = AvTransportClient(
        controlUrl,
        client: MockClient((_) async => http.Response(_positionResponse, 200)),
      );
      addTearDown(av.close);

      final info = await av.getPositionInfo();

      expect(info.position, const Duration(seconds: 12));
      expect(info.trackDuration, const Duration(minutes: 3, seconds: 45));
      expect(
        info.trackUri,
        'http://192.168.1.5:5555/media/pulsr-0',
      );
    });

    test('parses CurrentTransportState', () async {
      final av = AvTransportClient(
        controlUrl,
        client: MockClient((_) async => http.Response(_transportResponse, 200)),
      );
      addTearDown(av.close);

      final info = await av.getTransportInfo();

      expect(info.state, TransportState.paused);
      expect(info.state.isPaused, isTrue);
    });

    test('maps a UPnPError fault to a typed error with its code', () async {
      final av = AvTransportClient(
        controlUrl,
        client: MockClient((_) async => http.Response(_faultResponse, 200)),
      );
      addTearDown(av.close);

      await expectLater(
        av.seek(const Duration(seconds: 5)),
        throwsA(
          isA<UpnpActionError>()
              .having((error) => error.errorCode, 'errorCode', 714)
              .having((error) => error.action, 'action', 'Seek')
              .having(
                (error) => error.errorDescription,
                'errorDescription',
                'Illegal seek target',
              ),
        ),
      );
    });

    test('fails on an HTTP status >= 400 with a malformed body', () async {
      final av = AvTransportClient(
        controlUrl,
        client: MockClient(
          (_) async => http.Response('Internal Server Error', 500),
        ),
      );
      addTearDown(av.close);

      await expectLater(
        av.play(),
        throwsA(
          isA<UpnpActionError>()
              .having((error) => error.code, 'code', 'DLNA_HTTP_500')
              .having((error) => error.action, 'action', 'Play'),
        ),
      );
    });

    test('does not treat the word Fault in a normal response as a fault',
        () async {
      const body = '<?xml version="1.0"?>'
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
          '<s:Body><u:GetPositionInfoResponse>'
          '<RelTime>0:00:07</RelTime>'
          '<CurrentTrackURI>http://host/Fault</CurrentTrackURI>'
          '</u:GetPositionInfoResponse></s:Body></s:Envelope>';
      final av = AvTransportClient(
        controlUrl,
        client: MockClient((_) async => http.Response(body, 200)),
      );
      addTearDown(av.close);

      final info = await av.getPositionInfo();

      expect(info.position, const Duration(seconds: 7));
      expect(info.trackUri, 'http://host/Fault');
    });

    test('recognizes a namespaced SOAP Fault even on HTTP 500', () async {
      final av = AvTransportClient(
        controlUrl,
        client: MockClient((_) async => http.Response(_faultResponse, 500)),
      );
      addTearDown(av.close);

      await expectLater(
        av.play(),
        throwsA(
          isA<UpnpActionError>()
              .having((error) => error.errorCode, 'errorCode', 714)
              .having((error) => error.code, 'code', 'DLNA_UPNP_ERROR_714'),
        ),
      );
    });
  });

  group('duration helpers', () {
    test('parses H:MM:SS, HH:MM:SS and fractional seconds', () {
      expect(
        AvTransportClient.parseUpnpDuration('0:03:45'),
        const Duration(minutes: 3, seconds: 45),
      );
      expect(
        AvTransportClient.parseUpnpDuration('01:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      expect(
        AvTransportClient.parseUpnpDuration('0:00:12.500'),
        const Duration(seconds: 12),
      );
      expect(
        AvTransportClient.parseUpnpDuration('02:30'),
        const Duration(minutes: 2, seconds: 30),
      );
    });

    test('returns null for placeholders and malformed values', () {
      expect(AvTransportClient.parseUpnpDuration('NOT_IMPLEMENTED'), isNull);
      expect(AvTransportClient.parseUpnpDuration(''), isNull);
      expect(AvTransportClient.parseUpnpDuration(null), isNull);
      expect(AvTransportClient.parseUpnpDuration('abc'), isNull);
    });

    test('formats negative durations as zero', () {
      expect(
        AvTransportClient.formatUpnpDuration(const Duration(seconds: -1)),
        '00:00:00',
      );
    });
  });
}
