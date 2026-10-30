// lib/core/utils/metadata_placeholders.dart

/// Recognises placeholder values used when a file or online result carries no
/// usable title/artist/album. Scanners and tag writers substitute these for
/// missing data; reconciliation must never let them replace real metadata that
/// the download already knows.
class MetadataPlaceholders {
  static const Set<String> _artistPlaceholders = {
    '',
    '<unknown>',
    'unknown',
    'unknown artist',
  };

  static const Set<String> _albumPlaceholders = {
    '',
    '<unknown>',
    'unknown',
    'unknown album',
    'youtube music',
  };

  static bool isUnknownArtist(String? value) =>
      _artistPlaceholders.contains(_normalize(value));

  static bool isUnknownAlbum(String? value) =>
      _albumPlaceholders.contains(_normalize(value));

  static bool isUnknownTitle(String? value) {
    final normalized = _normalize(value);
    if (normalized.isEmpty || normalized == '<unknown>') return true;
    if (normalized == 'unknown' ||
        normalized == 'unknown title' ||
        normalized == 'unknown song') {
      return true;
    }
    return normalized.startsWith('ytdl_');
  }

  /// True when [value] is safe to show as real metadata.
  static bool isRealArtist(String? value) => !isUnknownArtist(value);
  static bool isRealAlbum(String? value) => !isUnknownAlbum(value);
  static bool isRealTitle(String? value) => !isUnknownTitle(value);

  static String _normalize(String? value) => (value ?? '').trim().toLowerCase();
}
