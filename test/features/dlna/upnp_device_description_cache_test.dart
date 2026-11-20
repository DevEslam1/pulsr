// Unit tests for UpnpDeviceDescriptionCache: TTL, single-flight coalescing,
// XML parsing, LRU capacity bounds, and manual invalidation.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pulsr/features/dlna/upnp_device_description_cache.dart';

const String _rendererXml = '<?xml version="1.0"?><root><device>'
    '<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>'
    '<friendlyName>Living Room Speaker</friendlyName>'
    '<serviceList><service>'
    '<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>'
    '<controlURL>/control/avt</controlURL>'
    '</service></serviceList>'
    '</device></root>';

const String _serverXml = '<?xml version="1.0"?><root><device>'
    '<deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>'
    '<friendlyName>NAS Music</friendlyName>'
    '<serviceList><service>'
    '<serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>'
    '<controlURL>/control/cds</controlURL>'
    '</service></serviceList>'
    '</device></root>';

class _CountingClient extends http.BaseClient {
  _CountingClient(this.handler);

  final Future<http.StreamedResponse> Function(http.Request request) handler;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requestCount++;
    return handler(request as http.Request);
  }
}

http.StreamedResponse _xmlResponse(String xml, {int status = 200}) {
  final bytes = utf8.encode(xml);
  return http.StreamedResponse(
    Stream.value(bytes),
    status,
    headers: {
      HttpHeaders.contentTypeHeader: 'text/xml; charset=utf-8',
      HttpHeaders.contentLengthHeader: bytes.length.toString(),
    },
  );
}

void main() {
  final uri1 = Uri.parse('http://192.168.1.50:8080/desc.xml');
  final uri2 = Uri.parse('http://192.168.1.51:8080/desc.xml');

  group('UpnpDeviceDescriptionCache', () {
    test('fetches once and caches subsequent requests within TTL', () async {
      final client = _CountingClient((_) async => _xmlResponse(_rendererXml));
      var fakeNow = DateTime(2026, 1, 1, 12, 0);
      final cache = UpnpDeviceDescriptionCache(
        ttl: const Duration(minutes: 5),
        clock: () => fakeNow,
      );

      final first = await cache.getOrFetchDeviceDescription(uri1, client: client);
      expect(first, isNotNull);
      expect(first!.friendlyName, 'Living Room Speaker');
      expect(client.requestCount, 1);

      // Advance time by 2 minutes (still within 5 minute TTL)
      fakeNow = fakeNow.add(const Duration(minutes: 2));

      final second = await cache.getOrFetchDeviceDescription(uri1, client: client);
      expect(second, isNotNull);
      expect(second!.friendlyName, 'Living Room Speaker');
      expect(client.requestCount, 1); // No new network request
    });

    test('re-fetches when TTL expires', () async {
      final client = _CountingClient((_) async => _xmlResponse(_rendererXml));
      var fakeNow = DateTime(2026, 1, 1, 12, 0);
      final cache = UpnpDeviceDescriptionCache(
        ttl: const Duration(minutes: 5),
        clock: () => fakeNow,
      );

      await cache.getOrFetchDeviceDescription(uri1, client: client);
      expect(client.requestCount, 1);

      // Advance past TTL (6 minutes)
      fakeNow = fakeNow.add(const Duration(minutes: 6));

      await cache.getOrFetchDeviceDescription(uri1, client: client);
      expect(client.requestCount, 2);
    });

    test('coalesces concurrent requests to the same location (single-flight)',
        () async {
      final completer = Completer<http.StreamedResponse>();
      final client = _CountingClient((_) => completer.future);
      final cache = UpnpDeviceDescriptionCache();

      // Launch 3 simultaneous requests for the same URI
      final future1 = cache.getOrFetchXml(uri1, client: client);
      final future2 = cache.getOrFetchXml(uri1, client: client);
      final future3 = cache.getOrFetchXml(uri1, client: client);

      completer.complete(_xmlResponse(_rendererXml));

      final results = await Future.wait([future1, future2, future3]);
      expect(results[0], _rendererXml);
      expect(results[1], _rendererXml);
      expect(results[2], _rendererXml);
      expect(client.requestCount, 1);
    });

    test('parses and caches UpnpServerDescription', () async {
      final client = _CountingClient((_) async => _xmlResponse(_serverXml));
      final cache = UpnpDeviceDescriptionCache();

      final server = await cache.getOrFetchServerDescription(uri2, client: client);
      expect(server, isNotNull);
      expect(server!.friendlyName, 'NAS Music');
      expect(server.contentDirectoryControlUrl,
          Uri.parse('http://192.168.1.51:8080/control/cds'));
    });

    test('manual putXml, invalidate, and clear work correctly', () async {
      final cache = UpnpDeviceDescriptionCache();

      cache.putXml(uri1, _rendererXml);
      expect(cache.contains(uri1), isTrue);

      final desc = await cache.getOrFetchDeviceDescription(uri1);
      expect(desc?.friendlyName, 'Living Room Speaker');

      cache.invalidate(uri1);
      expect(cache.contains(uri1), isFalse);

      cache.putXml(uri1, _rendererXml);
      cache.clear();
      expect(cache.contains(uri1), isFalse);
    });

    test('enforces maxEntries LRU eviction', () async {
      final cache = UpnpDeviceDescriptionCache(maxEntries: 2);
      final u1 = Uri.parse('http://1.1.1.1/d.xml');
      final u2 = Uri.parse('http://1.1.1.2/d.xml');
      final u3 = Uri.parse('http://1.1.1.3/d.xml');

      cache.putXml(u1, 'xml1');
      cache.putXml(u2, 'xml2');
      expect(cache.contains(u1), isTrue);
      expect(cache.contains(u2), isTrue);

      // Adding 3rd should evict the oldest (u1)
      cache.putXml(u3, 'xml3');
      expect(cache.contains(u1), isFalse);
      expect(cache.contains(u2), isTrue);
      expect(cache.contains(u3), isTrue);
    });

    test('accessing entry updates recency and protects it from LRU eviction', () async {
      final cache = UpnpDeviceDescriptionCache(maxEntries: 2);
      final u1 = Uri.parse('http://1.1.1.1/d.xml');
      final u2 = Uri.parse('http://1.1.1.2/d.xml');
      final u3 = Uri.parse('http://1.1.1.3/d.xml');

      cache.putXml(u1, _rendererXml);
      cache.putXml(u2, _serverXml);

      // Read u1 to update its recency (making u2 the least recently used)
      final desc = await cache.getOrFetchDeviceDescription(u1);
      expect(desc, isNotNull);

      // Inserting u3 should now evict u2 (the LRU entry), NOT u1
      cache.putXml(u3, 'xml3');
      expect(cache.contains(u1), isTrue);
      expect(cache.contains(u2), isFalse);
      expect(cache.contains(u3), isTrue);
    });

    test('rejects responses exceeding maxDescriptionBytes', () async {
      final oversized = 'x' * (UpnpDeviceDescriptionCache.maxDescriptionBytes + 1);
      final client = _CountingClient((_) async => _xmlResponse(oversized));
      final cache = UpnpDeviceDescriptionCache();

      final result = await cache.getOrFetchXml(uri1, client: client);
      expect(result, isNull);
    });
  });
}
