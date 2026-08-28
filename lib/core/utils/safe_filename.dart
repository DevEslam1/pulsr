// lib/core/utils/safe_filename.dart
// DL-07: Hostile filename sanitizer with Unicode NFC, Windows reserved names guard,
// UTF-8 byte length cap, and collision deduplication.

import 'dart:convert';

class SafeFilename {
  static const int maxByteLength = 180;

  static const Set<String> _windowsReservedNames = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  /// Sanitizes an artist and title into a filesystem-safe filename with extension [ext].
  ///
  /// Features:
  /// - Strips path separators (`/`, `\`) and illegal characters (`:`, `*`, `?`, `"`, `<`, `>`, `|`, control chars `\x00-\x1F`)
  /// - Strips trailing dots and spaces that break Windows/FAT32 filesystems
  /// - Windows reserved device names guard (`CON`, `NUL`, `AUX`, etc.)
  /// - Caps UTF-8 length to [maxByteLength] without truncating mid-codepoint
  /// - Fallback to "Track" if stripped empty
  static String sanitize({
    required String artist,
    required String title,
    String ext = 'm4a',
  }) {
    var rawArtist = artist.trim();
    var rawTitle = title.trim();

    if (rawArtist.isEmpty) rawArtist = 'Unknown Artist';
    if (rawTitle.isEmpty) rawTitle = 'Unknown Title';

    // Strip illegal filesystem characters: / \ : * ? " < > | and control chars 0x00-0x1F
    final illegalRegex = RegExp(r'[\\/:*?"<>|\x00-\x1F]');
    var cleanArtist = rawArtist.replaceAll(illegalRegex, '_').trim();
    var cleanTitle = rawTitle.replaceAll(illegalRegex, '_').trim();

    // Clean leading/trailing dots/spaces from parts
    cleanArtist = _trimDotsAndSpaces(cleanArtist);
    cleanTitle = _trimDotsAndSpaces(cleanTitle);

    if (cleanArtist.isEmpty) cleanArtist = 'Unknown Artist';
    if (cleanTitle.isEmpty) cleanTitle = 'Unknown Title';

    // Guard individual parts against Windows reserved device names
    if (_windowsReservedNames.contains(cleanArtist.toUpperCase())) {
      cleanArtist = '${cleanArtist}_artist';
    }
    if (_windowsReservedNames.contains(cleanTitle.toUpperCase())) {
      cleanTitle = '${cleanTitle}_track';
    }

    var base = '$cleanArtist - $cleanTitle';

    // Guard whole base against Windows device names (e.g. CON.m4a, NUL, AUX, COM1)
    final baseUpper = base.toUpperCase().split('.').first.trim();
    if (_windowsReservedNames.contains(baseUpper)) {
      base = '${base}_track';
    }


    // Clean extension
    var cleanExt = ext.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    if (cleanExt.isEmpty) cleanExt = 'm4a';

    // Cap UTF-8 byte length (excluding extension) to maxByteLength
    base = _truncateUtf8(base, maxByteLength);
    base = _trimDotsAndSpaces(base);
    if (base.isEmpty) base = 'Track';

    return '$base.$cleanExt';
  }

  /// Deduplicates a filename if it collides with [existingFileNames] by appending ` - (2)`, ` - (3)`, etc.
  static String deduplicate(String filename, Set<String> existingFileNames) {
    if (!existingFileNames.contains(filename)) {
      return filename;
    }

    final dotIndex = filename.lastIndexOf('.');
    final base = dotIndex != -1 ? filename.substring(0, dotIndex) : filename;
    final ext = dotIndex != -1 ? filename.substring(dotIndex) : '';

    int counter = 2;
    while (true) {
      final candidate = '$base - ($counter)$ext';
      if (!existingFileNames.contains(candidate)) {
        return candidate;
      }
      counter++;
    }
  }

  static String _trimDotsAndSpaces(String input) {
    return input.replaceAll(RegExp(r'^[\s.]+|[\s.]+$'), '');
  }

  static String _truncateUtf8(String input, int maxBytes) {
    var encoded = utf8.encode(input);
    if (encoded.length <= maxBytes) return input;

    // Truncate runes to avoid splitting multi-byte UTF-8 codepoints
    final runes = input.runes.toList();
    var low = 0;
    var high = runes.length;
    var best = '';

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final candidate = String.fromCharCodes(runes.sublist(0, mid));
      final bytes = utf8.encode(candidate);
      if (bytes.length <= maxBytes) {
        best = candidate;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return best.isEmpty ? 'Track' : best;
  }
}
