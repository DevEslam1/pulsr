// lib/core/constants/audio_formats.dart

class AudioFormats {
  /// Audio file extensions reliably supported and playable on Android via ExoPlayer & Native DSD Decoder.
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
  };

  /// Extensions excluded from library scanning due to lack of standard Android decoding support.
  static const Set<String> unsupportedExtensions = {
    'wma',
  };

  static bool isSupportedExtension(String pathOrExt) {
    final ext = extractExtension(pathOrExt);
    return supportedExtensions.contains(ext);
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
          unsupportedExtensions.contains(sub)) {
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
            unsupportedExtensions.contains(clean))) {
      return clean;
    }
    return '';
  }
}
