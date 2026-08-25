// test/proxy_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/network/proxy_config.dart';

void main() {
  group('ProxyConfig', () {
    test('default configuration is disabled and points to DIRECT', () {
      const config = ProxyConfig();
      expect(config.enabled, false);
      expect(config.isValid, false);
      expect(config.toFindProxyString(Uri.parse('https://music.youtube.com')), 'DIRECT');
    });

    test('valid HTTP proxy formats properly for HttpClient.findProxy', () {
      const config = ProxyConfig(
        enabled: true,
        type: AppProxyType.http,
        host: '127.0.0.1',
        port: 8080,
      );
      expect(config.isValid, true);
      expect(
        config.toFindProxyString(Uri.parse('https://music.youtube.com/search')),
        'PROXY 127.0.0.1:8080; DIRECT',
      );
    });

    test('valid SOCKS5 proxy formats properly for HttpClient.findProxy', () {
      const config = ProxyConfig(
        enabled: true,
        type: AppProxyType.socks5,
        host: '192.168.1.100',
        port: 1080,
      );
      expect(config.isValid, true);
      expect(
        config.toFindProxyString(Uri.parse('https://music.youtube.com/search')),
        'SOCKS5 192.168.1.100:1080; SOCKS 192.168.1.100:1080; DIRECT',
      );
    });

    test('bypassed hosts connect directly', () {
      const config = ProxyConfig(
        enabled: true,
        type: AppProxyType.http,
        host: '127.0.0.1',
        port: 8080,
        bypassHosts: 'localhost, 127.0.0.1, *.internal.net',
      );

      expect(config.isBypassed(Uri.parse('http://localhost:3000')), true);
      expect(config.isBypassed(Uri.parse('http://127.0.0.1:8000')), true);
      expect(config.isBypassed(Uri.parse('https://api.internal.net/v1')), true);
      expect(config.isBypassed(Uri.parse('https://music.youtube.com')), false);

      expect(config.toFindProxyString(Uri.parse('http://localhost:3000')), 'DIRECT');
      expect(config.toFindProxyString(Uri.parse('https://music.youtube.com')), 'PROXY 127.0.0.1:8080; DIRECT');
    });

    test('serialization to and from Map preserves all fields', () {
      const original = ProxyConfig(
        enabled: true,
        type: AppProxyType.socks5,
        host: 'proxy.company.org',
        port: 9050,
        username: 'user1',
        password: 'secretPassword',
        bypassHosts: 'localhost, internal.local',
      );

      final map = original.toMap();
      final reconstructed = ProxyConfig.fromMap(map);

      expect(reconstructed.enabled, original.enabled);
      expect(reconstructed.type, original.type);
      expect(reconstructed.host, original.host);
      expect(reconstructed.port, original.port);
      expect(reconstructed.username, original.username);
      expect(reconstructed.password, original.password);
      expect(reconstructed.bypassHosts, original.bypassHosts);
      expect(reconstructed.hasAuth, true);
    });
  });

  group('ProxyEntry', () {
    test('parses IP:PORT:USER:PASS format properly', () {
      final entry = ProxyEntry.parse('31.59.20.176:6754:qmyizdto:n5fui7pyec1q');
      expect(entry, isNotNull);
      expect(entry!.host, '31.59.20.176');
      expect(entry.port, 6754);
      expect(entry.username, 'qmyizdto');
      expect(entry.password, 'n5fui7pyec1q');
      expect(entry.hasAuth, true);
      expect(entry.isValid, true);
    });

    test('parses IP:PORT format', () {
      final entry = ProxyEntry.parse('45.38.107.97:6014');
      expect(entry, isNotNull);
      expect(entry!.host, '45.38.107.97');
      expect(entry.port, 6014);
      expect(entry.username, '');
      expect(entry.password, '');
      expect(entry.hasAuth, false);
      expect(entry.isValid, true);
    });

    test('parses URL format with socks5 scheme', () {
      final entry = ProxyEntry.parse('socks5://qmyizdto:secret123@198.105.121.200:6462');
      expect(entry, isNotNull);
      expect(entry!.host, '198.105.121.200');
      expect(entry.port, 6462);
      expect(entry.username, 'qmyizdto');
      expect(entry.password, 'secret123');
      expect(entry.type, AppProxyType.socks5);
    });

    test('parseList handles multi-line proxy text blocks with comments and duplicates', () {
      const rawText = '''
# Proxy list comment
31.59.20.176:6754:qmyizdto:n5fui7pyec1q
45.38.107.97:6014:qmyizdto:n5fui7pyec1q
// duplicate test
31.59.20.176:6754:qmyizdto:n5fui7pyec1q
198.105.121.200:6462:qmyizdto:n5fui7pyec1q
''';
      final list = ProxyEntry.parseList(rawText);
      expect(list.length, 3);
      expect(list[0].host, '31.59.20.176');
      expect(list[1].host, '45.38.107.97');
      expect(list[2].host, '198.105.121.200');
    });

    test('serialization to and from Map preserves all fields', () {
      const entry = ProxyEntry(
        id: 'p1',
        host: '64.137.96.74',
        port: 6641,
        username: 'user1',
        password: 'pwd',
        type: AppProxyType.socks5,
        label: 'US Fast Proxy',
        latencyMs: 120,
        isWorking: true,
      );

      final map = entry.toMap();
      final restored = ProxyEntry.fromMap(map);

      expect(restored.id, 'p1');
      expect(restored.host, '64.137.96.74');
      expect(restored.port, 6641);
      expect(restored.username, 'user1');
      expect(restored.password, 'pwd');
      expect(restored.type, AppProxyType.socks5);
      expect(restored.label, 'US Fast Proxy');
      expect(restored.latencyMs, 120);
      expect(restored.isWorking, true);
    });
  });
}
