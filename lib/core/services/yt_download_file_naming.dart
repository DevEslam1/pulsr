// lib/core/services/yt_download_file_naming.dart
import 'dart:convert';
import 'dart:io';

/// File-name and container rules for the audio a download writes.
class YtDownloadFileNaming {
  /// Audio container extensions this service is willing to name a file after.
  static const Set<String> _allowedExtensions = {
    'm4a',
    'webm',
    'opus',
    'mp4',
    'ogg',
    'oga',
    'mp3',
    'flac',
    'aac',
  };

  /// F11: [ext] arrives from the resolver and from byte sniffing and is then
  /// interpolated straight into a file name, so it has to be a bare container
  /// extension and nothing that could carry a path separator or a traversal
  /// segment.
  static String safeExtension(String? ext) {
    final e = (ext ?? '').trim().toLowerCase();
    if (e.isEmpty || e.contains('.') || e.contains('/') || e.contains('\\')) {
      return 'm4a';
    }
    return _allowedExtensions.contains(e) ? e : 'm4a';
  }

  static String sanitizeFilename(String artist, String title, String ext) {
    ext = safeExtension(ext);
    var rawArtist = artist.trim();
    var rawTitle = title.trim();
    if (rawArtist.isEmpty) rawArtist = 'Unknown Artist';
    if (rawTitle.isEmpty) rawTitle = 'Unknown Title';

    // 1. Strip reserved characters and control characters (BUG-015)
    final cleanedArtist =
        rawArtist.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    final cleanedTitle =
        rawTitle.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();

    var base = '$cleanedArtist - $cleanedTitle';
    // 2. Check Windows reserved device names
    final baseUpper = base.toUpperCase().split('.').first;
    const reservedNames = {
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
      'LPT9'
    };
    if (reservedNames.contains(baseUpper)) {
      base = '${base}_track';
    }

    // 3. Limit UTF-8 byte length to 180 bytes (BUG-015)
    var encoded = utf8.encode(base);
    if (encoded.length > 180) {
      while (encoded.length > 180 && base.isNotEmpty) {
        base = base.substring(0, base.length - 1);
        encoded = utf8.encode(base);
      }
    }
    // F11: strip trailing dots/spaces — not a valid file-name tail on every
    // target, and the shape a traversal attempt takes once separators are gone.
    base = base.replaceAll(RegExp(r'[. ]+$'), '').trim();
    if (base.isEmpty) base = 'Track';

    return '$base.$ext';
  }

  /// The container the bytes on disk actually are, or null for a header nothing
  /// recognises.
  ///
  /// The URL is not a trustworthy source for this. Entries the playback path
  /// wrote into `YtmUrlCache` carry no `YtmStream`, so the container and MIME
  /// that come back with them are *guessed* — and a WebM/Opus body was being
  /// saved as `.m4a`, handed to the MP4 tagger (which fails), and published to
  /// MediaStore as `audio/mp4`, leaving an untagged file with a lying extension
  /// that the scanner then refuses to index.
  static ({String ext, String mime})? sniffContainerBytes(List<int> header) {
    bool at(int offset, List<int> magic) {
      if (header.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (header[offset + i] != magic[i]) return false;
      }
      return true;
    }

    // ISO-BMFF: 4-byte box length, then 'ftyp'. Covers m4a/mp4/3gp.
    if (at(4, const [0x66, 0x74, 0x79, 0x70])) {
      return (ext: 'm4a', mime: 'audio/mp4');
    }
    // EBML header → Matroska/WebM.
    if (at(0, const [0x1A, 0x45, 0xDF, 0xA3])) {
      return (ext: 'webm', mime: 'audio/webm');
    }
    if (at(0, const [0x4F, 0x67, 0x67, 0x53])) {
      return (ext: 'ogg', mime: 'audio/ogg');
    }
    if (at(0, const [0x66, 0x4C, 0x61, 0x43])) {
      return (ext: 'flac', mime: 'audio/flac');
    }
    if (at(0, const [0x49, 0x44, 0x33])) {
      return (ext: 'mp3', mime: 'audio/mpeg');
    }
    // MPEG audio frame sync: eleven set bits.
    if (header.length >= 2 && header[0] == 0xFF && (header[1] & 0xE0) == 0xE0) {
      return (ext: 'mp3', mime: 'audio/mpeg');
    }
    return null;
  }

  static Future<({String ext, String mime})?> sniffContainer(File file) async {
    try {
      final raf = await file.open();
      try {
        return sniffContainerBytes(await raf.read(32));
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }
}
