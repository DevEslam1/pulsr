// lib/data/audio/triple_buffer_pipeline.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../db/app_database.dart';
import '../../core/utils/error_logger.dart';

/// 3-player architecture (Active, Preloaded, Prefetched) for zero-latency
/// transitions and lookahead caching.
class TripleBufferPipeline {
  final AudioPlayer activePlayer;
  final AudioPlayer preloadedPlayer;
  final AudioPlayer? prefetchPlayer;

  final Future<AudioSource> Function(SongsTableData song, MediaItem tag)
      resolveAudioSource;
  final MediaItem Function(SongsTableData song, [Uri? fastArtworkUri])
      songToMediaItem;

  TripleBufferPipeline({
    required this.activePlayer,
    required this.preloadedPlayer,
    this.prefetchPlayer,
    required this.resolveAudioSource,
    required this.songToMediaItem,
  });

  /// Preloads the next track into [preloadedPlayer] so crossfade starts with zero buffering delay.
  Future<void> preloadNext(SongsTableData nextSong) async {
    try {
      final tag = songToMediaItem(nextSong);
      final source = await resolveAudioSource(nextSong, tag);
      await preloadedPlayer.setAudioSource(source, preload: true);
    } catch (e) { ErrorLogger.log('Preload failed', error: e, category: 'TripleBuffer'); }
  }

  /// Prefetches track N+2 into [prefetchPlayer] without decoding ahead of time.
  Future<void> prefetchAhead(SongsTableData aheadSong) async {
    if (prefetchPlayer == null) return;
    try {
      final tag = songToMediaItem(aheadSong);
      final source = await resolveAudioSource(aheadSong, tag);
      await prefetchPlayer!.setAudioSource(source, preload: false);
    } catch (e) { ErrorLogger.log('Preload failed', error: e, category: 'TripleBuffer'); }
  }
}
