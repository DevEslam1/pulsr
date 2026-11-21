// lib/data/audio/format_aware_decoder.dart
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/constants/audio_formats.dart';
import '../../core/utils/error_logger.dart';
import '../db/app_database.dart';
import 'dsd_decoder_helper.dart';
import 'decoder_runtime_probe.dart';
import 'mqa_decoder_helper.dart';

/// Routes audio playback to the optimal decode path per format.
class FormatAwareDecoder {
  final Future<AudioSource> Function(SongsTableData song, MediaItem tag)
      resolveYtmStream;
  final Future<AudioSource> Function(SongsTableData song, MediaItem tag)?
      decodeDsdToPcm;
  final DecoderRuntimeProbe? decoderProbe;
  DecoderRuntimeProbe? _fallbackProbe;

  FormatAwareDecoder({
    required this.resolveYtmStream,
    this.decodeDsdToPcm,
    this.decoderProbe,
  });

  DecoderRuntimeProbe get _probe =>
      decoderProbe ?? (_fallbackProbe ??= DecoderRuntimeProbe());

  Future<bool> _alacAvailable(SongsTableData song) async {
    final rate = song.sampleRate ?? 0;
    if (await _probe.supports('audio/alac', sampleRate: rate)) return true;
    return _probe.supports('audio/x-alac', sampleRate: rate);
  }

  /// Decodes and wraps [song] into an optimal [AudioSource].
  Future<AudioSource> decodeForFormat(
    SongsTableData song,
    MediaItem tag, {
    bool updateGlobalState = true,
    void Function(bool isDop, bool isNativeDsd)? onTransportResolved,
  }) async {
    // Reset the DoP transport flag for every load when running on the active
    // global path. Pre-buffered/concurrent loads pass updateGlobalState=false
    // and report via [onTransportResolved] so they don't clobber the currently
    // playing track's transport state.
    if (updateGlobalState) {
      DsdDecoderHelper.dsdDopActive = false;
      DsdDecoderHelper.dsdNativeActive = false;
    }

    if (song.source == SongSource.youtube) {
      onTransportResolved?.call(false, false);
      return resolveYtmStream(song, tag);
    }

    final cleanPath = song.path.split('?').first;
    final dot = cleanPath.lastIndexOf('.');
    final ext = dot >= 0 ? cleanPath.substring(dot + 1).toLowerCase() : '';

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
        // MQA detection/unfolding is an enhancement: if probing or decoding
        // throws (unreadable header, native helper missing) the track must
        // still play as plain FLAC/WAV instead of failing the whole load.
        try {
          final isMqa = await MqaDecoderHelper.isMqaFile(song.path);
          if (isMqa) {
            MqaDecoderHelper.markMqaPath(song.path);
            // Default OFF: the in-app "unfold" is only an approximate, un-
            // authenticated 2x interpolation (no real added resolution), and is
            // only safe for genuine 24-bit stereo PCM WAV. Require an explicit
            // opt-in via the wired isMqaEnabled callback.
            if (MqaDecoderHelper.isMqaEnabled?.call() ?? false) {
              return await MqaDecoderHelper.decodeMqaFile(song, tag);
            }
          }
        } catch (e, st) {
          ErrorLogger.log(
              'MQA probe/decode failed for ${song.path}; playing as plain .$ext',
              error: e,
              stackTrace: st,
              category: 'FormatAwareDecoder');
        }
        onTransportResolved?.call(false, false);
        return AudioSource.uri(Uri.file(song.path), tag: tag);
      case 'alac':
      case 'm4a':
        final codec = (song.codec ?? '').toUpperCase();
        final isAlac = ext == 'alac' || codec.contains('ALAC');
        if (isAlac && !await _alacAvailable(song)) {
          throw PlayerException(
            9003,
            'ALAC decoder is not available on this device for ${song.title}',
            null,
          );
        }
        onTransportResolved?.call(false, false);
        return AudioSource.uri(Uri.file(song.path), tag: tag);
      case 'aiff':
        onTransportResolved?.call(false, false);
        return AudioSource.uri(Uri.file(song.path), tag: tag);

      // 2. DSD Formats (Direct Stream Digital)
      case 'dsf':
      case 'dff':
        if (decodeDsdToPcm != null) {
          final source = await decodeDsdToPcm!(song, tag);
          onTransportResolved?.call(false, false);
          return source;
        }
        return DsdDecoderHelper.decodeDsdFile(
          song,
          tag,
          updateGlobalState: updateGlobalState,
          onTransportResolved: onTransportResolved,
        );

      // 3. Compressed Standard Formats
      case 'mp3':
      case 'aac':
      case 'ogg':
      case 'opus':
      default:
        onTransportResolved?.call(false, false);
        return AudioSource.uri(Uri.file(song.path), tag: tag);
    }
  }
}
