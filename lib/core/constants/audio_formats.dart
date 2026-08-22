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

  /// Playable file extensions set.
  static const Set<String> playableExtensions = {
    'mp3',
    'm4a',
    'aac',
    'flac',
    'wav',
    'ogg',
    'opus',
    'mka',
  };

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
    final ext = extractExtension(pathOrExt);
    return playableExtensions.contains(ext);
  }

  static String extractExtension(String pathOrExt) {
    final clean = pathOrExt.split('?').first.toLowerCase();
    if (clean.contains('.')) {
      return clean.split('.').last;
    }
    return clean;
  }
}
