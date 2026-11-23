// lib/data/audio/sacd/sacd_exceptions.dart
//
// Shared exception type for the SACD pipeline. Kept in its own library so the
// extractor, the cache and the ISO open path can depend on it without an
// import cycle. `sacd_dsf_extractor.dart` re-exports it, which is why callers
// still `import '.../sacd_dsf_extractor.dart'` to catch extraction failures.

/// Thrown when a track cannot be extracted into a DSF file.
class SacdDsfException implements Exception {
  /// Creates the exception with a loggable [message].
  const SacdDsfException(this.message);

  /// Human-readable reason, safe to log.
  final String message;

  @override
  String toString() => 'SacdDsfException: $message';
}

/// Thrown when a SACD TOC or audio frame uses DST lossless compression
/// (`frame_format == 0`), which cannot be extracted as raw uncompressed DSD.
class SacdDstUnsupportedException extends SacdDsfException {
  const SacdDstUnsupportedException([
    super.message =
        'DST-compressed SACD frames (frame_format == 0) are not supported',
  ]);

  @override
  String toString() => 'SacdDstUnsupportedException: $message';
}
