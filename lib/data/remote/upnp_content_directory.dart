// lib/data/remote/upnp_content_directory.dart
//
// UPnP AV `ContentDirectory:1` control point: browses a media server's object
// tree, it does not render. A Browse action is a SOAP 1.1 POST to the service
// control URL; the response wraps a DIDL-Lite document in a `Result` element,
// escaped a second time, plus `NumberReturned` / `TotalMatches` for paging.
//
// Everything here is pure Dart over an injected `http.Client`, so the parsing
// and the exact bytes sent to a device are both testable without a server.
//
// Deliberate choices:
//   * XML is read with the small local-name parser below instead of adding a
//     dependency. Namespace prefixes are stripped before matching, so
//     `<dc:title>`, `<title>` and a default-namespaced `<title>` all work.
//   * Values are entity-decoded exactly once. Devices do emit bare `&`, so an
//     unknown entity is preserved instead of failing the whole page; a
//     structurally broken document (unclosed tag, mismatched close, trailing
//     junk) is a typed `UPNP_XML_MALFORMED` failure.
//   * Objects nested inside a container in the same payload are flattened in
//     document order and keep their own `parentID`.
//   * Resource URLs are never fetched here, so a `rtsp://` or `urn:` resource
//     is preserved verbatim and simply reports `isHttpResource == false`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/errors/app_error_base.dart';
import '../../core/network/remote_target_policy.dart';

/// Failure raised by the ContentDirectory control point.
///
/// [code] is stable and safe to branch on: `UPNP_TIMEOUT`, `UPNP_NETWORK_ERROR`,
/// `UPNP_HTTP_<status>`, `UPNP_UPNP_ERROR_<code>`, `UPNP_XML_MALFORMED`,
/// `UPNP_RESULT_TOO_LARGE`, `UPNP_CONTROL_URL_<verdict>`,
/// `UPNP_CONTROL_URL_CREDENTIALS`.
class UpnpBrowseError extends AppError {
  /// Numeric UPnP error code from a SOAP fault, e.g. `701`.
  final int? errorCode;

  /// `errorDescription` from the SOAP fault, when the device sent one.
  final String? errorDescription;

  /// Action that failed, e.g. `Browse`.
  final String? action;

  const UpnpBrowseError({
    required super.code,
    required super.userMessage,
    this.errorCode,
    this.errorDescription,
    this.action,
    super.cause,
    super.stackTrace,
  });
}

/// One DIDL-Lite object returned by Browse.
final class UpnpObject {
  /// `id` attribute; unique within the server's object tree.
  final String id;

  /// `parentID` attribute (empty when the device omitted it).
  final String parentId;

  /// `dc:title`, falling back to [id] when the device omitted it.
  final String title;

  /// `upnp:class`, e.g. `object.item.audioItem.musicTrack`.
  final String? upnpClass;

  /// `upnp:artist`, then `dc:creator`, then `upnp:albumArtist`.
  final String? artist;

  /// `upnp:album`.
  final String? album;

  /// Duration of the selected resource, when the device advertised one.
  final Duration? duration;

  /// Raw `res` text. May be `http(s)`, `rtsp`, `urn:` or a device-specific
  /// scheme; it is never fetched or rewritten here.
  final String? resourceUrl;

  /// `protocolInfo` of the selected resource, e.g.
  /// `http-get:*:audio/flac:*`.
  final String? protocolInfo;

  /// Declared resource size in bytes, when the device sent a `size`
  /// attribute. `null` means the size is unknown, so a byte window has no
  /// total to be validated against.
  final int? sizeBytes;

  /// True for `container` elements, false for `item` elements.
  final bool isContainer;

  /// `childCount` advertised on a container, when present.
  final int? childCount;

  const UpnpObject({
    required this.id,
    required this.parentId,
    required this.title,
    this.upnpClass,
    this.artist,
    this.album,
    this.duration,
    this.resourceUrl,
    this.protocolInfo,
    this.sizeBytes,
    this.isContainer = false,
    this.childCount,
  });

  /// True when the declared class is an audio item.
  bool get isAudioItem =>
      upnpClass?.startsWith('object.item.audioItem') ?? false;

  /// Parsed absolute resource URI, or null when absent/relative.
  Uri? get resourceUri {
    final raw = resourceUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.isEmpty) return null;
    return uri;
  }

  /// True when [resourceUrl] is an absolute `http`/`https` URI with a host.
  bool get isHttpResource {
    final uri = resourceUri;
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// HTTP resource URI that passes [RemoteTargetPolicy].
  ///
  /// A media server on the LAN necessarily serves from a private address, so
  /// the caller must opt in by listing the device host in
  /// [allowedHostSuffixes] (the policy treats an exact host as an allowlist
  /// entry). Returns null for non-HTTP resources, unresolvable hosts, loopback
  /// or unallowlisted private addresses.
  Uri? playableHttpUri({
    Set<String> allowedHostSuffixes = const {},
    bool requireHttps = false,
  }) {
    final uri = resourceUri;
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final verdict = RemoteTargetPolicy.classify(
      uri.toString(),
      requireHttps: requireHttps,
      allowedHostSuffixes: allowedHostSuffixes,
    );
    return verdict == RemoteTargetVerdict.allowed ? uri : null;
  }

  @override
  String toString() =>
      'UpnpObject(${isContainer ? 'container' : 'item'} $id "$title")';
}

/// One Browse page plus the counters needed to page further.
final class UpnpBrowseResult {
  /// Objects in document order, nested containers flattened.
  final List<UpnpObject> objects;

  /// `TotalMatches` as reported by the device. `0` means "unknown" in UPnP.
  final int totalMatches;

  /// `NumberReturned` as reported, defaulting to [objects] length.
  final int numberReturned;

  /// Index this page started at.
  final int startingIndex;

  /// Count that was requested, used to detect a short page.
  final int requestedCount;

  UpnpBrowseResult({
    required this.objects,
    this.totalMatches = 0,
    int? numberReturned,
    this.startingIndex = 0,
    this.requestedCount = 0,
  }) : numberReturned = numberReturned ?? objects.length;

  /// True when the device reported more objects after this page.
  bool get hasMore {
    if (objects.isEmpty || numberReturned <= 0) return false;
    if (totalMatches > 0) {
      return startingIndex + numberReturned < totalMatches;
    }
    return requestedCount > 0 && numberReturned >= requestedCount;
  }

  /// True when the page carried no objects.
  bool get isEmpty => objects.isEmpty;

  @override
  String toString() => 'UpnpBrowseResult(${objects.length} of $totalMatches '
      'from $startingIndex)';
}

/// Client for one device's `ContentDirectory:1` service.
final class UpnpContentDirectory {
  /// Service type used in `SOAPACTION` and the SOAP body namespace.
  static const String serviceType =
      'urn:schemas-upnp-org:service:ContentDirectory:1';

  /// Action name for Browse.
  static const String browseAction = 'Browse';

  /// `BrowseDirectChildren`: list the members of one container.
  static const String browseDirectChildren = 'BrowseDirectChildren';

  /// `BrowseMetadata`: read one object's own metadata.
  static const String browseMetadata = 'BrowseMetadata';

  /// Root container of every ContentDirectory.
  static const String rootObjectId = '0';

  /// Upper bound on a DIDL-Lite payload we are willing to parse.
  static const int maxPayloadBytes = 8 * 1024 * 1024;

  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  final Set<String> _allowedHostSuffixes;
  final bool _trustRequestHost;

  /// Creates a control point.
  ///
  /// [client] is injected in tests and optional in production; when omitted the
  /// instance creates and closes its own client. [allowedHostSuffixes] is the
  /// explicit LAN allowlist handed to [RemoteTargetPolicy] for control URLs.
  /// [trustRequestHost] accepts the host of the `controlUrl` passed to
  /// [browse] (the normal case: it came from an SSDP device description). Turn
  /// it off when the URL came from untrusted input.
  UpnpContentDirectory({
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
    Set<String> allowedHostSuffixes = const {},
    bool trustRequestHost = true,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _timeout = timeout,
        _allowedHostSuffixes = allowedHostSuffixes,
        _trustRequestHost = trustRequestHost;

  /// Releases the HTTP client when this instance created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Browses the direct children of [objectId].
  ///
  /// [start] and [count] are clamped to non-negative values; a [count] of `0`
  /// means "all remaining" on the wire, as UPnP defines it. Pass
  /// [browseMetadata] to read one object instead of its children.
  Future<UpnpBrowseResult> browse({
    required Uri controlUrl,
    String objectId = rootObjectId,
    int start = 0,
    int count = 200,
    String browseFlag = browseDirectChildren,
  }) async {
    final target = _validatedControlUrl(controlUrl);
    final safeStart = math.max(0, start);
    final safeCount = math.max(0, count);
    final envelope = buildBrowseEnvelope(
      objectId: objectId,
      startingIndex: safeStart,
      requestedCount: safeCount,
      browseFlag: browseFlag,
    );
    final body = await _invoke(target, browseAction, envelope);
    return parseBrowseResponse(
      body,
      startingIndex: safeStart,
      requestedCount: safeCount,
    );
  }

  /// Pages through [objectId] until `TotalMatches` (or a short page) ends it.
  ///
  /// [maxObjects] bounds memory for a server that never terminates paging;
  /// duplicates (same `id` and `parentID`) are dropped. Results preserve
  /// document order across pages.
  Future<List<UpnpObject>> browseAll({
    required Uri controlUrl,
    String objectId = rootObjectId,
    int pageSize = 200,
    int maxObjects = 5000,
  }) async {
    final safePage = math.max(1, pageSize);
    final safeMax = math.max(1, maxObjects);
    final objects = <UpnpObject>[];
    final seen = <String>{};
    final maxPages = math.max(64, (safeMax / safePage).ceil() * 4 + 8);
    var start = 0;

    for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
      if (objects.length >= safeMax) break;
      final count = math.min(safePage, safeMax - objects.length);
      final page = await browse(
        controlUrl: controlUrl,
        objectId: objectId,
        start: start,
        count: count,
      );
      for (final object in page.objects) {
        if (seen.add('${object.id}\u0000${object.parentId}')) {
          objects.add(object);
        }
      }
      if (page.objects.isEmpty || page.numberReturned <= 0) break;

      final advance = math.max(page.numberReturned, page.objects.length);
      final consumed = start + advance;
      if (page.totalMatches > 0 && consumed >= page.totalMatches) break;
      // A short page means the server has nothing more even if it did not
      // report TotalMatches.
      if (page.totalMatches == 0 && page.objects.length < count) break;
      start = consumed;
    }
    return objects;
  }

  Uri _validatedControlUrl(Uri controlUrl) {
    if (controlUrl.userInfo.isNotEmpty) {
      throw const UpnpBrowseError(
        code: 'UPNP_CONTROL_URL_CREDENTIALS',
        userMessage: 'The media server address must not embed credentials.',
        action: browseAction,
      );
    }
    final host = controlUrl.host;
    if (_isLoopbackOrLinkLocal(host)) {
      throw const UpnpBrowseError(
        code: 'UPNP_CONTROL_URL_PRIVATENETWORK',
        userMessage: 'The media server address is not allowed.',
        action: browseAction,
      );
    }
    final allowed = <String>{
      ..._allowedHostSuffixes,
      if (_trustRequestHost && host.isNotEmpty) host,
    };
    final verdict = RemoteTargetPolicy.classify(
      controlUrl.toString(),
      allowedHostSuffixes: allowed,
    );
    if (verdict != RemoteTargetVerdict.allowed) {
      throw UpnpBrowseError(
        code: 'UPNP_CONTROL_URL_${verdict.name.toUpperCase()}',
        userMessage: 'The media server address is not allowed.',
        action: browseAction,
      );
    }
    return controlUrl;
  }

  static bool _isLoopbackOrLinkLocal(String rawHost) {
    var lower = rawHost.trim().toLowerCase();
    if (lower.startsWith('[') && lower.endsWith(']')) {
      lower = lower.substring(1, lower.length - 1).trim();
    }
    final zoneIdx = lower.indexOf('%');
    if (zoneIdx != -1) lower = lower.substring(0, zoneIdx);
    if (lower.isEmpty) return true;
    if (lower == 'localhost' || lower.endsWith('.localhost')) return true;

    if (lower.contains(':')) {
      const loopbacks = {'::', '::1', '0:0:0:0:0:0:0:0', '0:0:0:0:0:0:0:1'};
      if (loopbacks.contains(lower)) return true;
      final embedded = RemoteTargetPolicy.embeddedIpv4(lower);
      if (embedded != null) {
        return _isLoopbackOrLinkLocalIpv4(embedded);
      }
      final firstGroup = lower.split(':').first;
      final value = int.tryParse(firstGroup, radix: 16);
      if (value != null) {
        if ((value & 0xffc0) == 0xfe80) return true; // fe80::/10 link-local
      }
      return false;
    }

    return _isLoopbackOrLinkLocalIpv4(lower);
  }

  static bool _isLoopbackOrLinkLocalIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
      octets.add(value);
    }
    final a = octets[0];
    final b = octets[1];
    if (a == 0) return true; // 0.0.0.0/8
    if (a == 127) return true; // 127.0.0.0/8 loopback
    if (a == 169 && b == 254) return true; // 169.254.0.0/16 link-local
    return false;
  }

  Future<String> _invoke(Uri controlUrl, String action, String envelope) async {
    final request = http.Request('POST', controlUrl)
      ..followRedirects = false
      ..headers['Content-Type'] = 'text/xml; charset="utf-8"'
      ..headers['SOAPACTION'] = soapAction(action)
      ..bodyBytes = utf8.encode(envelope);

    final http.StreamedResponse streamed;
    final Uint8List bodyBytes;
    try {
      streamed = await _client.send(request).timeout(_timeout);
      final limit = maxPayloadBytes * 2;
      final bytesBuilder = BytesBuilder(copy: false);
      var totalBytes = 0;
      await for (final chunk in streamed.stream.timeout(_timeout)) {
        totalBytes += chunk.length;
        if (totalBytes > limit) {
          throw UpnpBrowseError(
            code: 'UPNP_RESULT_TOO_LARGE',
            userMessage: 'The media server returned too much data.',
            action: action,
          );
        }
        bytesBuilder.add(chunk);
      }
      bodyBytes = bytesBuilder.takeBytes();
    } on TimeoutException catch (error, stackTrace) {
      throw UpnpBrowseError(
        code: 'UPNP_TIMEOUT',
        userMessage: 'The media server did not answer in time.',
        action: action,
        cause: error,
        stackTrace: stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      throw UpnpBrowseError(
        code: 'UPNP_NETWORK_ERROR',
        userMessage: 'Could not reach the media server.',
        action: action,
        cause: error,
        stackTrace: stackTrace,
      );
    } on http.ClientException catch (error, stackTrace) {
      throw UpnpBrowseError(
        code: 'UPNP_NETWORK_ERROR',
        userMessage: 'Could not reach the media server.',
        action: action,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    final body = utf8.decode(bodyBytes, allowMalformed: true);
    final fault = _faultFrom(body, action);
    if (streamed.statusCode != 200) {
      if (fault != null) throw fault;
      throw UpnpBrowseError(
        code: 'UPNP_HTTP_${streamed.statusCode}',
        userMessage: 'The media server rejected the browse request '
            '(HTTP ${streamed.statusCode}).',
        action: action,
      );
    }
    if (fault != null) throw fault;
    return body;
  }

  /// Builds the `SOAPACTION` header value, quotes included.
  static String soapAction(String action) => '"$serviceType#$action"';

  /// Wraps [arguments] in a SOAP 1.1 envelope for [action].
  static String buildSoapEnvelope({
    required String action,
    required String arguments,
  }) {
    return '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
        ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:$action xmlns:u="$serviceType">$arguments</u:$action>'
        '</s:Body>'
        '</s:Envelope>';
  }

  /// Builds the exact `Browse` request body.
  ///
  /// [objectId] and [sortCriteria] are entity-escaped: obfuscated container
  /// ids routinely contain `&`, `+` and quotes.
  static String buildBrowseEnvelope({
    required String objectId,
    int startingIndex = 0,
    int requestedCount = 200,
    String sortCriteria = '',
    String filter = '*',
    String browseFlag = browseDirectChildren,
  }) {
    return buildSoapEnvelope(
      action: browseAction,
      arguments: '<ObjectID>${escapeXml(objectId)}</ObjectID>'
          '<BrowseFlag>${escapeXml(browseFlag)}</BrowseFlag>'
          '<Filter>${escapeXml(filter)}</Filter>'
          '<StartingIndex>$startingIndex</StartingIndex>'
          '<RequestedCount>$requestedCount</RequestedCount>'
          '<SortCriteria>${escapeXml(sortCriteria)}</SortCriteria>',
    );
  }

  /// Parses a Browse SOAP response into a page.
  ///
  /// Throws [UpnpBrowseError] with `UPNP_XML_MALFORMED` when the SOAP body or
  /// the DIDL-Lite `Result` cannot be parsed.
  static UpnpBrowseResult parseBrowseResponse(
    String xml, {
    int startingIndex = 0,
    int requestedCount = 0,
  }) {
    final root = _parseXml(xml);
    final resultNode = _find(root, 'Result');
    if (resultNode == null) {
      throw const UpnpBrowseError(
        code: 'UPNP_BAD_RESPONSE',
        userMessage: 'The media server sent an unusable browse response.',
        action: browseAction,
      );
    }
    final didl = resultNode.text.trim();
    final objects = didl.isEmpty ? const <UpnpObject>[] : parseDidlLite(didl);
    return UpnpBrowseResult(
      objects: objects,
      totalMatches: _intText(root, 'TotalMatches') ?? 0,
      numberReturned: _intText(root, 'NumberReturned'),
      startingIndex: startingIndex,
      requestedCount: requestedCount,
    );
  }

  /// Parses a DIDL-Lite document (`<DIDL-Lite>…</DIDL-Lite>`) into objects.
  ///
  /// Nested containers are flattened in document order; objects without an
  /// `id` are skipped because they cannot be addressed by a later Browse.
  static List<UpnpObject> parseDidlLite(String xml) {
    if (xml.length > maxPayloadBytes) {
      throw const UpnpBrowseError(
        code: 'UPNP_RESULT_TOO_LARGE',
        userMessage: 'The media server returned too much data.',
      );
    }
    final root = _parseXml(xml);
    final objects = <UpnpObject>[];

    void collect(_XmlNode node) {
      for (final child in node.children) {
        if (child.name == 'item' || child.name == 'container') {
          final object = _objectFromNode(child);
          if (object != null) objects.add(object);
        }
        collect(child);
      }
    }

    if (root.name == 'item' || root.name == 'container') {
      final single = _objectFromNode(root);
      if (single != null) objects.add(single);
    }
    collect(root);
    return objects;
  }

  /// Escapes text for XML character data or an attribute value.
  static String escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// Parses `H:MM:SS[.mmm]`, `HH:MM:SS[.mmm]` or `MM:SS[.mmm]`.
  /// Returns null for placeholders such as `NOT_IMPLEMENTED`.
  static Duration? parseUpnpDuration(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final seconds = double.tryParse(parts.last);
    final minutes = int.tryParse(parts[parts.length - 2]);
    final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
    if (seconds == null ||
        minutes == null ||
        hours == null ||
        seconds < 0 ||
        minutes < 0 ||
        hours < 0) {
      return null;
    }
    final millis = (hours * 3600 + minutes * 60 + seconds) * 1000;
    if (!millis.isFinite || millis > 86400000000) return null;
    return Duration(milliseconds: millis.round());
  }

  /// Human-readable message for a UPnP error code.
  static String messageForErrorCode(int? errorCode) {
    switch (errorCode) {
      case 401:
        return 'The media server rejected the request.';
      case 402:
        return 'The media server reported invalid arguments.';
      case 501:
        return 'The media server does not support browsing.';
      case 701:
        return 'The media server does not have that object.';
      case 702:
        return 'The media server rejected an argument.';
      case 706:
        return 'The media server cannot provide that object.';
      case 708:
        return 'The media server rejected the sort criteria.';
      case 710:
        return 'The media server cannot find that container.';
      case 720:
        return 'The media server could not process the browse request.';
      case 721:
        return 'The media server does not support browsing that object.';
      default:
        return errorCode == null
            ? 'The media server reported an error.'
            : 'The media server reported error $errorCode.';
    }
  }

  static UpnpObject? _objectFromNode(_XmlNode node) {
    final id = (node.attributes['id'] ?? '').trim();
    if (id.isEmpty) return null;
    final resource = _selectResource(node);
    return UpnpObject(
      id: id,
      parentId:
          (node.attributes['parentID'] ?? node.attributes['parentId'] ?? '')
              .trim(),
      title: _childText(node, 'title') ?? id,
      upnpClass: _childText(node, 'class'),
      artist: _childText(node, 'artist') ??
          _childText(node, 'creator') ??
          _childText(node, 'albumArtist'),
      album: _childText(node, 'album'),
      duration: resource == null
          ? null
          : parseUpnpDuration(resource.attributes['duration']),
      resourceUrl: _resourceText(resource),
      protocolInfo: resource?.attributes['protocolInfo'],
      sizeBytes: int.tryParse(resource?.attributes['size'] ?? ''),
      isContainer: node.name == 'container',
      childCount: int.tryParse(node.attributes['childCount'] ?? ''),
    );
  }

  /// Prefers an HTTP audio resource, then any HTTP resource, then any audio
  /// resource, then the first resource, so the playable track wins over a
  /// device-specific companion entry.
  static _XmlNode? _selectResource(_XmlNode node) {
    final resources = node.children
        .where((child) => child.name == 'res' && child.text.trim().isNotEmpty)
        .toList(growable: false);
    if (resources.isEmpty) return null;
    for (final resource in resources) {
      final info = (resource.attributes['protocolInfo'] ?? '').toLowerCase();
      if (info.startsWith('http-get') && info.contains('audio/')) {
        return resource;
      }
    }
    for (final resource in resources) {
      final info = (resource.attributes['protocolInfo'] ?? '').toLowerCase();
      if (info.startsWith('http-get')) {
        return resource;
      }
    }
    for (final resource in resources) {
      final info = (resource.attributes['protocolInfo'] ?? '').toLowerCase();
      if (info.contains('audio/')) {
        return resource;
      }
    }
    return resources.first;
  }

  static String? _resourceText(_XmlNode? resource) {
    final raw = resource?.text.trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  static UpnpBrowseError? _faultFrom(String body, String action) {
    // A real fault carries `<Fault>` (optionally prefixed) and/or an
    // `errorCode`. A DIDL title containing the word is escaped in the raw body.
    final hasFaultTag =
        RegExp(r'<\s*(?:[A-Za-z_][\w.-]*:)?Fault(?:\s|>)').hasMatch(body);
    if (!hasFaultTag &&
        !RegExp(r'<\s*(?:[A-Za-z_][\w.-]*:)?errorCode\s*>').hasMatch(body)) {
      return null;
    }
    final _XmlNode root;
    try {
      root = _parseXml(body);
    } on UpnpBrowseError {
      // A non-XML error page: let the caller report the HTTP status.
      return null;
    }
    final fault = _find(root, 'Fault');
    final code = int.tryParse(_firstText(root, 'errorCode') ?? '');
    if (fault == null && code == null) return null;
    final description = _firstText(root, 'errorDescription');
    return UpnpBrowseError(
      code: code == null ? 'UPNP_UPNP_ERROR' : 'UPNP_UPNP_ERROR_$code',
      userMessage: messageForErrorCode(code),
      errorCode: code,
      errorDescription: description,
      action: action,
    );
  }

  static _XmlNode _parseXml(String xml) => _XmlParser(xml).parse();

  static _XmlNode? _find(_XmlNode node, String localName) {
    if (node.name == localName) return node;
    for (final child in node.children) {
      final match = _find(child, localName);
      if (match != null) return match;
    }
    return null;
  }

  static String? _firstText(_XmlNode root, String localName) {
    final text = _find(root, localName)?.text.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _intText(_XmlNode root, String localName) =>
      int.tryParse(_firstText(root, localName) ?? '');

  /// Reads a metadata element that is a *direct* child of [node], so a nested
  /// item's artist cannot leak into its parent container.
  static String? _childText(_XmlNode node, String localName) {
    for (final child in node.children) {
      if (child.name != localName) continue;
      final value = child.text.trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }
}

/// Minimal namespace-tolerant XML tree.
final class _XmlNode {
  _XmlNode(this.name);

  final String name;
  final Map<String, String> attributes = <String, String>{};
  final List<_XmlNode> children = <_XmlNode>[];
  final StringBuffer _text = StringBuffer();

  String get text => _text.toString();
}

/// Recursive-descent parser for the subset of XML a UPnP response uses.
///
/// Structural errors throw `UPNP_XML_MALFORMED`; entities are decoded once and
/// unknown ones are preserved literally (devices do emit bare `&`).
final class _XmlParser {
  _XmlParser(this._source);

  static const int _maxDepth = 64;

  final String _source;
  int _index = 0;

  _XmlNode parse() {
    if (_source.startsWith('\uFEFF')) _index = 1;
    _skipMisc();
    if (_index >= _source.length) _fail('empty document');
    final root = _parseElement(0);
    _skipMisc();
    if (_index < _source.length) _fail('trailing content');
    return root;
  }

  _XmlNode _parseElement(int depth) {
    if (depth > _maxDepth) _fail('nesting too deep');
    _expect('<');
    final rawName = _readName();
    final node = _XmlNode(_localName(rawName));
    final selfClosing = _readAttributes(node);
    if (selfClosing) return node;

    while (true) {
      if (_index >= _source.length) _fail('unterminated <$rawName>');
      if (_source.startsWith('</', _index)) {
        _index += 2;
        final closing = _readName();
        _skipWhitespace();
        _expect('>');
        if (_localName(closing) != node.name) {
          _fail('mismatched </$closing>');
        }
        return node;
      }
      if (_source.startsWith('<!--', _index)) {
        _skipUntil('-->');
        continue;
      }
      if (_source.startsWith('<![CDATA[', _index)) {
        _index += 9;
        final end = _source.indexOf(']]>', _index);
        if (end < 0) _fail('unterminated CDATA');
        node._text.write(_source.substring(_index, end));
        _index = end + 3;
        continue;
      }
      if (_source.startsWith('<?', _index)) {
        _skipUntil('?>');
        continue;
      }
      if (_source[_index] == '<') {
        node.children.add(_parseElement(depth + 1));
        continue;
      }
      final next = _source.indexOf('<', _index);
      final end = next < 0 ? _source.length : next;
      node._text.write(decodeEntities(_source.substring(_index, end)));
      _index = end;
    }
  }

  /// Reads attributes up to `>` or `/>`; returns true when self-closing.
  bool _readAttributes(_XmlNode node) {
    while (true) {
      _skipWhitespace();
      if (_source.startsWith('/>', _index)) {
        _index += 2;
        return true;
      }
      if (_index < _source.length && _source[_index] == '>') {
        _index++;
        return false;
      }
      final rawName = _readName();
      _skipWhitespace();
      _expect('=');
      _skipWhitespace();
      if (_index >= _source.length) _fail('unterminated attribute');
      final quote = _source[_index];
      if (quote != '"' && quote != "'") _fail('unquoted attribute');
      _index++;
      final end = _source.indexOf(quote, _index);
      if (end < 0) _fail('unterminated attribute');
      node.attributes[_localName(rawName)] =
          decodeEntities(_source.substring(_index, end));
      _index = end + 1;
    }
  }

  void _skipMisc() {
    while (true) {
      _skipWhitespace();
      if (_source.startsWith('<?', _index)) {
        _skipUntil('?>');
      } else if (_source.startsWith('<!--', _index)) {
        _skipUntil('-->');
      } else if (_isDoctypeAt(_index)) {
        _skipDeclaration();
      } else {
        return;
      }
    }
  }

  bool _isDoctypeAt(int index) {
    const keyword = '<!doctype';
    if (index + keyword.length > _source.length) return false;
    return _source.substring(index, index + keyword.length).toLowerCase() ==
        keyword;
  }

  /// Skips `<!DOCTYPE …>` including an internal subset in `[...]`.
  void _skipDeclaration() {
    var bracketDepth = 0;
    var quote = '';
    while (_index < _source.length) {
      final char = _source[_index];
      _index++;
      if (quote.isNotEmpty) {
        if (char == quote) quote = '';
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
      } else if (char == '[') {
        bracketDepth++;
      } else if (char == ']') {
        if (bracketDepth > 0) bracketDepth--;
      } else if (char == '>' && bracketDepth == 0) {
        return;
      }
    }
    _fail('unterminated declaration');
  }

  void _skipUntil(String marker) {
    final end = _source.indexOf(marker, _index);
    if (end < 0) _fail('unterminated $marker');
    _index = end + marker.length;
  }

  String _readName() {
    final start = _index;
    while (_index < _source.length && !_isNameTerminator(_source[_index])) {
      _index++;
    }
    if (_index == start) _fail('expected a name');
    return _source.substring(start, _index);
  }

  void _skipWhitespace() {
    while (_index < _source.length && _isWhitespace(_source[_index])) {
      _index++;
    }
  }

  void _expect(String char) {
    if (_index >= _source.length || _source[_index] != char) {
      _fail('expected "$char"');
    }
    _index++;
  }

  Never _fail(String reason) {
    throw UpnpBrowseError(
      code: 'UPNP_XML_MALFORMED',
      userMessage: 'The media server returned malformed XML.',
      cause: FormatException('$reason at byte $_index'),
    );
  }

  static bool _isWhitespace(String char) =>
      char == ' ' || char == '\t' || char == '\r' || char == '\n';

  static bool _isNameTerminator(String char) =>
      _isWhitespace(char) ||
      char == '<' ||
      char == '>' ||
      char == '/' ||
      char == '=' ||
      char == '"' ||
      char == "'";

  static String _localName(String rawName) {
    final colon = rawName.lastIndexOf(':');
    return colon < 0 ? rawName : rawName.substring(colon + 1);
  }

  /// Decodes `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&#NN;` and `&#xHH;`.
  /// Unknown or malformed references are preserved verbatim.
  static String decodeEntities(String raw) {
    if (!raw.contains('&')) return raw;
    return raw.replaceAllMapped(
      RegExp(r'&(#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);'),
      (match) {
        final token = match.group(1) ?? '';
        switch (token) {
          case 'amp':
            return '&';
          case 'lt':
            return '<';
          case 'gt':
            return '>';
          case 'quot':
            return '"';
          case 'apos':
            return "'";
        }
        final isHex = token.startsWith('#x') || token.startsWith('#X');
        final isDecimal = token.startsWith('#');
        if (!isHex && !isDecimal) return match.group(0)!;
        final code = int.tryParse(
          isHex ? token.substring(2) : token.substring(1),
          radix: isHex ? 16 : 10,
        );
        if (code == null || code < 0 || code > 0x10FFFF) {
          return match.group(0)!;
        }
        // Reject UTF-16 surrogates (0xD800–0xDFFF)
        if (code >= 0xD800 && code <= 0xDFFF) {
          return match.group(0)!;
        }
        // Reject illegal XML 1.0 control characters
        // Legal chars: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
        if (code < 0x20 && code != 0x9 && code != 0xA && code != 0xD) {
          return match.group(0)!;
        }
        return String.fromCharCode(code);
      },
    );
  }
}
