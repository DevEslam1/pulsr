import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mutex/mutex.dart';
import '../db/app_database.dart';
import '../../core/utils/error_logger.dart';

enum PlayerClaim { none, crossfade, prefetch }

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

  final Mutex _claimMutex = Mutex();
  PlayerClaim _inactiveClaim = PlayerClaim.none;
  PlayerClaim get inactiveClaim => _inactiveClaim;

  Future<bool> claimInactive(PlayerClaim claim) async {
    return _claimMutex.protect(() async {
      if (_inactiveClaim != PlayerClaim.none && _inactiveClaim != claim) {
        return false;
      }
      _inactiveClaim = claim;
      return true;
    });
  }

  void releaseInactive(PlayerClaim claim) {
    if (_inactiveClaim == claim) {
      _inactiveClaim = PlayerClaim.none;
    }
  }

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
      if (!await claimInactive(PlayerClaim.prefetch)) return;
      final tag = songToMediaItem(nextSong);
      final source = await resolveAudioSource(nextSong, tag);
      // The await above can outlast the track that scheduled this preload;
      // never touch a player that is no longer the inactive one.
      if (isLoadStillValid != null && !isLoadStillValid!()) {
        releaseInactive(PlayerClaim.prefetch);
        return;
      }
      // Re-acquire the inactive player reference AFTER the async gap — the
      // active/inactive players may have swapped during URL resolution.
      final inactivePlayer = getInactivePlayer();
      await inactivePlayer.setAudioSource(source, preload: true);
    } catch (e) {
      ErrorLogger.log('Preload failed', error: e, category: 'TripleBuffer');
    } finally {
      releaseInactive(PlayerClaim.prefetch);
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
