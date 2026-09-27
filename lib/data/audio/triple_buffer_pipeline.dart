import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mutex/mutex.dart';
import '../db/app_database.dart';
import '../../core/utils/error_logger.dart';
import 'playback_analytics.dart';

enum PlayerClaim { none, crossfade, prefetch }

/// 3-player architecture (Active, Preloaded, Prefetched) for zero-latency
/// transitions and lookahead caching.
class TripleBufferPipeline {
  final AudioPlayer Function() getActivePlayer;
  final AudioPlayer Function() getInactivePlayer;
  final AudioPlayer? prefetchPlayer;
  final PlaybackAnalytics? analytics;

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

  /// Monotonic play epoch from the handler. Captured at preload schedule time
  /// so a resolve that outlives its track is abandoned even when the
  /// active/inactive player pair hasn't swapped (the old `identical` check was
  /// always true for distinct objects, so generation is the real guard).
  final int Function()? getGeneration;

  final Mutex _claimMutex = Mutex();
  PlayerClaim _inactiveClaim = PlayerClaim.none;
  PlayerClaim get inactiveClaim => _inactiveClaim;

  int? _preloadedSongId;
  int? get preloadedSongId => _preloadedSongId;
  AudioSource? _preloadedSource;
  AudioSource? get preloadedSource => _preloadedSource;
  Uint8List? preloadedHeaderBytes;

  final Map<int, DateTime> _preloadFailedExpiry = {};

  bool isPreloadBlacklisted(int songId) {
    final expiry = _preloadFailedExpiry[songId];
    if (expiry == null) return false;
    if (DateTime.now().isAfter(expiry)) {
      _preloadFailedExpiry.remove(songId);
      return false;
    }
    return true;
  }

  void recordPreloadFailure(int songId) {
    _preloadFailedExpiry[songId] =
        DateTime.now().add(const Duration(seconds: 30));
  }

  void clearPreload() {
    _preloadedSongId = null;
    _preloadedSource = null;
    preloadedHeaderBytes = null;
  }

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
    this.analytics,
    this.isLoadStillValid,
    this.getGeneration,
    required this.resolveAudioSource,
    required this.songToMediaItem,
  });

  /// Preloads the next track into inactive player with 1 retry on failure
  /// and 30-second blacklisting on repeated failure.
  Future<void> preloadNext(SongsTableData nextSong) async {
    if (isPreloadBlacklisted(nextSong.id)) return;
    try {
      if (!await claimInactive(PlayerClaim.prefetch)) return;
      var success = await _attemptPreload(nextSong);
      if (!success) {
        // Retry once after 2 seconds
        await Future<void>.delayed(const Duration(seconds: 2));
        if (isLoadStillValid != null && !isLoadStillValid!()) {
          return;
        }
        success = await _attemptPreload(nextSong);
        if (!success) {
          _preloadFailedExpiry[nextSong.id] =
              DateTime.now().add(const Duration(seconds: 30));
          analytics?.recordPreloadFailure();
          return;
        }
      }
      _preloadFailedExpiry.remove(nextSong.id);
      analytics?.recordPreloadSuccess();
    } finally {
      releaseInactive(PlayerClaim.prefetch);
    }
  }

  Future<bool> _attemptPreload(SongsTableData nextSong) async {
    try {
      final scheduledGen = getGeneration?.call();
      final tag = songToMediaItem(nextSong);
      final source = await resolveAudioSource(nextSong, tag);
      // The await above can outlast the track that scheduled this preload;
      // never touch a player that is no longer the inactive one.
      if (scheduledGen != null && scheduledGen != getGeneration?.call()) {
        return false;
      }
      if (isLoadStillValid != null && !isLoadStillValid!()) {
        return false;
      }
      final inactivePlayer = getInactivePlayer();
      if (scheduledGen != null && scheduledGen != getGeneration?.call()) {
        return false;
      }
      await inactivePlayer.setAudioSource(source, preload: true);
      _preloadedSongId = nextSong.id;
      _preloadedSource = source;
      if (nextSong.path.isNotEmpty && !nextSong.path.startsWith('http')) {
        try {
          final file = File(nextSong.path);
          if (file.existsSync()) {
            final raf = file.openSync(mode: FileMode.read);
            try {
              final len = file.lengthSync();
              preloadedHeaderBytes = raf.readSync(len < 65536 ? len : 65536);
            } finally {
              raf.closeSync();
            }
          }
        } catch (_) {}
      }
      return true;
    } catch (e) {
      clearPreload();
      ErrorLogger.log('Preload attempt failed', error: e, category: 'TripleBuffer');
      return false;
    }
  }

  /// Prefetches track N+2 into [prefetchPlayer] without decoding ahead of time.
  Future<void> prefetchAhead(SongsTableData aheadSong) async {
    if (prefetchPlayer == null) return;
    try {
      final scheduledGen = getGeneration?.call();
      final tag = songToMediaItem(aheadSong);
      final source = await resolveAudioSource(aheadSong, tag);
      if (scheduledGen != null && scheduledGen != getGeneration?.call()) {
        return;
      }
      if (isLoadStillValid != null && !isLoadStillValid!()) {
        return;
      }
      await prefetchPlayer!.setAudioSource(source, preload: false);
    } catch (e) {
      ErrorLogger.log('Preload failed', error: e, category: 'TripleBuffer');
    }
  }
}
