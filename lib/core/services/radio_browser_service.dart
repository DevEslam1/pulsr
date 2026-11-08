// lib/core/services/radio_browser_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/radio_station.dart';
import '../utils/error_logger.dart';

typedef HostLookup = Future<List<String>> Function(String host);

/// A live directory lookup backed by radio-browser.info.
///
/// The curated list in [RadioStationStore] is intentionally small; this service
/// lets the user search the public directory without shipping a snapshot. It
/// never trusts the directory's URLs: every candidate goes through
/// [RadioStation.isHttpUrl] (loopback / private / link-local rejected) before it
/// can become a station.
class RadioBrowserService {
  RadioBrowserService({
    http.Client? client,
    Uri? endpoint,
    List<Uri>? mirrors,
    HostLookup? hostLookup,
  })  : _client = client ?? http.Client(),
        _explicitEndpoint = endpoint,
        _mirrors = mirrors ?? defaultMirrors,
        _hostLookup = hostLookup;

  final http.Client _client;
  final Uri? _explicitEndpoint;
  final List<Uri> _mirrors;
  final HostLookup? _hostLookup;
  int _activeMirrorIndex = 0;

  static final List<Uri> defaultMirrors = [
    Uri.parse('https://de1.api.radio-browser.info/json/stations/search'),
    Uri.parse('https://nl1.api.radio-browser.info/json/stations/search'),
    Uri.parse('https://at1.api.radio-browser.info/json/stations/search'),
  ];

  /// The active search endpoint, prioritizing the explicit endpoint if provided,
  /// or the currently healthy mirror from [defaultMirrors].
  Uri get currentEndpoint =>
      _explicitEndpoint ?? _mirrors[_activeMirrorIndex % _mirrors.length];

  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _probeTimeout = Duration(seconds: 5);
  static const int _maxResults = 40;

  /// Executes an operation with automatic failover across registered mirrors.
  Future<T> _executeWithFallback<T>(
      Future<T> Function(Uri endpoint) operation) async {
    final explicit = _explicitEndpoint;
    if (explicit != null) {
      return await operation(explicit);
    }

    dynamic lastError;
    final total = _mirrors.length;
    final start = _activeMirrorIndex;

    for (var i = 0; i < total; i++) {
      final index = (start + i) % total;
      final mirror = _mirrors[index];
      try {
        final result = await operation(mirror);
        _activeMirrorIndex = index;
        return result;
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError is Exception) {
      throw lastError;
    }
    throw RadioBrowserException(
        'All radio mirrors failed: ${lastError?.toString() ?? 'unknown error'}');
  }

  /// Searches by name, optionally constrained by country code or tag.
  ///
  /// Automatically fails over across community mirrors if a mirror is down.
  /// Throws on transport/HTTP failure so the sheet can show a retry state;
  /// malformed individual rows are skipped rather than failing the whole page.
  Future<List<RadioStation>> search({
    String query = '',
    String? country,
    String? tag,
    int limit = _maxResults,
  }) async {
    return _executeWithFallback((endpoint) async {
      final params = <String, String>{
        'limit': '${limit.clamp(1, _maxResults)}',
        'hidebroken': 'true',
        'order': 'clickcount',
        'reverse': 'true',
      };
      final trimmed = query.trim();
      if (trimmed.isNotEmpty) params['name'] = trimmed;
      if (country != null && country.trim().isNotEmpty) {
        params['countrycode'] = country.trim().toUpperCase();
      }
      if (tag != null && tag.trim().isNotEmpty) {
        params['tag'] = tag.trim();
      }

      final uri = endpoint.replace(queryParameters: params);
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'Pulsr/1.0 (radio directory)'
      }).timeout(_timeout);

      if (response.statusCode != 200) {
        throw RadioBrowserException(
            'Directory returned HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const RadioBrowserException(
            'Directory returned an invalid payload');
      }

      final seen = <String>{};
      final stations = <RadioStation>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = item.cast<String, dynamic>();
        final url =
            (map['url_resolved'] ?? map['url'])?.toString().trim() ?? '';
        if (url.isEmpty || !RadioStation.isHttpUrl(url)) {
          continue;
        }
        if (!seen.add(url.toLowerCase())) continue;

        final name = (map['name'] ?? '').toString().trim();
        final tags = (map['tags'] ?? '').toString();
        final genre = tags
            .split(',')
            .map((t) => t.trim())
            .firstWhere((t) => t.isNotEmpty, orElse: () => '');
        final favicon = (map['favicon'] ?? '').toString().trim();
        final artwork = favicon.startsWith('http') ? favicon : null;
        final bitrate = (map['bitrate'] as num?)?.toInt();
        final codecRaw = (map['codec'] ?? '').toString().trim();
        final codec = codecRaw.isNotEmpty ? codecRaw.toUpperCase() : null;
        final stationUuid = (map['stationuuid'] ?? '').toString().trim();

        stations.add(RadioStation.create(
          name: name.isEmpty ? 'Radio station' : name,
          url: url,
          genre: genre.isEmpty ? null : genre,
          artworkUrl: artwork,
          bitrate: (bitrate != null && bitrate > 0) ? bitrate : null,
          codec: codec,
          stationUuid: stationUuid.isNotEmpty ? stationUuid : null,
        ));
        if (stations.length >= limit) break;
      }
      return List<RadioStation>.unmodifiable(stations);
    });
  }

  /// Casts a vote/rate for [stationUuid] on the active radio-browser mirror.
  ///
  /// Increments the station's vote count in the global directory. Returns true
  /// when the directory confirms the vote (`{"ok": true, ...}`).
  Future<bool> voteForStation(String stationUuid) async {
    final uuid = stationUuid.trim();
    if (uuid.isEmpty) return false;

    try {
      return await _executeWithFallback((endpoint) async {
        final uri = endpoint.replace(
          path: '/json/vote/$uuid',
          queryParameters: null,
        );
        final response = await _client.get(uri, headers: const {
          'User-Agent': 'Pulsr/1.0 (radio directory)'
        }).timeout(_timeout);

        if (response.statusCode != 200) {
          throw RadioBrowserException(
              'Vote returned HTTP ${response.statusCode}');
        }
        final decoded = jsonDecode(response.body);
        return decoded is Map && decoded['ok'] == true;
      });
    } catch (e, st) {
      ErrorLogger.log('Station vote failed',
          error: e, stackTrace: st, category: 'RadioBrowser');
      return false;
    }
  }

  /// Checks that [url] answers as a live stream before it is added to the
  /// user's list.
  ///
  /// Defends against DNS rebinding SSRF by resolving and verifying target IP
  /// addresses. Probes using `Range: bytes=0-0` to avoid downloading audio payloads,
  /// with automatic fallback to standard GET for servers rejecting byte ranges.
  Future<bool> isReachable(String url,
      {Duration timeout = _probeTimeout}) async {
    if (!RadioStation.isHttpUrl(url)) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    // Defense against DNS rebinding: verify host and resolved IP addresses
    final safeHost = await RadioStation.isSafeHost(
      uri.host,
      lookup: _hostLookup,
    );
    if (!safeHost) return false;

    // Primary probe: Ranged GET with ICY metadata (0 bytes audio consumed)
    try {
      final request = http.Request('GET', uri)
        ..headers['Icy-MetaData'] = '1'
        ..headers['Range'] = 'bytes=0-0'
        ..headers['User-Agent'] = 'Pulsr/1.0 (radio directory)';
      final response = await _client.send(request).timeout(timeout);
      final status = response.statusCode;
      await response.stream.listen((_) {}, onError: (_) {}).cancel();

      if (status >= 200 && status < 400) {
        return true;
      }

      // If server rejected byte-ranges (416 Range Not Satisfiable, 400 Bad Request,
      // 405 Method Not Allowed), execute fallback probe without Range header.
      if (status == 416 || status == 400 || status == 405) {
        return await _fallbackProbe(uri, timeout);
      }
      return false;
    } catch (e, st) {
      // If the ranged request was rejected at socket/transport level,
      // attempt fallback probe before declaring unreachable.
      final fallbackOk = await _fallbackProbe(uri, timeout);
      if (fallbackOk) return true;

      ErrorLogger.log('Radio stream probe failed',
          error: e, stackTrace: st, category: 'RadioBrowser');
      return false;
    }
  }

  /// Fallback probe without Range header for Icecast/HLS servers that reject byte ranges.
  /// Immediately cancels the stream subscription after reading the response headers.
  Future<bool> _fallbackProbe(Uri uri, Duration timeout) async {
    try {
      final request = http.Request('GET', uri)
        ..headers['Icy-MetaData'] = '1'
        ..headers['User-Agent'] = 'Pulsr/1.0 (radio directory)';
      final response = await _client.send(request).timeout(timeout);
      final ok = response.statusCode >= 200 && response.statusCode < 400;
      await response.stream.listen((_) {}, onError: (_) {}).cancel();
      return ok;
    } catch (_) {
      return false;
    }
  }
}

class RadioBrowserException implements Exception {
  const RadioBrowserException(this.message);

  final String message;

  @override
  String toString() => 'RadioBrowserException($message)';
}

/// Best-effort wrapper used by the UI: logs and returns an empty list.
Future<List<RadioStation>> searchRadioDirectorySafely(
  RadioBrowserService service, {
  String query = '',
  String? country,
  String? tag,
}) async {
  try {
    return await service.search(query: query, country: country, tag: tag);
  } catch (e, st) {
    ErrorLogger.log('Radio directory search failed',
        error: e, stackTrace: st, category: 'RadioBrowser');
    return const [];
  }
}
