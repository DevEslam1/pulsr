// lib/features/dlna/upnp_device_description_cache.dart
//
// In-memory TTL cache for UPnP / DLNA device description XML and parsed
// descriptions, avoiding redundant HTTP GETs during SSDP scans and browsing.
//
// Features:
// - Bounded memory cache with LRU eviction.
// - Configurable time-to-live (TTL, default 5 minutes).
// - Single-flight request coalescing for concurrent fetches to the same URL.
// - Size limit enforcement on description XML (256 KB max).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/utils/error_logger.dart';
import 'upnp_device.dart';

/// Entry in the description cache with a timestamp.
class _CacheEntry<T> {
  final T value;
  final DateTime cachedAt;
  final int seq;

  const _CacheEntry(this.value, this.cachedAt, this.seq);

  bool isFresh(Duration ttl, DateTime now) =>
      now.difference(cachedAt) < ttl;
}

/// Cache for UPnP device description documents and parsed descriptions.
class UpnpDeviceDescriptionCache {
  /// Maximum document size accepted from a device (256 KB).
  static const int maxDescriptionBytes = 256 * 1024;

  /// Default time-to-live for cached descriptions.
  static const Duration defaultTtl = Duration(minutes: 5);

  /// Default capacity limit.
  static const int defaultMaxEntries = 100;

  /// Global shared instance.
  static final UpnpDeviceDescriptionCache shared =
      UpnpDeviceDescriptionCache();

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _clock;
  int _sequence = 0;

  final Map<Uri, _CacheEntry<String>> _xmlCache = {};
  final Map<Uri, _CacheEntry<UpnpDeviceDescription>> _deviceCache = {};
  final Map<Uri, _CacheEntry<UpnpServerDescription>> _serverCache = {};
  final Map<Uri, Future<String?>> _inFlight = {};

  UpnpDeviceDescriptionCache({
    this.ttl = defaultTtl,
    this.maxEntries = defaultMaxEntries,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Retrieves cached XML for [location] or fetches it over HTTP.
  Future<String?> getOrFetchXml(
    Uri location, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final now = _clock();
    final cached = _xmlCache[location];
    if (cached != null && cached.isFresh(ttl, now)) {
      // True LRU: update recency sequence on hit (§8.5)
      _xmlCache[location] = _CacheEntry(cached.value, cached.cachedAt, ++_sequence);
      return cached.value;
    }

    // Coalesce concurrent fetches to the same location.
    final inFlight = _inFlight[location];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _fetchXml(location, client: client, timeout: timeout);
    _inFlight[location] = future;
    try {
      final xml = await future;
      if (xml != null) {
        putXml(location, xml);
      }
      return xml;
    } finally {
      _inFlight.remove(location);
    }
  }

  /// Retrieves or fetches and parses a [UpnpDeviceDescription] for [location].
  Future<UpnpDeviceDescription?> getOrFetchDeviceDescription(
    Uri location, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final now = _clock();
    final cached = _deviceCache[location];
    if (cached != null && cached.isFresh(ttl, now)) {
      _deviceCache[location] = _CacheEntry(cached.value, cached.cachedAt, ++_sequence);
      return cached.value;
    }

    final xml = await getOrFetchXml(location, client: client, timeout: timeout);
    if (xml == null) return null;

    try {
      final description = UpnpDeviceDescription.parse(xml, location: location);
      _putDevice(location, description);
      return description;
    } on UpnpParseError catch (e, st) {
      ErrorLogger.log(
        'DLNA description parse rejected for $location',
        error: e,
        stackTrace: st,
        category: 'DLNA',
      );
      return null;
    } catch (e, st) {
      ErrorLogger.log(
        'DLNA description parse error for $location',
        error: e,
        stackTrace: st,
        category: 'DLNA',
      );
      return null;
    }
  }

  /// Retrieves or fetches and parses a [UpnpServerDescription] for [location].
  Future<UpnpServerDescription?> getOrFetchServerDescription(
    Uri location, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final now = _clock();
    final cached = _serverCache[location];
    if (cached != null && cached.isFresh(ttl, now)) {
      _serverCache[location] = _CacheEntry(cached.value, cached.cachedAt, ++_sequence);
      return cached.value;
    }

    final xml = await getOrFetchXml(location, client: client, timeout: timeout);
    if (xml == null) return null;

    try {
      final description = UpnpServerDescription.parse(xml, location: location);
      _putServer(location, description);
      return description;
    } on UpnpParseError catch (e, st) {
      ErrorLogger.log(
        'UPnP server description parse rejected for $location',
        error: e,
        stackTrace: st,
        category: 'DLNA',
      );
      return null;
    } catch (e, st) {
      ErrorLogger.log(
        'UPnP server description parse error for $location',
        error: e,
        stackTrace: st,
        category: 'DLNA',
      );
      return null;
    }
  }

  /// Manually populates the cache with [xml] for [location].
  void putXml(Uri location, String xml) {
    _evictOldestIfNeeded(_xmlCache);
    _xmlCache[location] = _CacheEntry(xml, _clock(), ++_sequence);
  }

  void _putDevice(Uri location, UpnpDeviceDescription device) {
    _evictOldestIfNeeded(_deviceCache);
    _deviceCache[location] = _CacheEntry(device, _clock(), ++_sequence);
  }

  void _putServer(Uri location, UpnpServerDescription server) {
    _evictOldestIfNeeded(_serverCache);
    _serverCache[location] = _CacheEntry(server, _clock(), ++_sequence);
  }

  /// Invalidates cached entries for [location].
  void invalidate(Uri location) {
    _xmlCache.remove(location);
    _deviceCache.remove(location);
    _serverCache.remove(location);
  }

  /// Clears all entries from the cache.
  void clear() {
    _xmlCache.clear();
    _deviceCache.clear();
    _serverCache.clear();
    _inFlight.clear();
  }

  /// Returns true if a fresh XML entry exists for [location].
  bool contains(Uri location) {
    final entry = _xmlCache[location];
    return entry != null && entry.isFresh(ttl, _clock());
  }

  Future<String?> _fetchXml(
    Uri location, {
    http.Client? client,
    required Duration timeout,
  }) async {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      final request = http.Request('GET', location)..followRedirects = false;
      final streamed = await httpClient.send(request).timeout(timeout);
      if (streamed.statusCode != HttpStatus.ok) {
        await _discardBody(streamed.stream, timeout);
        ErrorLogger.log(
          'UPnP description returned HTTP ${streamed.statusCode} for $location',
          category: 'DLNA',
        );
        return null;
      }

      final declaredLength = streamed.contentLength;
      if (declaredLength != null && declaredLength > maxDescriptionBytes) {
        await _discardBody(streamed.stream, timeout);
        ErrorLogger.log(
          'UPnP description for $location is too large ($declaredLength bytes)',
          category: 'DLNA',
        );
        return null;
      }

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream.timeout(timeout)) {
        if (bytes.length + chunk.length > maxDescriptionBytes) {
          ErrorLogger.log(
            'UPnP description for $location exceeded $maxDescriptionBytes bytes',
            category: 'DLNA',
          );
          return null;
        }
        bytes.add(chunk);
      }

      return utf8.decode(bytes.takeBytes(), allowMalformed: true);
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'UPnP description fetch failed for $location',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
      return null;
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  Future<void> _discardBody(Stream<List<int>> stream, Duration timeout) async {
    try {
      await stream.drain<void>().timeout(timeout);
    } catch (_) {}
  }

  void _evictOldestIfNeeded<T>(Map<Uri, _CacheEntry<T>> map) {
    if (map.length >= maxEntries) {
      final oldestKey = map.entries
          .reduce((a, b) => a.value.seq < b.value.seq ? a : b)
          .key;
      map.remove(oldestKey);
    }
  }
}
