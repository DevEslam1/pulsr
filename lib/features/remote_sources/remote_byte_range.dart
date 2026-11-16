// lib/features/remote_sources/remote_byte_range.dart
//
// P0-1 "remote sources": HTTP `Range: bytes=` arithmetic for the stream bridge.
//
// Implemented locally (not borrowed from the DLNA module) so the two range
// parsers cannot drift: this one is the only thing standing between a player's
// seek and a byte window, and every branch is unit-tested.
/// One resolved `Range: bytes=` window; both bounds are inclusive.
class RemoteByteRange {
  /// Creates a window.
  const RemoteByteRange({required this.start, required this.end});

  /// First byte to send.
  final int start;

  /// Last byte to send (inclusive).
  final int end;

  /// Number of bytes in the window.
  int get length => end - start + 1;

  @override
  String toString() => 'RemoteByteRange($start-$end)';
}

/// Result of parsing a `Range` header.
class RemoteRangeParseResult {
  /// Creates a parse result.
  const RemoteRangeParseResult({this.range, this.unsatisfiable = false});

  /// The window to serve, or `null` when the request did not ask for one.
  final RemoteByteRange? range;

  /// Whether the header was valid but falls outside the file (HTTP 416).
  final bool unsatisfiable;

  /// Whether a range header was present at all.
  bool get hasRange => range != null || unsatisfiable;
}

/// Parses a `Range: bytes=` header against [totalLength].
///
/// Supports `start-end`, `start-` and `-suffix`, clamps an end past the file,
/// uses the first of several windows and reports [unsatisfiable] for a window
/// that starts past the end. Anything unrecognised returns "no range", which
/// makes the caller answer 200 with the whole file.
RemoteRangeParseResult parseRemoteRangeHeader(
  String? header, {
  required int totalLength,
}) {
  const none = RemoteRangeParseResult();
  if (header == null) return none;
  final value = header.trim();
  if (value.isEmpty) return none;
  if (!value.toLowerCase().startsWith('bytes=')) return none;
  final spec = value.substring(6).split(',').first.trim();
  if (spec.isEmpty) return none;
  final dash = spec.indexOf('-');
  if (dash == -1) return none;
  final startText = spec.substring(0, dash).trim();
  final endText = spec.substring(dash + 1).trim();
  if (startText.isEmpty) {
    final suffix = int.tryParse(endText);
    if (suffix == null) return none;
    if (suffix <= 0) return const RemoteRangeParseResult(unsatisfiable: true);
    if (totalLength <= 0) {
      return const RemoteRangeParseResult(unsatisfiable: true);
    }
    final start = suffix >= totalLength ? 0 : totalLength - suffix;
    return RemoteRangeParseResult(
      range: RemoteByteRange(start: start, end: totalLength - 1),
    );
  }
  final start = int.tryParse(startText);
  if (start == null || start < 0) return none;
  if (start >= totalLength) {
    return const RemoteRangeParseResult(unsatisfiable: true);
  }
  var end = totalLength - 1;
  if (endText.isNotEmpty) {
    final parsedEnd = int.tryParse(endText);
    if (parsedEnd == null || parsedEnd < start) {
      return const RemoteRangeParseResult(unsatisfiable: true);
    }
    end = parsedEnd < totalLength ? parsedEnd : totalLength - 1;
  }
  return RemoteRangeParseResult(
    range: RemoteByteRange(start: start, end: end),
  );
}
