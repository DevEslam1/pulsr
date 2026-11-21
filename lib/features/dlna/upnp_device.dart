// lib/features/dlna/upnp_device.dart
//
// Parser for UPnP device description documents. Namespace prefixes are
// stripped before reading elements, so the parser accepts both
// `<friendlyName>` and `<s:friendlyName>` shapes from real-world devices.
import '../../core/errors/app_error_base.dart';
import 'ssdp_client.dart';
import 'upnp_entities.dart';

/// Raised when a device description cannot be used as a DLNA renderer.
class UpnpParseError extends AppError {
  /// Creates a parse error. [code] is stable and safe to branch on.
  const UpnpParseError({
    required super.code,
    required super.userMessage,
    super.cause,
    super.stackTrace,
  });
}

/// The subset of a UPnP description Pulsr needs to drive a MediaRenderer.
class UpnpDeviceDescription {
  /// Human-readable device name (`friendlyName`).
  final String friendlyName;

  /// `modelName`, when advertised.
  final String? modelName;

  /// `manufacturer`, when advertised.
  final String? manufacturer;

  /// Unique device name (`UDN`), e.g. `uuid:...`.
  final String? udn;

  /// Declared device type, e.g. `urn:schemas-upnp-org:device:MediaRenderer:1`.
  final String? deviceType;

  /// Absolute URL the description was fetched from.
  final Uri location;

  /// Absolute control URL of the device's AVTransport service.
  final Uri avTransportControlUrl;

  const UpnpDeviceDescription({
    required this.friendlyName,
    required this.location,
    required this.avTransportControlUrl,
    this.modelName,
    this.manufacturer,
    this.udn,
    this.deviceType,
  });

  /// Stable identity for selection and de-duplication.
  String get identity {
    final unique = udn;
    return unique == null || unique.isEmpty
        ? avTransportControlUrl.toString()
        : unique;
  }

  /// True when the device declares itself a MediaRenderer.
  bool get isMediaRenderer => deviceType?.contains('MediaRenderer') ?? false;

  /// Parses [xml] fetched from [location].
  ///
  /// Relative `controlURL` values are resolved against an advertised
  /// `URLBase` when present, otherwise against [location]. When several
  /// services exist, the AVTransport one is selected.
  ///
  /// Throws [UpnpParseError] when the document has no `friendlyName` or no
  /// usable AVTransport `controlURL`.
  static UpnpDeviceDescription parse(String xml, {required Uri location}) {
    if (xml.trim().isEmpty) {
      throw const UpnpParseError(
        code: 'DLNA_EMPTY_DESCRIPTION',
        userMessage: 'The device returned an empty description.',
      );
    }

    final document = _stripNamespacePrefixes(xml);
    final friendlyName = _elementText(document, 'friendlyName');
    if (friendlyName == null || friendlyName.isEmpty) {
      throw const UpnpParseError(
        code: 'DLNA_FRIENDLY_NAME',
        userMessage: 'The device description has no name.',
      );
    }

    final base = _resolveBase(document, location);
    final service = _selectAvTransportService(
      document,
      base: base,
      sourceAddress: location.host,
    );
    final controlUrl = service?.controlUrl ?? '';
    if (controlUrl.isEmpty) {
      throw const UpnpParseError(
        code: 'DLNA_CONTROL_URL',
        userMessage: 'The device does not expose an AVTransport control URL.',
      );
    }

    final resolvedControl = Uri.parse(controlUrl);
    if (!SsdpClient.isAllowedDescriptionLocation(resolvedControl, location.host)) {
      throw const UpnpParseError(
        code: 'DLNA_CONTROL_URL_DISALLOWED',
        userMessage: 'The AVTransport control URL points to a disallowed location.',
      );
    }

    return UpnpDeviceDescription(
      friendlyName: friendlyName,
      modelName: _emptyToNull(_elementText(document, 'modelName')),
      manufacturer: _emptyToNull(_elementText(document, 'manufacturer')),
      udn: _emptyToNull(_elementText(document, 'UDN')),
      deviceType: _emptyToNull(_elementText(document, 'deviceType')),
      location: location,
      avTransportControlUrl: resolvedControl,
    );
  }
}

/// Removes namespace prefixes such as `s:` from element tags so lookups can
/// use local names. Attribute values are untouched.
String _stripNamespacePrefixes(String xml) {
  final closing = xml.replaceAll(RegExp(r'<\s*/\s*[A-Za-z_][\w.-]*:'), '</');
  return closing.replaceAll(RegExp(r'<\s*[A-Za-z_][\w.-]*:'), '<');
}

String? _elementText(String document, String localName) {
  final match = RegExp(
    '<$localName\\b[^>]*>(.*?)</$localName\\s*>',
    dotAll: true,
    caseSensitive: false,
  ).firstMatch(document);
  if (match == null) return null;
  return decodeXmlEntities(_stripCdata(match.group(1) ?? '').trim());
}

String _stripCdata(String value) {
  var result = value.trim();
  while (result.startsWith('<![CDATA[') && result.endsWith(']]>')) {
    result = result.substring(9, result.length - 3).trim();
  }
  return result;
}

String? _emptyToNull(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Uri _resolveBase(String document, Uri location) {
  final urlBase = _elementText(document, 'URLBase');
  if (urlBase == null || urlBase.isEmpty) return location;
  final parsed = Uri.tryParse(urlBase);
  if (parsed == null || !parsed.hasScheme) return location;
  final resolved = location.resolveUri(parsed);
  if (!SsdpClient.isAllowedDescriptionLocation(resolved, location.host)) {
    return location;
  }
  return resolved;
}

_ServiceEntry? _selectAvTransportService(
  String document, {
  required Uri base,
  String? sourceAddress,
}) =>
    _selectService(
      document,
      base: base,
      sourceAddress: sourceAddress,
      isPrimary: (type, _) =>
          type.contains(':service:AVTransport:') ||
          type.endsWith(':AVTransport:1'),
      isFallback: (_, serviceId, control) =>
          serviceId.contains('AVTransport') || control.contains('avtrans'),
    );

_ServiceEntry? _selectContentDirectoryService(
  String document, {
  required Uri base,
  String? sourceAddress,
}) =>
    _selectService(
      document,
      base: base,
      sourceAddress: sourceAddress,
      isPrimary: (type, _) =>
          type.contains(':service:ContentDirectory:') ||
          type.endsWith(':ContentDirectory:1'),
      isFallback: (_, serviceId, control) =>
          serviceId.contains('ContentDirectory') ||
          control.toLowerCase().contains('contentdir'),
    );

/// Returns the first service matching [isPrimary], else the first one
/// matching [isFallback].
_ServiceEntry? _selectService(
  String document, {
  required Uri base,
  String? sourceAddress,
  required bool Function(String type, String serviceId) isPrimary,
  required bool Function(String type, String serviceId, String controlUrl)
      isFallback,
}) {
  final blocks = RegExp(
    r'<service\b[^>]*>(.*?)</service\s*>',
    dotAll: true,
    caseSensitive: false,
  ).allMatches(document);

  _ServiceEntry? fallback;
  for (final block in blocks) {
    final body = block.group(1) ?? '';
    final type = _elementText(body, 'serviceType') ?? '';
    final control = _elementText(body, 'controlURL') ?? '';
    if (control.isEmpty) continue;
    final resolved = base.resolve(control);
    if (!SsdpClient.isAllowedDescriptionLocation(resolved, sourceAddress)) {
      continue;
    }
    final serviceId = _elementText(body, 'serviceId') ?? '';
    final entry = _ServiceEntry(controlUrl: resolved.toString());
    if (isPrimary(type, serviceId)) return entry;
    if (isFallback(type, serviceId, control)) fallback ??= entry;
  }
  return fallback;
}

/// The subset of a UPnP description Pulsr needs to browse a MediaServer.
///
/// Deliberately separate from [UpnpDeviceDescription]: a media server exposes
/// no AVTransport service, so the renderer parser rejects it by design (which
/// is why SSDP responses from both device classes can share one fetch path).
/// Both readers use the same namespace-tolerant helpers.
class UpnpServerDescription {
  /// Human-readable device name (`friendlyName`).
  final String friendlyName;

  /// `modelName`, when advertised.
  final String? modelName;

  /// `manufacturer`, when advertised.
  final String? manufacturer;

  /// Unique device name (`UDN`), e.g. `uuid:...`.
  final String? udn;

  /// Declared device type, e.g. `urn:schemas-upnp-org:device:MediaServer:1`.
  final String? deviceType;

  /// Absolute URL the description was fetched from.
  final Uri location;

  /// Absolute control URL of the device's ContentDirectory service.
  final Uri contentDirectoryControlUrl;

  const UpnpServerDescription({
    required this.friendlyName,
    required this.location,
    required this.contentDirectoryControlUrl,
    this.modelName,
    this.manufacturer,
    this.udn,
    this.deviceType,
  });

  /// Stable identity for selection and de-duplication.
  String get identity {
    final unique = udn;
    return unique == null || unique.isEmpty
        ? contentDirectoryControlUrl.toString()
        : unique;
  }

  /// True when the device declares itself a MediaServer.
  bool get isMediaServer => deviceType?.contains('MediaServer') ?? false;

  /// Parses [xml] fetched from [location].
  ///
  /// Throws [UpnpParseError] when the document has no `friendlyName` or no
  /// usable ContentDirectory `controlURL`.
  static UpnpServerDescription parse(String xml, {required Uri location}) {
    if (xml.trim().isEmpty) {
      throw const UpnpParseError(
        code: 'DLNA_EMPTY_DESCRIPTION',
        userMessage: 'The device returned an empty description.',
      );
    }

    final document = _stripNamespacePrefixes(xml);
    final friendlyName = _elementText(document, 'friendlyName');
    if (friendlyName == null || friendlyName.isEmpty) {
      throw const UpnpParseError(
        code: 'DLNA_FRIENDLY_NAME',
        userMessage: 'The device description has no name.',
      );
    }

    final base = _resolveBase(document, location);
    final service = _selectContentDirectoryService(
      document,
      base: base,
      sourceAddress: location.host,
    );
    final controlUrl = service?.controlUrl ?? '';
    if (controlUrl.isEmpty) {
      throw const UpnpParseError(
        code: 'DLNA_CONTENT_DIRECTORY',
        userMessage:
            'The device does not expose a ContentDirectory control URL.',
      );
    }

    final resolvedControl = Uri.parse(controlUrl);
    if (!SsdpClient.isAllowedDescriptionLocation(resolvedControl, location.host)) {
      throw const UpnpParseError(
        code: 'DLNA_CONTENT_DIRECTORY_DISALLOWED',
        userMessage:
            'The ContentDirectory control URL points to a disallowed location.',
      );
    }

    return UpnpServerDescription(
      friendlyName: friendlyName,
      modelName: _emptyToNull(_elementText(document, 'modelName')),
      manufacturer: _emptyToNull(_elementText(document, 'manufacturer')),
      udn: _emptyToNull(_elementText(document, 'UDN')),
      deviceType: _emptyToNull(_elementText(document, 'deviceType')),
      location: location,
      contentDirectoryControlUrl: resolvedControl,
    );
  }
}

class _ServiceEntry {
  final String controlUrl;

  const _ServiceEntry({required this.controlUrl});
}
