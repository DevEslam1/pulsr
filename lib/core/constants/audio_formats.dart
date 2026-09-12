// lib/core/constants/audio_formats.dart

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

  static String extractExtension(String pathOrExt) {
    final clean =
        pathOrExt.split('?').first.split('#').first.trim().toLowerCase();
    if (clean.isEmpty || clean.endsWith('/') || clean.endsWith(r'\')) {
      return '';
    }
    // Handle bare extension with leading dot e.g. ".mp3" or ".flac"
    if (clean.startsWith('.') &&
        !clean.contains('/') &&
        !clean.contains(r'\')) {
      final ext = clean.substring(1);
      if (ext.isNotEmpty &&
          !ext.contains('.') &&
          ext != 'nomedia' &&
          ext != 'gitignore') {
        return ext;
      }
      return '';
    }
    final filename = clean.split('/').last.split(r'\').last;
    if (filename.isEmpty || filename == '.nomedia') {
      return '';
    }
    if (filename.startsWith('.')) {
      final sub = filename.substring(1);
      if (supportedExtensions.contains(sub) ||
          nativeDecodableExtensions.contains(sub)) {
        return sub;
      }
      return '';
    }
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex > 0 && dotIndex < filename.length - 1) {
      return filename.substring(dotIndex + 1);
    }
    // If the input was provided directly as an extension (e.g. "mp3" or "flac") without paths or leading dots
    if (!clean.contains('/') &&
        !clean.contains(r'\') &&
        !clean.contains('.') &&
        (supportedExtensions.contains(clean) ||
            nativeDecodableExtensions.contains(clean))) {
      return clean;
    }
    return '';
  }
}
