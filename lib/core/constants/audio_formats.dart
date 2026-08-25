// lib/core/constants/audio_formats.dart

class AudioFormats {
  /// Audio file extensions reliably supported and playable on Android via ExoPlayer.
  static const Set<String> supportedExtensions = {
    'mp3',
    'm4a',
    'aac',
    'flac',
    'wav',
    'ogg',
    'opus',
    'mka',
  };

  /// Playable file extensions set (alias of supportedExtensions for playback compatibility).
  static const Set<String> playableExtensions = supportedExtensions;

  /// Extensions excluded from library scanning due to lack of standard Android decoding support.
  static const Set<String> unsupportedExtensions = {
    'wma',
    'dsf',
    'dff',
  };

  static bool isSupportedExtension(String pathOrExt) {
    final ext = extractExtension(pathOrExt);
    return supportedExtensions.contains(ext);
  }

  static bool isPlayableExtension(String pathOrExt) {
    return isSupportedExtension(pathOrExt);
  }

  static String extractExtension(String pathOrExt) {
    final clean = pathOrExt.split('?').first.split('#').first.trim().toLowerCase();
    final filename = clean.split('/').last.split(r'\').last;
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex > 0 && dotIndex < filename.length - 1) {
      return filename.substring(dotIndex + 1);
    }
    // If the input was provided directly as an extension (e.g. "mp3" or "flac") without paths or leading dots
    if (!clean.contains('/') && !clean.contains(r'\') && !clean.contains('.') && clean.isNotEmpty) {
      return clean;
    }
    return '';
  }
}
