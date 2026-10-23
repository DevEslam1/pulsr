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
  ServerSocket? _socks5BridgeServer;
  Future<int?>? _socks5BridgeStarting;

  ProxyConfig get currentConfig => _config;

  /// Port of the active local HTTP-to-SOCKS5 loopback bridge, if running.
  int? get socks5BridgePort => _socks5BridgeServer?.port;

  void update(ProxyConfig newConfig) {
    _config = newConfig;
    if (newConfig.enabled &&
        newConfig.isValid &&
        newConfig.type == AppProxyType.socks5) {
      unawaited(ensureSocks5Bridge());
    } else {
      unawaited(stopSocks5Bridge());
    }
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

  /// Ensures the local loopback HTTP-to-SOCKS5 proxy bridge is listening when
  /// a SOCKS5 proxy is configured, allowing Dart's [HttpClient] (which only
  /// speaks HTTP `PROXY` in `findProxy`) to tunnel through SOCKS5 transparently.
  Future<int?> ensureSocks5Bridge() async {
    if (!_config.enabled ||
        !_config.isValid ||
        _config.type != AppProxyType.socks5) {
      await stopSocks5Bridge();
      return null;
    }
    if (_socks5BridgeServer != null) {
      return _socks5BridgeServer!.port;
    }
    if (_socks5BridgeStarting != null) {
      return _socks5BridgeStarting;
    }
    final completer = Completer<int?>();
    _socks5BridgeStarting = completer.future;
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _socks5BridgeServer = server;
      server.listen(
        _handleSocks5BridgeClient,
        onError: (_) {},
        cancelOnError: false,
      );
      completer.complete(server.port);
      return server.port;
    } catch (e) {
      completer.complete(null);
      return null;
    } finally {
      _socks5BridgeStarting = null;
    }
  }

  /// Stops the local loopback HTTP-to-SOCKS5 proxy bridge if running.
  Future<void> stopSocks5Bridge() async {
    final server = _socks5BridgeServer;
    _socks5BridgeServer = null;
    if (server != null) {
      try {
        await server.close();
      } catch (_) {}
    }
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
        if (_config.type == AppProxyType.socks5) {
          final bridgePort = _socks5BridgeServer?.port;
          if (bridgePort != null) {
            return 'PROXY 127.0.0.1:$bridgePort; DIRECT';
          }
          unawaited(ensureSocks5Bridge());
        }
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
    final authAttempts = <String, int>{};
    client.authenticateProxy = (host, port, scheme, realm) async {
      final targetHost = _config.host.trim().toLowerCase();
      final targetPort = _config.port;
      if (_config.enabled &&
          _config.hasAuth &&
          host.toLowerCase() == targetHost &&
          port == targetPort) {
        final authKey = '$host:$port:${realm ?? ''}';
        final attempts = authAttempts[authKey] ?? 0;
        if (attempts >= 1) {
          // Already attempted and rejected (407 retry loop); do not retry
          return false;
        }
        authAttempts[authKey] = attempts + 1;
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
        final authAttempts = <String, int>{};
        testClient.authenticateProxy = (host, port, scheme, realm) async {
          if (host.toLowerCase() == testConfig.host.trim().toLowerCase() &&
              port == testConfig.port) {
            final authKey = '$host:$port:${realm ?? ''}';
            final attempts = authAttempts[authKey] ?? 0;
            if (attempts >= 1) {
              return false;
            }
            authAttempts[authKey] = attempts + 1;
            testClient?.addProxyCredentials(
              host,
              port,
              realm ?? '',
              HttpClientBasicCredentials(
                  testConfig.username, testConfig.password),
            );
            return true;
          }
          return false;
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

  /// Performs raw SOCKS5 RFC 1928 greeting & CONNECT handshake and returns the
  /// established tunnel socket + byte reader.
  static Future<({Socket socket, _SocketByteReader reader})> _openSocks5Tunnel({
    required ProxyConfig proxyConfig,
    required String targetHost,
    required int targetPort,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    Socket? socket;
    _SocketByteReader? reader;
    try {
      socket = await Socket.connect(
        proxyConfig.host,
        proxyConfig.port,
        timeout: timeout,
      );
      reader = _SocketByteReader(socket);

      // 1. SOCKS5 greeting
      if (proxyConfig.hasAuth) {
        socket.add([
          0x05,
          0x02,
          0x00,
          0x02
        ]); // Offer NO AUTH (0x00) and USER/PASS (0x02)
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
        throw const SocketException(
            'SOCKS5 proxy rejected authentication methods (0xFF)');
      }

      // 2. Authentication (RFC 1929) if required
      if (selectedMethod == 0x02) {
        if (!proxyConfig.hasAuth) {
          throw const SocketException('SOCKS5 proxy requires authentication');
        }
        final userBytes = utf8.encode(proxyConfig.username);
        final passBytes = utf8.encode(proxyConfig.password);
        if (userBytes.length > 255 || passBytes.length > 255) {
          throw const SocketException(
              'SOCKS5 username and password must each be 255 bytes or fewer');
        }
        socket.add([
          0x01,
          userBytes.length,
          ...userBytes,
          passBytes.length,
          ...passBytes
        ]);
        await socket.flush();

        final authReply = await reader.readBytes(2, timeout);
        if (authReply[1] != 0x00) {
          throw SocketException(
              'SOCKS5 authentication failed (status: ${authReply[1]})');
        }
      }

      // 3. SOCKS5 CONNECT to target host & port
      final hostBytes = utf8.encode(targetHost);
      if (hostBytes.isEmpty || hostBytes.length > 255) {
        throw const SocketException(
            'SOCKS5 host must be non-empty and 255 bytes or fewer');
      }
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

      return (socket: socket, reader: reader);
    } catch (_) {
      await reader?.cancel();
      socket?.destroy();
      rethrow;
    }
  }

  Future<void> _handleSocks5BridgeClient(Socket clientSocket) async {
    final clientReader = _SocketByteReader(clientSocket);
    Socket? upstreamSocket;
    _SocketByteReader? upstreamReader;
    const timeout = Duration(seconds: 15);

    try {
      final headerBytes = await clientReader.readUntilHeaderEnd(timeout);
      final headerStr = latin1.decode(headerBytes);
      final lines = headerStr.split('\r\n');
      if (lines.isEmpty || lines.first.isEmpty) {
        clientSocket.destroy();
        return;
      }

      final requestLineParts = lines.first.split(' ');
      if (requestLineParts.length < 3) {
        clientSocket.destroy();
        return;
      }

      final method = requestLineParts[0].toUpperCase();
      final requestTarget = requestLineParts[1];
      final httpVersion = requestLineParts[2];

      if (method == 'CONNECT') {
        final colonIdx = requestTarget.lastIndexOf(':');
        final targetHost = colonIdx > 0
            ? requestTarget.substring(0, colonIdx)
            : requestTarget;
        final targetPort = colonIdx > 0
            ? (int.tryParse(requestTarget.substring(colonIdx + 1)) ?? 443)
            : 443;

        final tunnel = await _openSocks5Tunnel(
          proxyConfig: _config,
          targetHost: targetHost,
          targetPort: targetPort,
          timeout: timeout,
        );
        upstreamSocket = tunnel.socket;
        upstreamReader = tunnel.reader;

        clientSocket.add(
          ascii.encode('HTTP/1.1 200 Connection Established\r\n\r\n'),
        );
        await clientSocket.flush();

        clientReader.forwardTo(upstreamSocket);
        upstreamReader.forwardTo(clientSocket);
      } else {
        final targetUri = Uri.tryParse(requestTarget);
        if (targetUri == null || targetUri.host.isEmpty) {
          clientSocket.destroy();
          return;
        }
        final targetHost = targetUri.host;
        final targetPort = targetUri.hasPort
            ? targetUri.port
            : (targetUri.isScheme('https') ? 443 : 80);
        final relativePath = targetUri.path.isEmpty ? '/' : targetUri.path;
        final pathWithQuery = targetUri.hasQuery
            ? '$relativePath?${targetUri.query}'
            : relativePath;

        final tunnel = await _openSocks5Tunnel(
          proxyConfig: _config,
          targetHost: targetHost,
          targetPort: targetPort,
          timeout: timeout,
        );
        upstreamSocket = tunnel.socket;
        upstreamReader = tunnel.reader;

        final rewrittenLines = <String>[
          '$method $pathWithQuery $httpVersion',
          ...lines.skip(1).where(
                (l) => !l.toLowerCase().startsWith('proxy-'),
              ),
        ];
        upstreamSocket.add(latin1.encode(rewrittenLines.join('\r\n')));
        await upstreamSocket.flush();

        clientReader.forwardTo(upstreamSocket);
        upstreamReader.forwardTo(clientSocket);
      }
    } catch (_) {
      await clientReader.cancel();
      await upstreamReader?.cancel();
      upstreamSocket?.destroy();
      try {
        clientSocket.add(
          ascii.encode('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n'),
        );
        await clientSocket.flush();
      } catch (_) {}
      clientSocket.destroy();
    }
  }

  /// Performs raw SOCKS5 RFC 1928 greeting & CONNECT handshake.
  @visibleForTesting
  static Future<({bool success, int latencyMs, String? error})>
      testSocks5ViaSocket({
    required ProxyConfig testConfig,
    required Uri targetUri,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    _SocketByteReader? reader;

    try {
      final targetPort = targetUri.port > 0
          ? targetUri.port
          : (targetUri.isScheme('https') ? 443 : 80);
      final tunnel = await _openSocks5Tunnel(
        proxyConfig: testConfig,
        targetHost: targetUri.host,
        targetPort: targetPort,
        timeout: timeout,
      );
      socket = tunnel.socket;
      reader = tunnel.reader;

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
  int _offset = 0;
  Completer<void>? _waitCompleter;
  int _waitCount = 0;
  bool _waitHeaderEnd = false;
  Socket? _forwardTarget;
  bool _isDone = false;
  Object? _error;
  StackTrace? _errorStack;

  int get _availableBytes => _buffer.length - _offset;

  _SocketByteReader(this._stream) {
    _sub = _stream.listen(
      (chunk) {
        final target = _forwardTarget;
        if (target != null) {
          try {
            target.add(chunk);
          } catch (_) {
            target.destroy();
          }
          return;
        }
        _buffer.addAll(chunk);
        if (_waitCompleter != null) {
          if (_waitHeaderEnd && _findHeaderEndIndex() != -1) {
            if (!_waitCompleter!.isCompleted) _waitCompleter!.complete();
            _waitCompleter = null;
          } else if (!_waitHeaderEnd && _availableBytes >= _waitCount) {
            if (!_waitCompleter!.isCompleted) _waitCompleter!.complete();
            _waitCompleter = null;
          }
        }
      },
      onError: (e, st) {
        final target = _forwardTarget;
        if (target != null) {
          target.destroy();
          return;
        }
        _error = e;
        _errorStack = st;
        _isDone = true;
        if (_waitCompleter != null && !_waitCompleter!.isCompleted) {
          _waitCompleter!.completeError(e, st);
          _waitCompleter = null;
        }
      },
      onDone: () {
        final target = _forwardTarget;
        if (target != null) {
          try {
            target.destroy();
          } catch (_) {}
          return;
        }
        _isDone = true;
        if (_waitCompleter != null && !_waitCompleter!.isCompleted) {
          _waitCompleter!.complete();
          _waitCompleter = null;
        }
      },
      cancelOnError: true,
    );
  }

  int _findHeaderEndIndex() {
    final end = _buffer.length - 3;
    for (var i = _offset; i < end; i++) {
      if (_buffer[i] == 13 &&
          _buffer[i + 1] == 10 &&
          _buffer[i + 2] == 13 &&
          _buffer[i + 3] == 10) {
        return i + 4;
      }
    }
    return -1;
  }

  Future<List<int>> readUntilHeaderEnd(Duration timeout) async {
    _checkAndRethrowError();
    var endIdx = _findHeaderEndIndex();
    if (endIdx != -1) {
      final res = _buffer.sublist(_offset, endIdx);
      _offset = endIdx;
      _compactBufferIfNeeded();
      return res;
    }
    if (_isDone) {
      throw const SocketException('Connection closed before HTTP header end');
    }
    _waitHeaderEnd = true;
    _waitCompleter = Completer<void>();
    try {
      await _waitCompleter!.future.timeout(timeout);
    } finally {
      _waitCompleter = null;
      _waitHeaderEnd = false;
    }
    _checkAndRethrowError();
    endIdx = _findHeaderEndIndex();
    if (endIdx == -1) {
      throw const SocketException('Incomplete HTTP header received');
    }
    final res = _buffer.sublist(_offset, endIdx);
    _offset = endIdx;
    _compactBufferIfNeeded();
    return res;
  }

  void forwardTo(Socket target) {
    if (_availableBytes > 0) {
      final remaining = _buffer.sublist(_offset);
      _buffer.clear();
      _offset = 0;
      try {
        target.add(remaining);
      } catch (_) {
        target.destroy();
        return;
      }
    }
    if (_isDone) {
      target.destroy();
      return;
    }
    _forwardTarget = target;
  }

  void _compactBufferIfNeeded() {
    if (_offset > 0 && _offset >= _buffer.length ~/ 2) {
      _buffer.removeRange(0, _offset);
      _offset = 0;
    }
  }

  void _checkAndRethrowError() {
    if (_error != null) {
      final err = _error!;
      final st = _errorStack ?? StackTrace.current;
      if (err is Exception) {
        Error.throwWithStackTrace(err, st);
      }
      Error.throwWithStackTrace(
          SocketException('SOCKS5 socket error: $err'), st);
    }
  }

  Future<List<int>> readBytes(int count, Duration timeout) async {
    _checkAndRethrowError();

    if (_availableBytes >= count) {
      final res = _buffer.sublist(_offset, _offset + count);
      _offset += count;
      _compactBufferIfNeeded();
      return res;
    }
    if (_isDone) {
      throw const SocketException(
          'Connection closed before bytes were received');
    }
    _waitCount = count;
    _waitCompleter = Completer<void>();
    try {
      await _waitCompleter!.future.timeout(timeout);
    } finally {
      _waitCompleter = null;
      _waitCount = 0;
    }

    _checkAndRethrowError();

    if (_availableBytes < count) {
      throw const SocketException(
          'Incomplete response received from SOCKS5 proxy');
    }
    final res = _buffer.sublist(_offset, _offset + count);
    _offset += count;
    _compactBufferIfNeeded();
    return res;
  }

  Future<void> cancel() async {
    await _sub?.cancel();
    _sub = null;
  }
}
