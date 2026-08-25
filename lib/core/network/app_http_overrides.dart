// lib/core/network/app_http_overrides.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'proxy_config.dart';

/// Global [HttpOverrides] that intercepts all Dart [HttpClient] instances and
/// applies the active proxy settings and authentication credentials.
class AppHttpOverrides extends HttpOverrides {
  AppHttpOverrides._();

  static final AppHttpOverrides instance = AppHttpOverrides._();

  ProxyConfig _config = const ProxyConfig();

  ProxyConfig get currentConfig => _config;

  void update(ProxyConfig newConfig) {
    _config = newConfig;
    debugPrint(
      '[AppHttpOverrides] Proxy updated: enabled=${newConfig.enabled}, '
      'type=${newConfig.type.name}, host=${newConfig.host}:${newConfig.port}',
    );
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    
    // Dynamic findProxy callback
    client.findProxy = (uri) {
      return _config.toFindProxyString(uri);
    };

    // Proxy authentication credentials if configured
    if (_config.enabled && _config.hasAuth) {
      client.authenticateProxy = (host, port, scheme, realm) async {
        if (_config.hasAuth) {
          client.addProxyCredentials(
            host,
            port,
            realm ?? '',
            HttpClientBasicCredentials(_config.username, _config.password),
          );
          return true;
        }
        return false;
      };
    }

    // Default resilient timeouts
    client.connectionTimeout = const Duration(seconds: 15);
    client.idleTimeout = const Duration(seconds: 90);

    return client;
  }

  /// Probes connectivity through the currently configured proxy.
  /// Returns a record with `(success, latencyMs, errorMessage)`.
  Future<({bool success, int latencyMs, String? error})> testConnection({
    ProxyConfig? configToTest,
    String testUrl = 'https://music.youtube.com/generate_204',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final testConfig = configToTest ?? _config;
    final stopwatch = Stopwatch()..start();
    HttpClient? testClient;

    try {
      final uri = Uri.parse(testUrl);
      testClient = HttpClient()
        ..connectionTimeout = timeout
        ..idleTimeout = timeout;

      testClient.findProxy = (u) => testConfig.toFindProxyString(u);

      if (testConfig.enabled && testConfig.hasAuth) {
        testClient.authenticateProxy = (host, port, scheme, realm) async {
          testClient?.addProxyCredentials(
            host,
            port,
            realm ?? '',
            HttpClientBasicCredentials(testConfig.username, testConfig.password),
          );
          return true;
        };
      }

      final request = await testClient.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      stopwatch.stop();

      // Drain response bytes to free connection
      await response.drain<void>();

      if (response.statusCode >= 200 && response.statusCode < 400) {
        return (
          success: true,
          latencyMs: stopwatch.elapsedMilliseconds,
          error: null,
        );
      } else {
        return (
          success: false,
          latencyMs: stopwatch.elapsedMilliseconds,
          error: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      stopwatch.stop();
      return (
        success: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: e.toString().replaceAll('SocketException: ', '').replaceAll('HttpException: ', ''),
      );
    } finally {
      testClient?.close(force: true);
    }
  }
}
