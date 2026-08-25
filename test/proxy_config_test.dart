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
}
