// lib/features/remote_sources/upnp_discovery.dart
//
// P1-8 "network parity": find DLNA media servers on the LAN.
//
// Playback uses the existing [SsdpClient] M-SEARCH socket; this class only adds
// the second half of discovery, which the renderer path never needed: fetching
// each `LOCATION` description and keeping the ones that expose a
// ContentDirectory service. Renderers and routers answer `ssdp:all` too, so a
// description without that service is an ordinary miss rather than an error.
//
// Every collaborator is injectable: the search is a plain function in tests (no
// UDP socket) and the description fetches go through an injected `http.Client`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/utils/error_logger.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../dlna/ssdp_client.dart';
import '../dlna/upnp_device.dart';

/// Runs one SSDP search and returns the raw replies.
typedef SsdpSearch = Future<List<SsdpResponse>> Function(Duration timeout);

/// Finds UPnP `MediaServer:1` devices and their ContentDirectory control URLs.
class UpnpDiscovery {
  /// Largest device description accepted, matching the renderer path.
  static const int maxDescriptionBytes = 256 * 1024;

  /// Creates a discovery helper.
  ///
  /// [search] replaces the SSDP round trip in tests; [client] replaces the HTTP
  /// transport. [ssdp] is only used when [search] is omitted.
  UpnpDiscovery({
    SsdpClient? ssdp,
    SsdpSearch? search,
    http.Client? client,
    Duration searchTimeout = const Duration(seconds: 3),
    Duration descriptionTimeout = const Duration(seconds: 4),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _searchTimeout = searchTimeout,
        _descriptionTimeout = descriptionTimeout {
    final ssdpClient = ssdp ?? SsdpClient();
    _search = search ?? (timeout) => ssdpClient.search(timeout: timeout);
  }

  final http.Client _client;
  final bool _ownsClient;
  final Duration _searchTimeout;
  final Duration _descriptionTimeout;
  late final SsdpSearch _search;

  /// Searches the LAN and returns the media servers that answered, by name.
  ///
  /// Throws [RemoteUnavailableError] when the SSDP socket itself cannot be
  /// opened; a device whose description cannot be fetched or parsed is skipped
  /// (it may be a renderer, a router or a sleeping NAS).
  Future<List<UpnpServerDescription>> discover() async {
    final List<SsdpResponse> responses;
    try {
      responses = await _search(_searchTimeout);
    } on SocketException catch (e, st) {
      ErrorLogger.log(
        'UPnP discovery socket failed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      throw RemoteUnavailableError(
        code: 'UPNP_DISCOVERY_FAILED',
        userMessage: 'Media servers could not be searched for. Check that '
            'this device is on the same network.',
        cause: e,
        stackTrace: st,
      );
    }

    final locations = <Uri>[];
    for (final response in responses) {
      final location = _locationOf(response);
      if (location != null && !locations.contains(location)) {
        locations.add(location);
      }
    }

    final descriptions = await Future.wait(locations.map(_fetchDescription));
    final byIdentity = <String, UpnpServerDescription>{};
    final controlUrls = <String>{};
    for (final description in descriptions) {
      if (description == null) continue;
      final control = description.contentDirectoryControlUrl.toString();
      if (!controlUrls.add(control)) continue;
      byIdentity.putIfAbsent(description.identity, () => description);
    }

    final servers = byIdentity.values.toList(growable: false)
      ..sort(
        (a, b) => a.friendlyName
            .toLowerCase()
            .compareTo(b.friendlyName.toLowerCase()),
      );
    return servers;
  }

  /// Releases the HTTP client this instance created.
  void close() {
    if (_ownsClient) _client.close();
  }

  static Uri? _locationOf(SsdpResponse response) {
    final parsed = Uri.tryParse(response.location);
    if (parsed == null) return null;
    if (!SsdpClient.isAllowedDescriptionLocation(
      parsed,
      response.sourceAddress,
    )) {
      return null;
    }
    return parsed;
  }

  Future<UpnpServerDescription?> _fetchDescription(Uri location) async {
    try {
      final request = http.Request('GET', location)..followRedirects = false;
      final streamed = await _client.send(request).timeout(_descriptionTimeout);
      if (streamed.statusCode != HttpStatus.ok) {
        await _discard(streamed.stream);
        return null;
      }

      final declaredLength = streamed.contentLength;
      if (declaredLength != null && declaredLength > maxDescriptionBytes) {
        await _discard(streamed.stream);
        return null;
      }

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream.timeout(_descriptionTimeout)) {
        if (bytes.length + chunk.length > maxDescriptionBytes) return null;
        bytes.add(chunk);
      }

      final body = utf8.decode(bytes.takeBytes(), allowMalformed: true);
      final description = UpnpServerDescription.parse(body, location: location);
      final scheme = description.contentDirectoryControlUrl.scheme;
      if (scheme != 'http' && scheme != 'https') return null;
      if (description.contentDirectoryControlUrl.host.isEmpty) return null;
      return description;
    } on UpnpParseError {
      // A renderer, a router or any other device that answered ssdp:all.
      return null;
    } catch (e, st) {
      ErrorLogger.log(
        'UPnP description fetch failed for $location',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      return null;
    }
  }

  static Future<void> _discard(Stream<List<int>> stream) async {
    try {
      await stream.drain<void>();
    } on Object {
      // The body is being thrown away; a failed drain has no consequence.
    }
  }
}
