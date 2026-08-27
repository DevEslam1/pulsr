// lib/data/audio/format_aware_decoder.dart
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../db/app_database.dart';

/// Routes audio playback to the optimal decode path per format.
class FormatAwareDecoder {
  final Future<AudioSource> Function(SongsTableData song, MediaItem tag)
      resolveYtmStream;
  final Future<AudioSource> Function(SongsTableData song, MediaItem tag)?
      decodeDsdToPcm;

  const FormatAwareDecoder({
    required this.resolveYtmStream,
    this.decodeDsdToPcm,
  });

  /// Decodes and wraps [song] into an optimal [AudioSource].
  Future<AudioSource> decodeForFormat(SongsTableData song, MediaItem tag) async {
    if (song.source == SongSource.youtube) {
      return resolveYtmStream(song, tag);
    }

    final ext = song.path.split('.').last.toLowerCase();

    switch (ext) {
      // 1. High-Res Lossless: Direct file access, native decoder
      case 'flac':
      case 'wav':
      case 'alac':
      case 'aiff':
        return AudioSource.uri(Uri.file(song.path), tag: tag);

      // 2. DSD Formats (Direct Stream Digital)
      case 'dsf':
      case 'dff':
        if (decodeDsdToPcm != null) {
          return decodeDsdToPcm!(song, tag);
        }
        return AudioSource.uri(Uri.file(song.path), tag: tag);

      // 3. Compressed Standard Formats
      case 'mp3':
      case 'aac':
      case 'm4a':
      case 'ogg':
      case 'opus':
      default:
        return AudioSource.uri(Uri.file(song.path), tag: tag);
    }
  }
}
