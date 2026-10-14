// lib/core/network/app_http_overrides.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/channels.dart';
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
    // Log the resolved findProxy string rather than the raw host:port, and
    // redact the endpoint inside it: the address may reveal a private/VPN exit
    // or a credentialed proxy and must not reach the logs verbatim.
    final resolved =
        newConfig.toFindProxyString(Uri.parse('https://example.com'));
    debugPrint(
      '[AppHttpOverrides] Proxy updated: enabled=${newConfig.enabled}, '
      'type=${newConfig.type.name}, resolved=${_redactProxyAddress(resolved)}',
    );
  }

  /// Replaces the `PROXY <host>:<port>` token with a redacted placeholder so
  /// the configured proxy endpoint never reaches the logs.
  static String _redactProxyAddress(String findProxy) =>
      findProxy.replaceAll(RegExp(r'PROXY\s+[^;\s]+'), 'PROXY [REDACTED]');

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    // Dynamic findProxy callback — when no custom proxy is active, fall
    // back to the platform's proxy resolution (covers VPNs that expose
    // themselves as a local HTTP/SOCKS proxy). Returning a hard-coded
    // 'DIRECT' bypassed the VPN and made Pulsr fail while the official
    // YouTube Music app (which uses the system selector) kept working.
    client.findProxy = (uri) {
      if (_config.enabled && _config.isValid && !_config.isBypassed(uri)) {
        return _config.toFindProxyString(uri);
      }
      // Delegate to Dart's environment proxy (http_proxy/https_proxy) and
      // ultimately to DIRECT if none is set — DIRECT still traverses a
      // TUN-based VPN at the IP layer.
      return HttpClient.findProxyFromEnvironment(
        uri,
        environment: Platform.environment,
      );
    };

    // Dynamic proxy authentication credentials
    client.authenticateProxy = (host, port, scheme, realm) async {
      if (_config.enabled && _config.hasAuth) {
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

    // Default resilient timeouts
    client.connectionTimeout = const Duration(seconds: 15);
    client.idleTimeout = const Duration(seconds: 90);

    return client;
  }

  /// Classifies a probe response into the `(success, error)` pair returned by
  /// [testConnection]. Pure so the auth-failure precedence is unit-testable.
  @visibleForTesting
  static ({bool success, String? error}) evaluateResponse(
    int statusCode,
    String reasonPhrase,
    Uri uri,
  ) {
    if (statusCode >= 200 && statusCode < 400) {
      return (success: true, error: null);
    }
    // 407 (Proxy Authentication Required) and 401 mean the proxy/server
    // rejected the credentials. They must fail BEFORE the 4xx-reachability
    // rule below, otherwise wrong proxy credentials report "working".
    if (statusCode == 407 || statusCode == 401) {
      return (
        success: false,
        error: 'HTTP $statusCode: '
            '${reasonPhrase.isEmpty ? 'Authentication failed' : reasonPhrase}',
      );
    }
    if (statusCode >= 400 &&
        statusCode < 500 &&
        (uri.host.contains('youtube.com') ||
            uri.host.contains('googlevideo.com'))) {
      // YouTube answered (even with 403/404): the proxy path itself works,
      // the restriction is IP-level. Count the proxy as reachable.
      return (success: true, error: null);
    }
    return (success: false, error: 'HTTP $statusCode: $reasonPhrase');
  }

  /// Probes connectivity through the currently configured proxy.
  /// Defaults to the YouTube Music host: a Google-204 probe can succeed while
  /// the current IP/VPN exit is blocked for YouTube, marking a useless proxy
  /// as "working". Any HTTP response (even 4xx) from music.youtube.com proves
  /// the path reaches YouTube; only 5xx/network errors (and auth failures)
  /// mean failure.
  /// Returns a record with `(success, latencyMs, errorMessage)`.
  Future<({bool success, int latencyMs, String? error})> testConnection({
    ProxyConfig? configToTest,
    String testUrl = 'https://music.youtube.com/',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final testConfig = configToTest ?? _config;

    // SOCKS5 cannot be probed via Dart's HttpClient because HttpClient only
    // supports HTTP proxies (toFindProxyString returns 'DIRECT' for socks5).
    // Perform a real SOCKS5 reachability check.
    if (testConfig.enabled && testConfig.type == AppProxyType.socks5) {
      return _testSocks5Connection(
        testConfig: testConfig,
        uri: Uri.parse(testUrl),
        timeout: timeout,
      );
    }

    final stopwatch = Stopwatch()..start();
    HttpClient? testClient;

    try {
      final uri = Uri.parse(testUrl);
      testClient = HttpClient()
        ..connectionTimeout = timeout
        ..idleTimeout = timeout;

      testClient.findProxy = (u) {
        if (testConfig.enabled &&
            testConfig.isValid &&
            !testConfig.isBypassed(u)) {
          return testConfig.toFindProxyString(u);
        }
        return HttpClient.findProxyFromEnvironment(
          u,
          environment: Platform.environment,
        );
      };

      if (testConfig.enabled && testConfig.hasAuth) {
        testClient.addProxyCredentials(
          testConfig.host,
          testConfig.port,
          'Basic',
          HttpClientBasicCredentials(testConfig.username, testConfig.password),
        );
        testClient.authenticateProxy = (host, port, scheme, realm) async {
          testClient?.addProxyCredentials(
            host,
            port,
            realm ?? '',
            HttpClientBasicCredentials(
                testConfig.username, testConfig.password),
          );
          return true;
        };
      }

      final request = await testClient.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      stopwatch.stop();

      // Drain response bytes to free connection
      await response.drain<void>();

      final verdict = evaluateResponse(
        response.statusCode,
        response.reasonPhrase,
        uri,
      );
      return (
        success: verdict.success,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: verdict.error,
      );
    } catch (e) {
      stopwatch.stop();
      return (
        success: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: e
            .toString()
            .replaceAll('SocketException: ', '')
            .replaceAll('HttpException: ', ''),
      );
    } finally {
      testClient?.close(force: true);
    }
  }

  Future<({bool success, int latencyMs, String? error})> _testSocks5Connection({
    required ProxyConfig testConfig,
    required Uri uri,
    required Duration timeout,
  }) async {
    if (!testConfig.isValid) {
      return (
        success: false,
        latencyMs: 0,
        error: 'Invalid proxy configuration: host or port missing',
      );
    }

    // Try native Android MethodChannel if available
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await const MethodChannel(PulsrChannels.proxy)
            .invokeMethod<Map<dynamic, dynamic>>('testProxy', {
          'testUrl': uri.toString(),
          'timeoutMs': timeout.inMilliseconds,
        });
        if (result != null) {
          final success = result['success'] as bool? ?? false;
          final latency = (result['latencyMs'] as num?)?.toInt() ?? 0;
          final error = result['error'] as String?;
          return (success: success, latencyMs: latency, error: error);
        }
      } on MissingPluginException {
        // Fall back to raw socket handshake
      } on PlatformException {
        // Fall back to raw socket handshake
      } catch (_) {
        // Fall back to raw socket handshake
      }
    }

    return testSocks5ViaSocket(
      testConfig: testConfig,
      targetUri: uri,
      timeout: timeout,
    );
  }

  /// Performs raw SOCKS5 RFC 1928 greeting & CONNECT handshake.
  @visibleForTesting
  static Future<({bool success, int latencyMs, String? error})> testSocks5ViaSocket({
    required ProxyConfig testConfig,
    required Uri targetUri,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    _SocketByteReader? reader;

    try {
      socket = await Socket.connect(
        testConfig.host,
        testConfig.port,
        timeout: timeout,
      );
      reader = _SocketByteReader(socket);

      // 1. SOCKS5 greeting
      if (testConfig.hasAuth) {
        socket.add([0x05, 0x02, 0x00, 0x02]); // Offer NO AUTH (0x00) and USER/PASS (0x02)
      } else {
        socket.add([0x05, 0x01, 0x00]); // Offer NO AUTH (0x00)
      }
      await socket.flush();

      final greetingReply = await reader.readBytes(2, timeout);
      if (greetingReply[0] != 0x05) {
        throw const SocketException('Invalid SOCKS version in server greeting');
      }
      final selectedMethod = greetingReply[1];
      if (selectedMethod == 0xFF) {
        throw const SocketException('SOCKS5 proxy rejected authentication methods (0xFF)');
      }

      // 2. Authentication (RFC 1929) if required
      if (selectedMethod == 0x02) {
        if (!testConfig.hasAuth) {
          throw const SocketException('SOCKS5 proxy requires authentication');
        }
        final userBytes = utf8.encode(testConfig.username);
        final passBytes = utf8.encode(testConfig.password);
        if (userBytes.length > 255 || passBytes.length > 255) {
          throw const SocketException(
              'SOCKS5 username and password must each be 255 bytes or fewer');
        }
        socket.add([0x01, userBytes.length, ...userBytes, passBytes.length, ...passBytes]);
        await socket.flush();

        final authReply = await reader.readBytes(2, timeout);
        if (authReply[1] != 0x00) {
          throw SocketException('SOCKS5 authentication failed (status: ${authReply[1]})');
        }
      }

      // 3. SOCKS5 CONNECT to target host & port
      final hostBytes = utf8.encode(targetUri.host);
      if (hostBytes.isEmpty || hostBytes.length > 255) {
        throw const SocketException(
            'SOCKS5 host must be non-empty and 255 bytes or fewer');
      }
      final targetPort = targetUri.port > 0
          ? targetUri.port
          : (targetUri.isScheme('https') ? 443 : 80);
      socket.add([
        0x05, // VER
        0x01, // CMD: CONNECT
        0x00, // RSV
        0x03, // ATYP: DOMAINNAME
        hostBytes.length,
        ...hostBytes,
        (targetPort >> 8) & 0xFF,
        targetPort & 0xFF,
      ]);
      await socket.flush();

      final replyHeader = await reader.readBytes(4, timeout);
      if (replyHeader[0] != 0x05) {
        throw const SocketException('Invalid SOCKS version in connect reply');
      }
      final rep = replyHeader[1];
      if (rep != 0x00) {
        throw SocketException(_socks5ErrorMessage(rep));
      }

      // Consume bound address and port
      final atyp = replyHeader[3];
      if (atyp == 0x01) {
        await reader.readBytes(4 + 2, timeout); // IPv4 + port
      } else if (atyp == 0x03) {
        final lenBytes = await reader.readBytes(1, timeout);
        await reader.readBytes(lenBytes[0] + 2, timeout); // domain + port
      } else if (atyp == 0x04) {
        await reader.readBytes(16 + 2, timeout); // IPv6 + port
      }

      sw.stop();
      return (
        success: true,
        latencyMs: sw.elapsedMilliseconds,
        error: null,
      );
    } catch (e) {
      sw.stop();
      return (
        success: false,
        latencyMs: sw.elapsedMilliseconds,
        error: e
            .toString()
            .replaceAll('SocketException: ', '')
            .replaceAll('HttpException: ', ''),
      );
    } finally {
      await reader?.cancel();
      socket?.destroy();
    }
  }

  static String _socks5ErrorMessage(int rep) {
    switch (rep) {
      case 0x01:
        return 'SOCKS5 server error: general failure';
      case 0x02:
        return 'SOCKS5 connection not allowed by ruleset';
      case 0x03:
        return 'SOCKS5 network unreachable';
      case 0x04:
        return 'SOCKS5 host unreachable';
      case 0x05:
        return 'SOCKS5 connection refused';
      case 0x06:
        return 'SOCKS5 TTL expired';
      case 0x07:
        return 'SOCKS5 command not supported';
      case 0x08:
        return 'SOCKS5 address type not supported';
      default:
        return 'SOCKS5 connection error (code $rep)';
    }
  }
}

class _SocketByteReader {
  final Stream<Uint8List> _stream;
  StreamSubscription<Uint8List>? _sub;
  final List<int> _buffer = [];
  Completer<void>? _waitCompleter;
  int _waitCount = 0;
  bool _isDone = false;

  _SocketByteReader(this._stream) {
    _sub = _stream.listen(
      (chunk) {
        _buffer.addAll(chunk);
        if (_waitCompleter != null && _buffer.length >= _waitCount) {
          _waitCompleter!.complete();
          _waitCompleter = null;
        }
      },
      onError: (e) {
        _waitCompleter?.completeError(e);
        _waitCompleter = null;
      },
      onDone: () {
        _isDone = true;
        _waitCompleter?.complete();
        _waitCompleter = null;
      },
      cancelOnError: true,
    );
  }

  Future<List<int>> readBytes(int count, Duration timeout) async {
    if (_buffer.length >= count) {
      final res = _buffer.sublist(0, count);
      _buffer.removeRange(0, count);
      return res;
    }
    if (_isDone) {
      throw const SocketException('Connection closed before bytes were received');
    }
    _waitCount = count;
    _waitCompleter = Completer<void>();
    await _waitCompleter!.future.timeout(timeout);
    if (_buffer.length < count) {
      throw const SocketException('Incomplete response received from SOCKS5 proxy');
    }
    final res = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return res;
  }

  Future<void> cancel() async {
    await _sub?.cancel();
    _sub = null;
  }
}
