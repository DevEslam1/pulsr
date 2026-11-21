// lib/features/dlna/ssdp_client.dart
//
// SSDP discovery for DLNA / UPnP MediaRenderers. Pure dart:io: one UDP socket
// bound to an ephemeral port sends M-SEARCH datagrams to the SSDP multicast
// group and collects unicast responses until the timeout expires.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/utils/error_logger.dart';

/// Creates the UDP socket used for discovery.
///
/// Tests inject a fake socket to drive [SsdpClient.search] without a network.
typedef SsdpSocketFactory = Future<RawDatagramSocket> Function();

/// A single `HTTP/1.1 200 OK` response to an SSDP M-SEARCH.
class SsdpResponse {
  /// Raw `LOCATION` header, usually an absolute URL to the device description.
  final String location;

  /// `ST` header (the search target the device answered for).
  final String searchTarget;

  /// `USN` header; identifies the device + service pair.
  final String usn;

  /// `SERVER` header (OS / UPnP stack version), may be empty.
  final String server;

  /// Advertised `CACHE-CONTROL: max-age` in seconds, when present.
  final int? maxAgeSeconds;

  /// IP address the datagram came from.
  final String sourceAddress;

  const SsdpResponse({
    required this.location,
    required this.searchTarget,
    required this.usn,
    required this.server,
    required this.sourceAddress,
    this.maxAgeSeconds,
  });

  /// Stable identity used to de-duplicate responses: USN, falling back to the
  /// description URL when a device omits USN.
  String get identity => usn.isNotEmpty ? usn : location;

  @override
  String toString() => 'SsdpResponse($identity -> $location)';
}

/// Minimal SSDP client: sends M-SEARCH for MediaRenderers and parses replies.
class SsdpClient {
  /// SSDP multicast group used by UPnP discovery.
  static const String multicastAddress = '239.255.255.250';

  /// SSDP discovery port.
  static const int multicastPort = 1900;

  /// Search targets sent by [search]: renderer- and server-specific first, then
  /// `ssdp:all` so devices that under-report their device type still answer.
  static const List<String> searchTargets = <String>[
    'urn:schemas-upnp-org:device:MediaRenderer:1',
    'urn:schemas-upnp-org:device:MediaServer:1',
    'ssdp:all',
  ];

  /// Value used for the `MX` header: maximum wait, in seconds, before a device
  /// replies. Kept below the default discovery timeout.
  static const int maxResponseDelaySeconds = 2;

  final SsdpSocketFactory _socketFactory;

  /// Creates a client. [socketFactory] is optional and exists for tests.
  SsdpClient({SsdpSocketFactory? socketFactory})
      : _socketFactory = socketFactory ?? _bindSocket;

  static Future<RawDatagramSocket> _bindSocket() =>
      RawDatagramSocket.bind(InternetAddress.anyIPv4, 0, reuseAddress: true);

  /// Sends M-SEARCH for every entry in [searchTargets] and returns the
  /// de-duplicated responses collected within [timeout].
  ///
  /// The socket is always closed before the future completes. Socket-level
  /// failures are logged and rethrown so the caller can surface them.
  Future<List<SsdpResponse>> search({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final responses = <String, SsdpResponse>{};
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? deadline;
    final finished = Completer<void>();

    try {
      socket = await _socketFactory();
      subscription = socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            _drain(socket!, responses);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          ErrorLogger.log(
            'SSDP socket error',
            error: error,
            stackTrace: stackTrace,
            category: 'DLNA',
          );
        },
      );

      // A test socket may already hold queued datagrams; draining once here
      // keeps search deterministic without changing real-device behaviour.
      _drain(socket, responses);
      for (final target in searchTargets) {
        _sendSearch(socket, target);
      }

      deadline = Timer(timeout, () {
        if (!finished.isCompleted) finished.complete();
      });
      await finished.future;
    } on SocketException catch (error, stackTrace) {
      ErrorLogger.log(
        'SSDP search failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
      rethrow;
    } finally {
      deadline?.cancel();
      await subscription?.cancel();
      socket?.close();
    }

    return responses.values.toList(growable: false);
  }

  void _sendSearch(RawDatagramSocket socket, String searchTarget) {
    final message = StringBuffer()
      ..write('M-SEARCH * HTTP/1.1\r\n')
      ..write('HOST: $multicastAddress:$multicastPort\r\n')
      ..write('MAN: "ssdp:discover"\r\n')
      ..write('MX: $maxResponseDelaySeconds\r\n')
      ..write('ST: $searchTarget\r\n')
      ..write('USER-AGENT: Pulsr/1.0 UPnP/1.1\r\n')
      ..write('\r\n');
    socket.send(
      utf8.encode(message.toString()),
      InternetAddress(multicastAddress),
      multicastPort,
    );
  }

  void _drain(RawDatagramSocket socket, Map<String, SsdpResponse> into) {
    while (true) {
      final datagram = socket.receive();
      if (datagram == null) return;
      final raw = utf8.decode(datagram.data, allowMalformed: true);
      final parsed = parseResponse(
        raw,
        sourceAddress: datagram.address.address,
      );
      if (parsed == null) continue;
      into.putIfAbsent(parsed.identity, () => parsed);
    }
  }

  /// Parses one raw SSDP reply. Returns `null` when it is not a usable
  /// `HTTP/1.1 200` response, when `LOCATION` is missing, non-HTTP(S), or
  /// points at a host that is neither the responder nor on the private LAN.
  ///
  /// Header names are matched case-insensitively and both CRLF and LF line
  /// endings are accepted. [sourceAddress] is the datagram sender and is
  /// recorded on the result for diagnostics.
  static SsdpResponse? parseResponse(
    String raw, {
    required String sourceAddress,
  }) {
    final lines = raw.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return null;

    // Only a successful search response may be consumed. NOTIFY, M-SEARCH and
    // error datagrams all share the SSDP port and must be ignored.
    if (!RegExp(r'^HTTP/1\.1\s+200(?:\s|$)').hasMatch(lines.first.trim())) {
      return null;
    }

    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final separator = trimmed.indexOf(':');
      if (separator <= 0) continue;
      final name = trimmed.substring(0, separator).trim().toLowerCase();
      final value = trimmed.substring(separator + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      headers.putIfAbsent(name, () => value);
    }

    final location = headers['location'];
    if (location == null || location.isEmpty) return null;

    final parsed = Uri.tryParse(location);
    if (parsed == null || !isAllowedDescriptionLocation(parsed, sourceAddress)) {
      return null;
    }

    return SsdpResponse(
      location: location,
      searchTarget: headers['st'] ?? '',
      usn: headers['usn'] ?? '',
      server: headers['server'] ?? '',
      maxAgeSeconds: _parseMaxAge(headers['cache-control']),
      sourceAddress: sourceAddress,
    );
  }

  /// True when [location] is an absolute http(s) URL whose host matches the
  /// responder [sourceAddress] or is on the same private LAN. Hostnames are
  /// rejected because they cannot be verified without a DNS lookup.
  static bool isAllowedDescriptionLocation(
    Uri location, [
    String? sourceAddress,
  ]) {
    final scheme = location.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    if (!location.hasAuthority || location.host.isEmpty) return false;

    final target = InternetAddress.tryParse(location.host);
    if (target == null) return false;

    if (sourceAddress == null || sourceAddress.isEmpty) {
      return _isPrivateOrLocal(target);
    }

    final source = InternetAddress.tryParse(sourceAddress);
    if (source != null && target.address == source.address) return true;
    if (target.isLoopback && (source == null || !source.isLoopback)) {
      return false;
    }
    return source != null &&
        _isPrivateOrLocal(source) &&
        _isPrivateOrLocal(target);
  }

  /// RFC 1918 / link-local / loopback IPv4 and ULA / link-local IPv6.
  static bool _isPrivateOrLocal(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 169 && bytes[1] == 254) ||
          bytes[0] == 127;
    }
    if (address.type == InternetAddressType.IPv6) {
      return (bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) ||
          bytes.every((byte) => byte == 0) ||
          (bytes.sublist(0, 15).every((byte) => byte == 0) && bytes[15] == 1);
    }
    return false;
  }

  static int? _parseMaxAge(String? cacheControl) {
    if (cacheControl == null || cacheControl.isEmpty) return null;
    final match = RegExp(r'max-age\s*=\s*(\d+)', caseSensitive: false)
        .firstMatch(cacheControl);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}
