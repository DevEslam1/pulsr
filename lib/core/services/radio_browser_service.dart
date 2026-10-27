// lib/core/services/radio_browser_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/radio_station.dart';
import '../utils/error_logger.dart';

/// A live directory lookup backed by radio-browser.info.
///
/// The curated list in [RadioStationStore] is intentionally small; this service
/// lets the user search the public directory without shipping a snapshot. It
/// never trusts the directory's URLs: every candidate goes through
/// [RadioStation.isHttpUrl] (loopback / private / link-local rejected) before it
/// can become a station.
class RadioBrowserService {
  RadioBrowserService({http.Client? client, Uri? endpoint})
      : _client = client ?? http.Client(),
        _endpoint = endpoint ??
            Uri.parse(
                'https://de1.api.radio-browser.info/json/stations/search');

  final http.Client _client;
  final Uri _endpoint;

  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _probeTimeout = Duration(seconds: 5);
  static const int _maxResults = 40;

  /// Searches by name, optionally constrained by country code or tag.
  ///
  /// Throws on transport/HTTP failure so the sheet can show a retry state;
  /// malformed individual rows are skipped rather than failing the whole page.
  Future<List<RadioStation>> search({
    String query = '',
    String? country,
    String? tag,
    int limit = _maxResults,
  }) async {
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

    final uri = _endpoint.replace(queryParameters: params);
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
      final url = (map['url_resolved'] ?? map['url'])?.toString().trim() ?? '';
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

      stations.add(RadioStation.create(
        name: name.isEmpty ? 'Radio station' : name,
        url: url,
        genre: genre.isEmpty ? null : genre,
        artworkUrl: artwork,
      ));
      if (stations.length >= limit) break;
    }
    return List<RadioStation>.unmodifiable(stations);
  }

  /// Checks that [url] answers as a live stream before it is added to the
  /// user's list.
  ///
  /// Directory entries go stale: a station that answered when the snapshot was
  /// taken can now be a parked domain or an HTTP error page. A ranged GET asks
  /// for one byte, so a healthy Icecast/Shoutcast server answers immediately
  /// without downloading audio. Only 2xx/3xx count; a 4xx/5xx page means the
  /// URL is not a stream. The body is never read — the subscription is
  /// cancelled after the headers arrive.
  Future<bool> isReachable(String url,
      {Duration timeout = _probeTimeout}) async {
    if (!RadioStation.isHttpUrl(url)) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    http.StreamedResponse? response;
    try {
      final request = http.Request('GET', uri)
        ..headers['Icy-MetaData'] = '1'
        ..headers['Range'] = 'bytes=0-0'
        ..headers['User-Agent'] = 'Pulsr/1.0 (radio directory)';
      response = await _client.send(request).timeout(timeout);
      final ok = response.statusCode >= 200 && response.statusCode < 400;
      // Free the socket without waiting for audio; cancellation is enough to
      // close a chunked stream.
      await response.stream.listen((_) {}, onError: (_) {}).cancel();
      return ok;
    } catch (e, st) {
      ErrorLogger.log('Radio stream probe failed',
          error: e, stackTrace: st, category: 'RadioBrowser');
      // Any transport or HTTP failure counts as unreachable. Some Icecast
      // servers reject ranged probes; the user can still add such a station by
      // pasting its URL, which is validated separately.
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
