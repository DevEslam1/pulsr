// test/core/network/app_http_overrides_test.dart
//
// testConnection()'s response classification: proxy auth rejections must fail
// before the YouTube 4xx-reachability rule, or wrong proxy credentials report
// "working".
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/network/app_http_overrides.dart';
import 'package:pulsr/core/network/proxy_config.dart';

void main() {
  final youtubeUri = Uri.parse('https://music.youtube.com/');
  final googleVideoUri = Uri.parse('https://rr1---sn-abc.googlevideo.com/');
  final otherUri = Uri.parse('https://example.com/');

  group('AppHttpOverrides.evaluateResponse', () {
    test('2xx/3xx are reachable', () {
      expect(AppHttpOverrides.evaluateResponse(200, 'OK', youtubeUri).success,
          isTrue);
      expect(
          AppHttpOverrides.evaluateResponse(204, 'No Content', youtubeUri)
              .success,
          isTrue);
      expect(AppHttpOverrides.evaluateResponse(302, 'Found', otherUri).success,
          isTrue);
    });

    test('407 proxy authentication fails even on a YouTube host', () {
      final result = AppHttpOverrides.evaluateResponse(
          407, 'Proxy Authentication Required', youtubeUri);

      expect(result.success, isFalse);
      expect(result.error, contains('407'));
    });

    test('401 authentication fails before the 4xx reachability rule', () {
      final result =
          AppHttpOverrides.evaluateResponse(401, 'Unauthorized', youtubeUri);

      expect(result.success, isFalse);
      expect(result.error, contains('401'));
    });

    test('403/404 from YouTube still count as proxy-reachable', () {
      expect(
          AppHttpOverrides.evaluateResponse(403, 'Forbidden', youtubeUri)
              .success,
          isTrue);
      expect(
          AppHttpOverrides.evaluateResponse(404, 'Not Found', youtubeUri)
              .success,
          isTrue);
      expect(
          AppHttpOverrides.evaluateResponse(404, 'Not Found', googleVideoUri)
              .success,
          isTrue);
    });

    test('4xx from a non-YouTube host fails', () {
      final result =
          AppHttpOverrides.evaluateResponse(403, 'Forbidden', otherUri);

      expect(result.success, isFalse);
      expect(result.error, contains('403'));
    });

    test('5xx fails on every host', () {
      expect(
          AppHttpOverrides.evaluateResponse(500, 'Server Error', youtubeUri)
              .success,
          isFalse);
      expect(
          AppHttpOverrides.evaluateResponse(503, 'Unavailable', otherUri)
              .success,
          isFalse);
    });

    test('an empty reason phrase still yields a usable error', () {
      final result = AppHttpOverrides.evaluateResponse(407, '', youtubeUri);

      expect(result.success, isFalse);
      expect(result.error, isNotEmpty);
    });
  });

  group('AppHttpOverrides SOCKS5 connectivity testing', () {
    test(
        'unreachable SOCKS5 proxy fails with error instead of false-positive success',
        () async {
      // Pick a port that is not listening on localhost
      final config = const ProxyConfig(
        enabled: true,
        type: AppProxyType.socks5,
        host: '127.0.0.1',
        port: 59999,
      );

      final result = await AppHttpOverrides.instance.testConnection(
        configToTest: config,
        timeout: const Duration(milliseconds: 500),
      );

      expect(result.success, isFalse);
      expect(result.error, isNotNull);
    });

    test('valid SOCKS5 proxy handshake succeeds via testSocks5ViaSocket',
        () async {
      // Spin up a minimal loopback SOCKS5 server
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((client) {
        client.listen((data) {
          // Greeting [0x05, 0x01, 0x00] -> reply [0x05, 0x00] (no auth)
          if (data.isNotEmpty && data[0] == 0x05 && data.length <= 4) {
            client.add([0x05, 0x00]);
          } else if (data.isNotEmpty && data[0] == 0x05 && data[1] == 0x01) {
            // Connect request -> reply success [0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 1, 1]
            client.add([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 80]);
          }
        });
      });

      try {
        final config = ProxyConfig(
          enabled: true,
          type: AppProxyType.socks5,
          host: '127.0.0.1',
          port: server.port,
        );

        final result = await AppHttpOverrides.testSocks5ViaSocket(
          testConfig: config,
          targetUri: Uri.parse('https://music.youtube.com/'),
          timeout: const Duration(seconds: 2),
        );

        expect(result.success, isTrue);
        expect(result.error, isNull);
      } finally {
        await server.close();
      }
    });

    test(
        'Dart HttpClient tunnels HTTP requests through local SOCKS5 loopback bridge',
        () async {
      var socksConnectReceived = false;
      final socksServer =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      socksServer.listen((client) {
        var stage = 0;
        client.listen((data) {
          if (stage == 0 && data.isNotEmpty && data[0] == 0x05) {
            stage = 1;
            client.add([0x05, 0x00]);
          } else if (stage == 1 &&
              data.isNotEmpty &&
              data[0] == 0x05 &&
              data[1] == 0x01) {
            stage = 2;
            socksConnectReceived = true;
            client.add([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 80]);
          } else if (stage == 2) {
            final reqText = latin1.decode(data);
            if (reqText.contains('GET /test-socks5 HTTP/1.1')) {
              client.add(ascii.encode(
                'HTTP/1.1 200 OK\r\n'
                'Content-Length: 13\r\n'
                'Connection: close\r\n\r\n'
                'socks5-bridge',
              ));
              client.close();
            }
          }
        });
      });

      final previousOverrides = HttpOverrides.current;
      try {
        final config = ProxyConfig(
          enabled: true,
          type: AppProxyType.socks5,
          host: '127.0.0.1',
          port: socksServer.port,
        );
        AppHttpOverrides.instance.update(config);
        final bridgePort = await AppHttpOverrides.instance.ensureSocks5Bridge();
        expect(bridgePort, isNotNull);

        final client = AppHttpOverrides.instance.createHttpClient(null);
        final req =
            await client.getUrl(Uri.parse('http://example.com/test-socks5'));
        final res = await req.close();
        final body = await utf8.decoder.bind(res).join();
        client.close(force: true);

        expect(socksConnectReceived, isTrue);
        expect(res.statusCode, 200);
        expect(body, 'socks5-bridge');
      } finally {
        AppHttpOverrides.instance.update(const ProxyConfig());
        await AppHttpOverrides.instance.stopSocks5Bridge();
        HttpOverrides.global = previousOverrides;
        await socksServer.close();
      }
    });
  });
}
