// lib/core/constants/audio_formats.dart

/// {@category DesignSystem}
class AudioFormats {
  /// Platform-decodable extensions: playable on Android via ExoPlayer/MediaCodec
  /// plus the bundled native DSD decoder. Safe to index into the playable library.
  static const Set<String> supportedExtensions = {
    'mp3',
    'm4a',
    'aac',
    'flac',
    'wav',
    'ogg',
    'opus',
    'mka',
    'dsf',
    'dff',
    'webm',
    'oga',
    'aiff',
    'aif',
  };

  /// Recognized extensions that require a native decoder this build does not
  /// bundle. They are classified (and may be counted) but must never be scanned
  /// into the playable library.
  static const Set<String> nativeDecodableExtensions = {
    'ape',
    'wma',
    'tta',
    'tak',
    'wv',
    'mpc',
    'mod',
    'it',
    'xm',
    's3m',
  };

  /// Extensions excluded from playable library scanning. The native tier is
  /// folded in here because those formats are not decodable in this build.
  static const Set<String> unsupportedExtensions = {
    ...nativeDecodableExtensions,
  };

  static bool isSupportedExtension(String pathOrExt) {
    final ext = extractExtension(pathOrExt);
    return supportedExtensions.contains(ext);
  }

  static bool isRecognizedExtension(String pathOrExt) {
    final ext = extractExtension(pathOrExt);
    return supportedExtensions.contains(ext) ||
        nativeDecodableExtensions.contains(ext);
  }

  static bool requiresNativeDecoder(String pathOrExt) {
    final ext = extractExtension(pathOrExt);
    return nativeDecodableExtensions.contains(ext);
  }

  static final RegExp _urlSchemeRegex = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');

  static String extractExtension(String pathOrExt) {
    var clean = pathOrExt.trim();
    if (clean.isEmpty) return '';

    // Only strip '?' query and '#' fragment from non-file URLs.
    // Local filesystem paths can legitimately contain '#' (e.g. "Track #1.mp3")
    // or '?' and must not be prematurely truncated.
    final lower = clean.toLowerCase();
    if (_urlSchemeRegex.hasMatch(clean) && !lower.startsWith('file://')) {
      clean = clean.split('?').first.split('#').first.trim();
    }
    clean = clean.toLowerCase();
    if (clean.isEmpty || clean.endsWith('/') || clean.endsWith(r'\')) {
      return '';
    }
    final hasPathSeparator = clean.contains('/') || clean.contains(r'\');

    // Handle bare extension with leading dot e.g. ".mp3" or ".flac"
    if (clean.startsWith('.') && !hasPathSeparator) {
      if (clean.startsWith('.trashed-') || clean.startsWith('._')) {
        return '';
      }
      final ext = clean.substring(1);
      if (ext.isNotEmpty &&
          !ext.contains('.') &&
          ext != 'nomedia' &&
          ext != 'gitignore') {
        if (supportedExtensions.contains(ext) ||
            nativeDecodableExtensions.contains(ext)) {
          return ext;
        }
      }
      return '';
    }

    final filename = clean.split('/').last.split(r'\').last;
    if (filename.isEmpty || filename == '.nomedia') {
      return '';
    }

    // Reject hidden dot-prefixed filenames when a path separator is present or
    // when the filename starts with .trashed- (Android MediaStore) or ._ (macOS AppleDouble)
    if (filename.startsWith('.')) {
      if (hasPathSeparator ||
          filename.startsWith('.trashed-') ||
          filename.startsWith('._')) {
        return '';
      }
      return '';
    }

    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex > 0 && dotIndex < filename.length - 1) {
      return filename.substring(dotIndex + 1);
    }
    // If the input was provided directly as an extension (e.g. "mp3" or "flac") without paths or leading dots
    if (!hasPathSeparator &&
        !clean.contains('.') &&
        (supportedExtensions.contains(clean) ||
            nativeDecodableExtensions.contains(clean))) {
      return clean;
    }
    return '';
  }
}
