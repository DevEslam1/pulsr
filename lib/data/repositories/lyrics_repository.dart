// lib/data/repositories/lyrics_repository.dart
import 'dart:async';
import 'package:injectable/injectable.dart';
import '../../core/di/injection.dart';
import '../../core/services/lrclib_service.dart';
import '../../core/services/ytm_account_service.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/lrc_parser.dart';
import '../../domain/models/lyrics_line.dart';

/// Repository for fetching synchronized and plain lyrics from remote providers
/// (LRCLIB and YouTube Music).
@lazySingleton
class LyricsRepository {
  final LrclibService? _lrclibService;
  final YtmAccountService? _ytmAccountService;

  LyricsRepository({
    LrclibService? lrclibService,
    YtmAccountService? ytmAccountService,
  })  : _lrclibService = lrclibService,
        _ytmAccountService = ytmAccountService;

  LrclibService? get _effectiveLrclib =>
      _lrclibService ??
      (getIt.isRegistered<LrclibService>() ? getIt<LrclibService>() : null);

  YtmAccountService? get _effectiveYtmAccount =>
      _ytmAccountService ??
      (getIt.isRegistered<YtmAccountService>()
          ? getIt<YtmAccountService>()
          : null);

  /// Looks up lyrics for a track across available providers.
  /// First checks LRCLIB, then falls back to YouTube Music lyrics if videoId is provided.
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    int? durationMs,
    String? videoId,
  }) async {
    // 1. Try LRCLIB
    final lrclib = _effectiveLrclib;
    if (lrclib != null && title.trim().isNotEmpty && artist.trim().isNotEmpty) {
      try {
        final durationSec =
            (durationMs != null && durationMs > 0) ? durationMs ~/ 1000 : null;
        final res = await lrclib
            .fetchLyrics(
              trackName: title.trim(),
              artistName: artist.trim(),
              albumName: album?.trim(),
              durationSeconds: durationSec,
            )
            .timeout(const Duration(seconds: 8));
        if (res != null && res.lines.isNotEmpty) {
          return res;
        }
      } catch (e, st) {
        ErrorLogger.log('LyricsRepository LRCLIB fetch failed for "$title"',
            error: e, stackTrace: st, category: 'Lyrics');
      }
    }

    // 2. Try YTM lyrics if videoId is available
    final ytm = _effectiveYtmAccount;
    if (ytm != null && videoId != null && videoId.trim().isNotEmpty) {
      try {
        final res = await ytm
            .fetchYtmLyrics(videoId.trim())
            .timeout(const Duration(seconds: 8));
        if (res != null && res.lines.isNotEmpty) {
          return res;
        }
      } catch (e, st) {
        ErrorLogger.log('LyricsRepository YTM fetch failed for $videoId',
            error: e, stackTrace: st, category: 'Lyrics');
      }
    }

    return null;
  }

  /// Fetches lyrics and formats them as standard LRC text (or plain text if unsynced).
  Future<String?> fetchLyricsLrc({
    required String title,
    required String artist,
    String? album,
    int? durationMs,
    String? videoId,
  }) async {
    final result = await fetchLyrics(
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      videoId: videoId,
    );
    if (result == null || result.lines.isEmpty) return null;

    if (result.isSynced) {
      return LrcParser.formatToLrc(result.lines);
    } else {
      return result.lines.map((l) => l.text).join('\n');
    }
  }
}
