// SSDP response parsing and search behaviour for the DLNA renderer module.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/dlna/ssdp_client.dart';

class _FakeRawDatagramSocket implements RawDatagramSocket {
  final StreamController<RawSocketEvent> _events =
      StreamController<RawSocketEvent>();
  final List<Datagram> _incoming = <Datagram>[];
  final List<String> sent = <String>[];
  bool closed = false;

  void queue(String payload, {String from = '192.168.1.20'}) {
    _incoming.add(
      Datagram(
        Uint8List.fromList(utf8.encode(payload)),
        InternetAddress(from),
        SsdpClient.multicastPort,
      ),
    );
  }

  Future<void> dispose() => _events.close();

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _events.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Datagram? receive() => _incoming.isEmpty ? null : _incoming.removeAt(0);

  @override
  int send(List<int> buffer, InternetAddress address, int port) {
    sent.add(utf8.decode(buffer));
    return buffer.length;
  }

  @override
  void close() {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _response({
  required String location,
  String usn = 'uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1',
  String st = 'urn:schemas-upnp-org:device:MediaRenderer:1',
}) {
  return 'HTTP/1.1 200 OK\r\n'
      'CACHE-CONTROL: max-age=1800\r\n'
      'LOCATION: $location\r\n'
      'SERVER: Linux/5.10 UPnP/1.0 Pulsr/1.0\r\n'
      'ST: $st\r\n'
      'USN: $usn\r\n'
      '\r\n';
}

void main() {
  group('SsdpClient.parseResponse', () {
    test('parses CRLF headers case-insensitively', () {
      final response = SsdpClient.parseResponse(
        _response(location: 'http://192.168.1.20:49152/description.xml'),
        sourceAddress: '192.168.1.20',
      );

      expect(response, isNotNull);
      expect(
        response!.location,
        'http://192.168.1.20:49152/description.xml',
      );
      expect(
        response.searchTarget,
        'urn:schemas-upnp-org:device:MediaRenderer:1',
      );
      expect(
        response.usn,
        'uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1',
      );
      expect(response.server, 'Linux/5.10 UPnP/1.0 Pulsr/1.0');
      expect(response.maxAgeSeconds, 1800);
      expect(response.sourceAddress, '192.168.1.20');
    });

    test('accepts LF-only line endings and mixed header case', () {
      const raw = 'HTTP/1.1 200 OK\n'
          'cache-control: max-age = 120\n'
          'location: http://10.0.0.7:8080/desc.xml\n'
          'st: ssdp:all\n'
          'usn: uuid:xyz::urn:schemas-upnp-org:device:MediaRenderer:1\n'
          '\n';

      final response =
          SsdpClient.parseResponse(raw, sourceAddress: '10.0.0.7');

      expect(response, isNotNull);
      expect(response!.location, 'http://10.0.0.7:8080/desc.xml');
      expect(response.maxAgeSeconds, 120);
      expect(response.searchTarget, 'ssdp:all');
    });

    test('returns null without a LOCATION header', () {
      const raw = 'HTTP/1.1 200 OK\r\n'
          'ST: ssdp:all\r\n'
          'USN: uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
          '\r\n';

      expect(
        SsdpClient.parseResponse(raw, sourceAddress: '192.168.1.20'),
        isNull,
      );
    });

    test('returns null for a status line without headers', () {
      expect(
        SsdpClient.parseResponse(
          'HTTP/1.1 200 OK\r\n\r\n',
          sourceAddress: '192.168.1.20',
        ),
        isNull,
      );
    });
  });

  group('SsdpClient.search', () {
    test('sends both M-SEARCH targets and de-duplicates by USN', () async {
      final socket = _FakeRawDatagramSocket();
      final sharedUsn =
          'uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1';
      socket
        ..queue(
          _response(
            location: 'http://192.168.1.20:49152/description.xml',
            usn: sharedUsn,
          ),
        )
        ..queue(
          _response(
            location: 'http://192.168.1.20:49152/description.xml',
            usn: sharedUsn,
          ),
        )
        ..queue(
          _response(
            location: 'http://192.168.1.21:49152/description.xml',
            usn: 'uuid:other::urn:schemas-upnp-org:device:MediaRenderer:1',
          ),
        );

      final client = SsdpClient(socketFactory: () async => socket);
      final results = await client.search(
        timeout: const Duration(milliseconds: 40),
      );

      expect(results, hasLength(2));
      expect(
        results.map((r) => r.location).toSet(),
        <String>{
          'http://192.168.1.20:49152/description.xml',
          'http://192.168.1.21:49152/description.xml',
        },
      );
      expect(socket.sent, hasLength(2));
      expect(socket.sent[0], contains('M-SEARCH * HTTP/1.1'));
      expect(socket.sent[0], contains('ST: ${SsdpClient.searchTargets[0]}'));
      expect(socket.sent[1], contains('ST: ${SsdpClient.searchTargets[1]}'));
      expect(socket.sent[0], contains('HOST: 239.255.255.250:1900'));
      expect(socket.sent[0], contains('MAN: "ssdp:discover"'));
      expect(socket.closed, isTrue);

      await socket.dispose();
    });
  });
}
