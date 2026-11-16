// lib/features/dlna/upnp_device.dart
//
// Parser for UPnP device description documents. Namespace prefixes are
// stripped before reading elements, so the parser accepts both
// `<friendlyName>` and `<s:friendlyName>` shapes from real-world devices.
import '../../core/errors/app_error_base.dart';

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

    final service = _selectAvTransportService(document);
    final controlUrl = service?.controlUrl ?? '';
    if (controlUrl.isEmpty) {
      throw const UpnpParseError(
        code: 'DLNA_CONTROL_URL',
        userMessage: 'The device does not expose an AVTransport control URL.',
      );
    }

    final base = _resolveBase(document, location);
    final resolvedControl = base.resolve(controlUrl);

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

  /// Removes namespace prefixes such as `s:` from element tags so lookups can
  /// use local names. Attribute values are untouched.
  static String _stripNamespacePrefixes(String xml) {
    final closing = xml.replaceAll(RegExp(r'<\s*/\s*[A-Za-z_][\w.-]*:'), '</');
    return closing.replaceAll(RegExp(r'<\s*[A-Za-z_][\w.-]*:'), '<');
  }

  static String? _elementText(String document, String localName) {
    final match = RegExp(
      '<$localName\\b[^>]*>(.*?)</$localName\\s*>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(document);
    if (match == null) return null;
    return _decodeEntities(_stripCdata(match.group(1) ?? '').trim());
  }

  static String _stripCdata(String value) {
    var result = value.trim();
    while (result.startsWith('<![CDATA[') && result.endsWith(']]>')) {
      result = result.substring(9, result.length - 3).trim();
    }
    return result;
  }

  static String? _emptyToNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Uri _resolveBase(String document, Uri location) {
    final urlBase = _elementText(document, 'URLBase');
    if (urlBase == null || urlBase.isEmpty) return location;
    final parsed = Uri.tryParse(urlBase);
    if (parsed == null || !parsed.hasScheme) return location;
    return parsed;
  }

  static _ServiceEntry? _selectAvTransportService(String document) {
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
      final serviceId = _elementText(body, 'serviceId') ?? '';
      final entry = _ServiceEntry(controlUrl: control);
      if (type.contains(':service:AVTransport:') ||
          type.endsWith(':AVTransport:1')) {
        return entry;
      }
      if (serviceId.contains('AVTransport') || control.contains('avtrans')) {
        fallback ??= entry;
      }
    }
    return fallback;
  }

  static String _decodeEntities(String value) {
    if (!value.contains('&')) return value;
    return value.replaceAllMapped(
      RegExp(r'&(#x?[0-9A-Fa-f]+|[A-Za-z]+);'),
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
        if (token.startsWith('#x') || token.startsWith('#X')) {
          final code = int.tryParse(token.substring(2), radix: 16);
          return code == null ? match.group(0)! : String.fromCharCode(code);
        }
        if (token.startsWith('#')) {
          final code = int.tryParse(token.substring(1));
          return code == null ? match.group(0)! : String.fromCharCode(code);
        }
        return match.group(0)!;
      },
    );
  }
}

class _ServiceEntry {
  final String controlUrl;

  const _ServiceEntry({required this.controlUrl});
}
