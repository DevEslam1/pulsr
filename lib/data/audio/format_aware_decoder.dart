// lib/data/audio/format_aware_decoder.dart
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/constants/audio_formats.dart';
import '../../domain/models/audio_quality_info.dart';
import '../db/app_database.dart';
import 'dsd_decoder_helper.dart';
import 'mqa_decoder_helper.dart';

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
  Future<AudioSource> decodeForFormat(
      SongsTableData song, MediaItem tag) async {
    // Reset the DoP transport flag for every load. It is a process-wide static
    // that [DsdDecoderHelper] sets true only when a compatible USB DAC is in
    // use; without this reset it stayed true after the first DoP DSD track,
    // forcing unity mixer volume and disabling native ReplayGain for every
    // subsequent track. The DSD branch below re-sets it when appropriate.
    AudioQualityInfo.dsdDopActive = false;

    if (song.source == SongSource.youtube) {
      return resolveYtmStream(song, tag);
    }

    final cleanPath = song.path.split('?').first;
    final dot = cleanPath.lastIndexOf('.');
    final ext =
        dot >= 0 ? cleanPath.substring(dot + 1).toLowerCase() : '';

    // Formats recognized in the native tier have no platform decoder in this
    // build. Fail honestly instead of handing a bogus file URI to ExoPlayer.
    if (AudioFormats.requiresNativeDecoder(ext)) {
      throw PlayerException(
        9002,
        'Format .$ext requires a native decoder that is not bundled in this build',
        null,
      );
    }

    switch (ext) {
      // 1. High-Res Lossless & MQA
      case 'flac':
      case 'wav':
        final isMqa = await MqaDecoderHelper.isMqaFile(song.path);
        if (isMqa) {
          MqaDecoderHelper.markMqaPath(song.path);
          if (MqaDecoderHelper.isMqaEnabled?.call() ?? true) {
            return MqaDecoderHelper.decodeMqaFile(song, tag);
          }
        }
        return AudioSource.uri(Uri.file(song.path), tag: tag);
      case 'alac':
      case 'aiff':
        return AudioSource.uri(Uri.file(song.path), tag: tag);

      // 2. DSD Formats (Direct Stream Digital)
      case 'dsf':
      case 'dff':
        final decoder = decodeDsdToPcm ?? DsdDecoderHelper.decodeDsdFile;
        return decoder(song, tag);

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
