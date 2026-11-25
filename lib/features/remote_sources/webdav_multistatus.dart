// lib/features/remote_sources/webdav_multistatus.dart
//
// P0-1 "remote sources": the WebDAV `multistatus` reader.
//
// Namespace prefixes are treated as noise (Nextcloud sends `d:`, Apache sends
// `D:`, some appliances send none), hrefs may be absolute URLs or absolute
// paths, and every value is percent- and entity-decoded before it reaches the
// UI. No XML package is used: the response shape is a flat list of `response`
// blocks and a hand-written scanner keeps `dart:convert` XML out of the
// dependency graph.
import 'dart:io';

import '../../domain/models/remote_source.dart';

/// Parses a WebDAV `<multistatus>` body into entries relative to [rootPath].
///
/// The request target itself is dropped (it is the collection being listed)
/// unless [keepSelf] is true, which is what a `Depth: 0` stat needs.
List<RemoteEntry> parseWebDavMultiStatus(
  String xml, {
  required String rootPath,
  required String requestPath,
  bool keepSelf = false,
}) {
  final wanted = _stripSlashes(requestPath).toLowerCase();
  final entries = <RemoteEntry>[];
  for (final match in _responseBlock.allMatches(xml)) {
    final block = match.group(1);
    if (block == null) continue;
    final href = _textOf(block, 'href');
    if (href == null || href.isEmpty) continue;
    final propSource = _successfulPropSource(block);
    if (propSource == null) continue;
    final relative = _relativeFromHref(href, rootPath);
    if (relative == null) continue;
    if (!keepSelf && relative.toLowerCase() == wanted) continue;
    final name = relative.isEmpty ? '/' : relative.split('/').last;
    if (name.isEmpty) continue;
    final resourceType = _innerOf(propSource, 'resourcetype') ?? '';
    final isDirectory = _collectionTag.hasMatch(resourceType);
    final size = int.tryParse(_textOf(propSource, 'getcontentlength') ?? '');
    entries.add(
      RemoteEntry(
        path: relative,
        name: name,
        isDirectory: isDirectory,
        sizeBytes: isDirectory ? null : size,
        modifiedAt: _parseHttpDate(_textOf(propSource, 'getlastmodified')),
        etag: _normalizeEtag(_textOf(propSource, 'getetag')),
      ),
    );
  }
  entries.sort(RemoteEntry.compare);
  return entries;
}

final RegExp _responseBlock = RegExp(
  r'<(?:[A-Za-z_][\w.\-]*:)?response\b[^>]*>(.*?)</(?:[A-Za-z_][\w.\-]*:)?response\s*>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _propstatBlock = RegExp(
  r'<(?:[A-Za-z_][\w.\-]*:)?propstat\b[^>]*>(.*?)</(?:[A-Za-z_][\w.\-]*:)?propstat\s*>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _cdata = RegExp(r'^<!\[CDATA\[(.*?)\]\]>$', dotAll: true);
final RegExp _collectionTag = RegExp(
  r'<(?:[A-Za-z_][\w.\-]*:)?collection\b',
  caseSensitive: false,
);
final RegExp _httpStatusCode = RegExp(r'\b(\d{3})\b');
final RegExp _xmlEntity =
    RegExp(r'&(?:lt|gt|quot|apos|amp|#\d+|#x[0-9a-fA-F]+);');

/// Returns the concatenated 2xx `<propstat>` XML fragments inside a `<response>`,
/// or `null` when `<status>` rejects the response (403/404/etc.).
String? _successfulPropSource(String block) {
  final propstats = _propstatBlock
      .allMatches(block)
      .map((match) => match.group(1))
      .whereType<String>()
      .toList();
  if (propstats.isEmpty) {
    final responseStatus = _textOf(block, 'status');
    return _isSuccessStatus(responseStatus) ? block : null;
  }
  final ok = <String>[];
  for (final propstat in propstats) {
    if (_isSuccessStatus(_textOf(propstat, 'status'))) {
      ok.add(propstat);
    }
  }
  return ok.isEmpty ? null : ok.join('\n');
}

bool _isSuccessStatus(String? statusText) {
  if (statusText == null || statusText.trim().isEmpty) return true;
  final match = _httpStatusCode.firstMatch(statusText);
  if (match == null) return false;
  final code = int.tryParse(match.group(1)!) ?? 0;
  return code >= 200 && code < 300;
}

String? _relativeFromHref(String href, String rootPath) {
  var raw = href.trim();
  if (raw.isEmpty) return null;
  final lower = raw.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    raw = parsed.path;
  }
  final queryIndex = raw.indexOf('?');
  if (queryIndex != -1) raw = raw.substring(0, queryIndex);
  final fragmentIndex = raw.indexOf('#');
  if (fragmentIndex != -1) raw = raw.substring(0, fragmentIndex);
  if (!raw.startsWith('/')) raw = '/$raw';
  String decoded;
  try {
    decoded = Uri.decodeComponent(raw);
  } on ArgumentError {
    decoded = raw;
  } on FormatException {
    decoded = raw;
  }
  final root = RemoteSource.normalizeRootPath(rootPath);
  if (root != '/') {
    if (decoded.toLowerCase() == root.toLowerCase()) return '';
    if (!decoded.toLowerCase().startsWith('${root.toLowerCase()}/')) {
      return null;
    }
    decoded = decoded.substring(root.length);
  }
  final stripped = _stripSlashes(decoded);
  if (stripped.split('/').any((segment) => segment == '..')) return null;
  return stripped;
}

String _stripSlashes(String value) {
  var result = value;
  while (result.startsWith('/')) {
    result = result.substring(1);
  }
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

String? _innerOf(String block, String tag) {
  final pattern = RegExp(
    '<(?:[A-Za-z_][\\w.\\-]*:)?$tag\\b[^>]*>(.*?)</(?:[A-Za-z_][\\w.\\-]*:)?$tag\\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  return pattern.firstMatch(block)?.group(1);
}

String? _textOf(String block, String tag) {
  final inner = _innerOf(block, tag);
  if (inner == null) return null;
  var value = inner.trim();
  final cdata = _cdata.firstMatch(value);
  if (cdata != null) value = cdata.group(1)?.trim() ?? '';
  return _decodeEntities(value);
}

String _decodeEntities(String value) {
  if (!value.contains('&')) return value;
  return value.replaceAllMapped(_xmlEntity, (match) {
    final token = match.group(0)!;
    switch (token) {
      case '&lt;':
        return '<';
      case '&gt;':
        return '>';
      case '&quot;':
        return '"';
      case '&apos;':
        return "'";
      case '&amp;':
        return '&';
      default:
        final isHex = token.startsWith('&#x');
        final digits = token.substring(isHex ? 3 : 2, token.length - 1);
        final codePoint = int.tryParse(digits, radix: isHex ? 16 : 10);
        if (codePoint == null ||
            codePoint <= 0 ||
            codePoint > 0x10FFFF ||
            (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
          return token;
        }
        return String.fromCharCode(codePoint);
    }
  });
}

DateTime? _parseHttpDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    return HttpDate.parse(raw.trim());
  } on FormatException {
    return null;
  } on HttpException {
    return null;
  }
}

String? _normalizeEtag(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();
  if (value.isEmpty) return null;
  if (value.startsWith('W/')) value = value.substring(2);
  if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
    value = value.substring(1, value.length - 1);
  }
  return value.isEmpty ? null : value;
}
