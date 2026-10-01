// lib/features/player/cubit/managers/player_lyrics_manager.dart
// FIX-A1: Modular Lyrics manager extracted from PlayerCubit
import 'dart:async';
import '../../../../core/services/lrclib_service.dart';
import '../../../../core/services/ytm_account_service.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/lrc_parser.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../player_constants.dart';

/// Owns multi-source lyrics fetching (local file, LRCLIB, YTM) with generation guards.
class PlayerLyricsManager {
  final LrclibService? _lrclibService;
  final YtmAccountService? _ytmAccountService;

  PlayerLyricsManager({
    LrclibService? lrclibService,
    YtmAccountService? ytmAccountService,
  })  : _lrclibService = lrclibService,
        _ytmAccountService = ytmAccountService;

  int _generation = 0;
  int get generation => _generation;

  int bumpGeneration() => ++_generation;

  /// Checks whether fresh positive cached lyrics exist in LrcParser cache.
  LyricsResult? getCachedLyrics(SongsTableData song) {
    if (!LrcParser.hasCachedLyrics(songId: song.id, path: song.path)) {
      return null;
    }
    return LrcParser.getCachedLyrics(songId: song.id, path: song.path);
  }

  /// Checks whether a fresh negative cache entry exists (lyrics were searched and not found within TTL).
  bool hasFreshNegativeCache(SongsTableData song) {
    if (!LrcParser.hasCachedLyrics(songId: song.id, path: song.path)) {
      return false;
    }
    final cached = LrcParser.getCachedLyrics(songId: song.id, path: song.path);
    if (cached != null) return false;
    final cacheTs = LrcParser.getCacheTimestamp(songId: song.id, path: song.path);
    return cacheTs != null &&
        DateTime.now().difference(cacheTs) <= PlayerConstants.lyricsNegativeCacheTtl;
  }

  /// Caches a negative lookup result so callers avoid hammering network APIs within TTL.
  void cacheNegativeResult(SongsTableData song) {
    LrcParser.cacheLyricsResult(null, songId: song.id, path: song.path);
  }

  /// Resolves lyrics from available sources (local metadata, LRCLIB, YTM).
  Future<LyricsResult?> resolveLyrics(
    SongsTableData song, {
    required bool isOfflineOnly,
    bool Function()? isStale,
  }) async {
    LyricsResult? result;

    // 1. Local metadata and sidecar .lrc files
    if (song.source == SongSource.local &&
        !song.path.startsWith('http') &&
        !song.path.startsWith('ytmusic://')) {
      try {
        result = await LrcParser.resolveLyrics(
          song.path,
          songId: song.id,
        );
      } catch (e, st) {
        ErrorLogger.log('Local lyrics resolution failed for ${song.path}',
            error: e, stackTrace: st, category: 'PlayerLyricsManager');
      }
    }

    if (isStale != null && isStale()) return null;

    // 2. Query LRCLIB
    final hasSynced = result != null && result.lines.isNotEmpty && result.isSynced;
    final lrclib = _lrclibService;
    if (!hasSynced && !isOfflineOnly && lrclib != null) {
      try {
        final onlineResult = await lrclib.fetchLyrics(
          trackName: song.title,
          artistName: song.artist,
          albumName: song.album,
          durationSeconds: song.durationMs > 0 ? song.durationMs ~/ 1000 : null,
        );
        if (onlineResult != null && onlineResult.lines.isNotEmpty) {
          result = onlineResult;
          LrcParser.cacheLyricsResult(
            onlineResult,
            songId: song.id,
            path: song.path,
          );
        }
      } catch (e, st) {
        ErrorLogger.log('LRCLIB fetch failed for ${song.title}',
            error: e, stackTrace: st, category: 'PlayerLyricsManager');
      }
    }

    if (isStale != null && isStale()) return null;

    // 3. Fallback to YTM lyrics
    final ytmAccount = _ytmAccountService;
    if ((result == null || result.lines.isEmpty) &&
        !isOfflineOnly &&
        ytmAccount != null) {
      final remoteId = song.remoteId;
      if (remoteId != null && remoteId.isNotEmpty) {
        try {
          final ytmResult = await ytmAccount.fetchYtmLyrics(remoteId);
          if (ytmResult != null && ytmResult.lines.isNotEmpty) {
            result = ytmResult;
            LrcParser.cacheLyricsResult(
              ytmResult,
              songId: song.id,
              path: song.path,
            );
          }
        } catch (e, st) {
          ErrorLogger.log('YTM lyrics fetch failed for $remoteId',
              error: e, stackTrace: st, category: 'PlayerLyricsManager');
        }
      }
    }

    if ((result == null || result.lines.isEmpty) && !isOfflineOnly) {
      cacheNegativeResult(song);
    }

    return result;
  }
}
