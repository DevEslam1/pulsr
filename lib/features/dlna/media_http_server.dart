// lib/features/dlna/media_http_server.dart
//
// HTTP file server used as the DLNA media source. URLs carry an opaque token
// only: the server resolves tokens through its registry and never turns a URL
// path into a filesystem path.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../core/utils/error_logger.dart';

/// A media item the DLNA renderer can fetch.
class MediaSource {
  /// Absolute path of the file to serve, when this is a file source.
  final String? filePath;

  /// MIME type override; derived from the extension for file sources when
  /// omitted.
  final String? contentType;

  final Future<List<int>> Function()? _loadBytes;

  /// Serves [path] from disk.
  const MediaSource.file(String path, {this.contentType})
      : filePath = path,
        _loadBytes = null;

  /// Serves bytes produced by [loader] (used for in-memory or generated media).
  const MediaSource.bytes(
    Future<List<int>> Function() loader, {
    required this.contentType,
  })  : filePath = null,
        _loadBytes = loader;

  /// True when the source reads from disk.
  bool get isFile => filePath != null;

  Future<List<int>> _bytes() async {
    final loader = _loadBytes;
    if (loader == null) {
      throw StateError('MediaSource has neither a path nor a byte loader.');
    }
    return loader();
  }
}

/// Serves registered [MediaSource]s over HTTP 1.1 with byte ranges.
///
/// Tokens are registered by the renderer service, capped at [maxEntries] and
/// expire after [tokenTtl]. Every request must carry a registered token; the
/// URL never selects a file on its own. Use [newToken] to create
/// cryptographically random tokens.
class MediaHttpServer {
  /// Largest number of tokens kept alive at once.
  final int maxEntries;

  /// How long a token stays valid after registration.
  final Duration tokenTtl;

  /// Largest number of requests handled at once. Further requests get 503.
  final int maxConcurrentRequests;

  /// A token read within this window is never evicted while the server runs.
  ///
  /// A renderer streaming a long track re-reads the same token for every range
  /// request; evicting it mid-playback used to end the cast with a 403.
  static const Duration activeAccessWindow = Duration(minutes: 2);

  /// Longest request path accepted, in characters.
  static const int maxRequestPathLength = 512;

  static final Random _secureRandom = Random.secure();
  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  final InternetAddress _defaultBindAddress;
  final Map<String, _MediaEntry> _entries = <String, _MediaEntry>{};

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  Future<void>? _starting;
  String _host = InternetAddress.loopbackIPv4.address;
  int _activeRequests = 0;

  /// Creates a server. [bindAddress] is used when [start] is called without an
  /// explicit address; both defaults serve every IPv4 interface so a LAN
  /// renderer can reach the server.
  MediaHttpServer({
    this.maxEntries = 32,
    this.tokenTtl = const Duration(hours: 6),
    this.maxConcurrentRequests = 8,
    InternetAddress? bindAddress,
  })  : assert(maxEntries > 0, 'maxEntries must be positive'),
        assert(maxConcurrentRequests > 0,
            'maxConcurrentRequests must be positive'),
        _defaultBindAddress = bindAddress ?? InternetAddress.anyIPv4;

  /// Bound port, or `null` before [start].
  int? get port => _server?.port;

  /// True between [start] and [stop].
  bool get isRunning => _server != null;

  /// Address the advertised URL uses, or the loopback fallback before [start].
  String get host => _host;

  /// Generates a 128-bit token as 32 lowercase hex characters using
  /// [Random.secure]. [random] is injectable for deterministic tests.
  static String newToken({Random? random}) {
    final rng = random ?? _secureRandom;
    final buffer = StringBuffer();
    for (var index = 0; index < 16; index++) {
      buffer.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Returns the local address the OS would use to reach [host], or `null`
  /// when it cannot be determined. Used to bind the server to the interface
  /// that actually faces the renderer instead of guessing.
  ///
  /// A short TCP connect to the renderer's control port reveals the chosen
  /// source address without sending any application data.
  static Future<InternetAddress?> localAddressFacing(
    String host,
    int port,
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 2),
      );
      final local = socket.address;
      if (local.isLoopback || _isUnspecified(local)) return null;
      return local;
    } on SocketException catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA local address detection failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
      return null;
    } finally {
      socket?.destroy();
    }
  }

  /// Starts listening on an ephemeral port. Safe to call twice.
  ///
  /// [bindAddress] overrides the constructor address. When it is a concrete
  /// interface the advertised URL uses exactly that interface; when the server
  /// binds the wildcard address the best local address is detected.
  Future<void> start({InternetAddress? bindAddress}) async {
    if (_server != null) return;
    final pending = _starting;
    if (pending != null) {
      await pending;
      return;
    }
    final future = _startInternal(bindAddress: bindAddress);
    _starting = future;
    try {
      await future;
    } finally {
      if (identical(_starting, future)) _starting = null;
    }
  }

  Future<void> _startInternal({InternetAddress? bindAddress}) async {
    if (_server != null) return;
    try {
      final target = bindAddress ?? _defaultBindAddress;
      HttpServer server;
      try {
        server = await HttpServer.bind(target, 0);
      } on SocketException catch (error, stackTrace) {
        if (target.address == InternetAddress.anyIPv4.address) rethrow;
        // The interface chosen by the resolver disappeared between discovery
        // and binding; fall back to all interfaces rather than failing a cast.
        ErrorLogger.log(
          'DLNA media server could not bind ${target.address}; '
          'falling back to all interfaces',
          error: error,
          stackTrace: stackTrace,
          category: 'DLNA',
        );
        server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      // Bound per-connection idle handling so a stalled client cannot pin a
      // request handler (and a concurrency slot) forever.
      server.idleTimeout = const Duration(seconds: 30);
      _server = server;
      final bound = server.address;
      _host = _isUnspecified(bound) ? await _detectHost() : bound.address;
      _subscription = server.listen(
        (request) {
          unawaited(_handle(request));
        },
        onError: (Object error, StackTrace stackTrace) {
          ErrorLogger.log(
            'DLNA media server socket error',
            error: error,
            stackTrace: stackTrace,
            category: 'DLNA',
          );
        },
      );
    } on SocketException catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA media server failed to bind',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
      rethrow;
    }
  }

  /// Registers [source] under [token], evicting expired and oldest entries.
  ///
  /// [token] must be URL-safe; the server rejects request paths that could be
  /// read as filesystem traversal before it ever looks the token up.
  void register(String token, MediaSource source) {
    if (!_isValidToken(token)) {
      throw ArgumentError.value(
        token,
        'token',
        'Token must be 1-$maxRequestPathLength URL-safe characters',
      );
    }
    final now = DateTime.now();
    _entries[token] = _MediaEntry(
      source: source,
      expiresAt: now.add(tokenTtl),
      registeredAt: now,
    );
    _prune();
  }

  /// Removes [token]; returns whether it was registered and still valid.
  bool unregister(String token) => _entries.remove(token) != null;

  /// Absolute URL a renderer can fetch [token] from.
  Uri uriFor(String token) {
    final server = _server;
    if (server == null) {
      throw StateError('MediaHttpServer.start() must be called first.');
    }
    return Uri(
      scheme: 'http',
      host: _host,
      port: server.port,
      pathSegments: <String>['media', token],
    );
  }

  /// Stops the server, drops every token, and is safe to call repeatedly.
  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final server = _server;
    _server = null;
    _entries.clear();
    _host = InternetAddress.loopbackIPv4.address;
    if (server != null) await server.close(force: true);
  }

  /// MIME type derived from a file name's extension.
  static String contentTypeFor(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'application/octet-stream';
    switch (name.substring(dot + 1).toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'm4b':
      case 'mp4':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'oga':
        return 'audio/ogg';
      case 'opus':
        return 'audio/opus';
      case 'wma':
        return 'audio/x-ms-wma';
      case 'aiff':
      case 'aif':
        return 'audio/aiff';
      case 'dsf':
        return 'audio/x-dsf';
      case 'dff':
        return 'audio/x-dff';
      case 'ape':
        return 'audio/x-ape';
      case 'wv':
        return 'audio/x-wavpack';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _handle(HttpRequest request) async {
    if (_activeRequests >= maxConcurrentRequests) {
      try {
        await _writeEmpty(request.response, HttpStatus.serviceUnavailable);
      } catch (_) {
        // The request is already gone; nothing else to release.
      }
      return;
    }
    _activeRequests += 1;
    try {
      await _dispatch(request);
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA media request failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (closeError, closeStack) {
        ErrorLogger.log(
          'DLNA media response close failed',
          error: closeError,
          stackTrace: closeStack,
          category: 'DLNA',
        );
      }
    } finally {
      _activeRequests -= 1;
    }
  }

  Future<void> _dispatch(HttpRequest request) async {
    final method = request.method;
    if (method != 'GET' && method != 'HEAD') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD')
        ..headers.set(HttpHeaders.contentLengthHeader, '0');
      await request.response.close();
      return;
    }

    // Reject anything that could be interpreted as a filesystem path before
    // consulting the token registry. `Uri.path` keeps percent-encoding, so a
    // request for `%2e%2e` is rejected even though `pathSegments` decodes it.
    final rawPath = request.uri.path;
    if (rawPath.length > maxRequestPathLength ||
        rawPath.contains('%') ||
        rawPath.contains(r'\') ||
        rawPath.contains('..')) {
      await _writeEmpty(request.response, HttpStatus.forbidden);
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.length != 2 ||
        segments.first != 'media' ||
        !_isValidToken(segments[1])) {
      await _writeEmpty(request.response, HttpStatus.forbidden);
      return;
    }

    final entry = _lookup(segments[1]);
    if (entry == null) {
      await _writeEmpty(request.response, HttpStatus.forbidden);
      return;
    }

    final source = entry.source;
    if (source.isFile) {
      final file = File(source.filePath!);
      if (!await file.exists()) {
        await _writeEmpty(request.response, HttpStatus.notFound);
        return;
      }
    }
    final bytes = source.isFile ? null : await source._bytes();
    final size = source.isFile
        ? await File(source.filePath!).length()
        : bytes?.length ?? 0;

    final range = _parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      size,
    );
    if (range.status == _RangeStatus.unsatisfiable) {
      request.response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size')
        ..headers.set(HttpHeaders.contentLengthHeader, '0');
      await request.response.close();
      return;
    }

    final start = range.status == _RangeStatus.satisfiable ? range.start : 0;
    final end = range.status == _RangeStatus.satisfiable ? range.end : size - 1;
    final length = size == 0 ? 0 : end - start + 1;
    final contentType = source.contentType ??
        (source.filePath == null
            ? 'application/octet-stream'
            : contentTypeFor(source.filePath!));

    final response = request.response
      ..statusCode = range.status == _RangeStatus.satisfiable
          ? HttpStatus.partialContent
          : HttpStatus.ok
      ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..headers.set(HttpHeaders.contentTypeHeader, contentType)
      ..headers.set(HttpHeaders.contentLengthHeader, '$length');
    if (range.status == _RangeStatus.satisfiable) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    }

    if (request.method == 'HEAD' || length == 0) {
      await response.close();
      return;
    }

    if (source.isFile) {
      try {
        await response
            .addStream(File(source.filePath!).openRead(start, end + 1));
      } on FileSystemException catch (error, stackTrace) {
        ErrorLogger.log(
          'DLNA media file read failed',
          error: error,
          stackTrace: stackTrace,
          category: 'DLNA',
        );
        await response.close();
        return;
      }
    } else {
      final slice = bytes!.sublist(start, end + 1);
      response.add(slice);
    }
    await response.close();
  }

  Future<void> _writeEmpty(HttpResponse response, int statusCode) async {
    response
      ..statusCode = statusCode
      ..headers.set(HttpHeaders.contentLengthHeader, '0');
    await response.close();
  }

  _MediaEntry? _lookup(String token) {
    _prune();
    final entry = _entries[token];
    if (entry == null) return null;
    // Touch on access: LRU order and the token TTL both follow reads, not
    // registration, so an actively streamed item stays valid and is the last
    // candidate for eviction.
    final now = DateTime.now();
    entry.lastAccess = now;
    entry.expiresAt = now.add(tokenTtl);
    return entry;
  }

  void _prune() {
    final now = DateTime.now();
    _entries.removeWhere((_, entry) => !entry.expiresAt.isAfter(now));
    if (_entries.length <= maxEntries) return;

    final cutoff = now.subtract(activeAccessWindow);
    final running = _server != null;

    bool isActive(_MediaEntry entry) {
      final access = entry.lastAccess;
      return running && access != null && access.isAfter(cutoff);
    }

    // Least-recently ACCESSED first (never-read entries fall back to their
    // registration time), skipping anything a renderer read in the last two
    // minutes.
    final candidates = _entries.entries
        .where((entry) => !isActive(entry.value))
        .toList()
      ..sort((a, b) => a.value.freshness.compareTo(b.value.freshness));
    for (final candidate in candidates) {
      if (_entries.length <= maxEntries) break;
      _entries.remove(candidate.key);
    }

    // Everything left was read within the protection window. The cap still
    // wins: dropping the least recently read entry keeps a renderer that
    // cycles through more live tracks than the registry can hold bounded.
    if (_entries.length > maxEntries) {
      final overflow = _entries.entries.toList()
        ..sort((a, b) => a.value.freshness.compareTo(b.value.freshness));
      for (final entry in overflow) {
        if (_entries.length <= maxEntries) break;
        _entries.remove(entry.key);
      }
    }
  }

  /// Parses a Range header. Multi-range requests are served as their first
  /// range (a valid single-range response) instead of a 416.
  _RangeOutcome _parseRange(String? header, int size) {
    if (header == null || header.isEmpty) return const _RangeOutcome.none();
    if (!header.toLowerCase().startsWith('bytes=')) {
      return const _RangeOutcome.none();
    }
    final specs = header.substring(6).split(',');
    final spec = specs.first.trim();
    if (spec.isEmpty) {
      return const _RangeOutcome.unsatisfiable();
    }
    final dash = spec.indexOf('-');
    if (dash < 0) return const _RangeOutcome.unsatisfiable();

    final startText = spec.substring(0, dash).trim();
    final endText = spec.substring(dash + 1).trim();

    if (startText.isEmpty) {
      final suffix = int.tryParse(endText);
      if (suffix == null || suffix <= 0 || size == 0) {
        return const _RangeOutcome.unsatisfiable();
      }
      final start = suffix >= size ? 0 : size - suffix;
      return _RangeOutcome.satisfiable(start, size - 1);
    }

    final start = int.tryParse(startText);
    if (start == null || start < 0 || start >= size) {
      return const _RangeOutcome.unsatisfiable();
    }
    var end = size - 1;
    if (endText.isNotEmpty) {
      final parsed = int.tryParse(endText);
      if (parsed == null || parsed < start) {
        return const _RangeOutcome.unsatisfiable();
      }
      if (parsed < size) end = parsed;
    }
    return _RangeOutcome.satisfiable(start, end);
  }

  Future<String> _detectHost() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final preferred = selectPreferredIpv4(
        interfaces
            .map((iface) => (name: iface.name, addresses: iface.addresses)),
      );
      if (preferred != null) return preferred;
    } on SocketException catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA media host detection failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
    }
    return InternetAddress.loopbackIPv4.address;
  }

  /// Selects the best LAN IPv4 address from [interfaces], avoiding VPN TUN/TAP
  /// and CGNAT addresses whenever a real LAN interface is available.
  static String? selectPreferredIpv4(
    Iterable<({String name, List<InternetAddress> addresses})> interfaces,
  ) {
    String? fallback;
    for (final interface in interfaces) {
      final virtualOrVpn = isVirtualOrTunnelInterface(interface.name);
      for (final address in interface.addresses) {
        if (address.type != InternetAddressType.IPv4) continue;
        final raw = address.rawAddress;
        if (raw.length != 4) continue;
        // Skip link-local 169.254.0.0/16 and loopback 127.0.0.0/8.
        if ((raw[0] == 169 && raw[1] == 254) || raw[0] == 127) continue;
        final isCgnat = raw[0] == 100 && (raw[1] & 0xc0) == 64;
        if (!virtualOrVpn && !isCgnat) return address.address;
        fallback ??= address.address;
      }
    }
    return fallback;
  }

  /// True for common VPN tunnel and container virtual interface names.
  static bool isVirtualOrTunnelInterface(String name) {
    final lower = name.trim().toLowerCase();
    return lower.startsWith('tun') ||
        lower.startsWith('tap') ||
        lower.startsWith('ppp') ||
        lower.startsWith('wg') ||
        lower.startsWith('utun') ||
        lower.startsWith('ipsec') ||
        lower.startsWith('tailscale') ||
        lower.startsWith('veth') ||
        lower.startsWith('docker') ||
        lower.startsWith('br-') ||
        lower.contains('vpn') ||
        lower.contains('proton') ||
        lower.contains('nordlynx');
  }

  static bool _isUnspecified(InternetAddress address) =>
      address.type == InternetAddressType.IPv4 &&
      address.rawAddress.every((byte) => byte == 0);

  static bool _isValidToken(String token) =>
      token.isNotEmpty &&
      token.length <= maxRequestPathLength &&
      _tokenPattern.hasMatch(token);
}

class _MediaEntry {
  _MediaEntry({
    required this.source,
    required this.expiresAt,
    required this.registeredAt,
  });

  final MediaSource source;
  DateTime expiresAt;

  /// When the token entered the registry; the LRU fallback for a never-read
  /// entry.
  final DateTime registeredAt;

  /// Last read, or `null` when the token was never requested.
  DateTime? lastAccess;

  /// Sort key for eviction: last read, else registration.
  DateTime get freshness => lastAccess ?? registeredAt;
}

enum _RangeStatus { none, satisfiable, unsatisfiable }

class _RangeOutcome {
  final _RangeStatus status;
  final int start;
  final int end;

  const _RangeOutcome.none()
      : status = _RangeStatus.none,
        start = 0,
        end = 0;

  const _RangeOutcome.unsatisfiable()
      : status = _RangeStatus.unsatisfiable,
        start = 0,
        end = 0;

  const _RangeOutcome.satisfiable(this.start, this.end)
      : status = _RangeStatus.satisfiable;
}
