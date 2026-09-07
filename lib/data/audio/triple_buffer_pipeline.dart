// lib/data/audio/triple_buffer_pipeline.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../db/app_database.dart';
import '../../core/utils/error_logger.dart';

/// 3-player architecture (Active, Preloaded, Prefetched) for zero-latency
/// transitions and lookahead caching.
class TripleBufferPipeline {
  final AudioPlayer Function() getActivePlayer;
  final AudioPlayer Function() getInactivePlayer;
  final AudioPlayer? prefetchPlayer;

  final Future<AudioSource> Function(SongsTableData song, MediaItem tag)
      resolveAudioSource;
  final MediaItem Function(SongsTableData song, [Uri? fastArtworkUri])
      songToMediaItem;

  /// Called after the (possibly slow) source resolve and again right before
  /// [AudioPlayer.setAudioSource]; when it returns false the preload is
  /// abandoned. Without this guard a YouTube resolve that takes seconds can
  /// complete after the dual-player engine has already loaded/played or
  /// swapped that same player, clobbering live playback.
  final bool Function()? isLoadStillValid;

  TripleBufferPipeline({
    required this.getActivePlayer,
    required this.getInactivePlayer,
    this.prefetchPlayer,
    this.isLoadStillValid,
    required this.resolveAudioSource,
    required this.songToMediaItem,
  });

  /// Preloads the next track into inactive player so crossfade starts with zero buffering delay.
  Future<void> preloadNext(SongsTableData nextSong) async {
    try {
      final inactivePlayer = getInactivePlayer();
      final tag = songToMediaItem(nextSong);
      final source = await resolveAudioSource(nextSong, tag);
      // The await above can outlast the track that scheduled this preload;
      // never touch a player that is no longer the inactive one.
      if (isLoadStillValid != null && !isLoadStillValid!()) return;
      await inactivePlayer.setAudioSource(source, preload: true);
    } catch (e) {
      ErrorLogger.log('Preload failed', error: e, category: 'TripleBuffer');
    }
  }

  /// Prefetches track N+2 into [prefetchPlayer] without decoding ahead of time.
  Future<void> prefetchAhead(SongsTableData aheadSong) async {
    if (prefetchPlayer == null) return;
    try {
      final tag = songToMediaItem(aheadSong);
      final source = await resolveAudioSource(aheadSong, tag);
      await prefetchPlayer!.setAudioSource(source, preload: false);
    } catch (e) {
      ErrorLogger.log('Preload failed', error: e, category: 'TripleBuffer');
    }
  }
}
