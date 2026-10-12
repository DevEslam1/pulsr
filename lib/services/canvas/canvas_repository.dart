// lib/services/canvas/canvas_repository.dart
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:mutex/mutex.dart';
import '../../core/utils/error_logger.dart';
import '../../data/db/app_database.dart';
import 'apple_music_canvas.dart';
import 'canvas_artwork.dart';
import 'canvas_cache.dart';
import 'community_canvas.dart';
import 'tidal_canvas.dart';

export 'canvas_artwork.dart';
export 'canvas_cache.dart';

/// Central repository resolving Spotify Canvas, Apple Music motion artwork,
/// and Tidal video covers with a 150 MB LRU disk cache.
class CanvasRepository {
  CanvasRepository({
    http.Client? client,
    CanvasCache? cache,
    CommunityCanvas? communityCanvas,
    AppleMusicCanvas? appleMusicCanvas,
    TidalCanvas? tidalCanvas,
  })  : _cache = cache ?? CanvasCache(client: client),
        _community = communityCanvas ?? CommunityCanvas(client: client),
        _apple = appleMusicCanvas ?? AppleMusicCanvas(client: client),
        _tidal = tidalCanvas ?? TidalCanvas(client: client);

  static final CanvasRepository instance = CanvasRepository();

  final CanvasCache _cache;
  final CommunityCanvas _community;
  final AppleMusicCanvas _apple;
  final TidalCanvas _tidal;

  final Mutex _lock = Mutex();

  CanvasCache get cache => _cache;

  /// Returns already-resolved canvas from memory immediately without network.
  CanvasArtwork? cached(SongsTableData song) {
    final key = _cacheKey(song.title, song.artist, song.album);
    return _cache.getFromMemory(key);
  }

  /// Resolves the canvas for [song]. Queries Community, Apple Music, and Tidal
  /// in sequence until one hits. Downloads & caches the resulting MP4 clip to disk.
  Future<CanvasArtwork?> canvasFor(
    SongsTableData song, {
    bool downloadToDisk = true,
  }) async {
    return canvasForTrack(
      title: song.title,
      artist: song.artist,
      album: song.album,
      downloadToDisk: downloadToDisk,
    );
  }

  /// Resolves the canvas for a track by metadata.
  Future<CanvasArtwork?> canvasForTrack({
    required String title,
    required String artist,
    String? album,
    bool downloadToDisk = true,
  }) async {
    final cleanTitle = cleanNoise(title);
    final cleanArtist = artist.trim();
    if (cleanTitle.isEmpty || cleanArtist.isEmpty) return null;

    final key = _cacheKey(cleanTitle, cleanArtist, album);

    return _lock.protect(() async {
      // 1. Check in-memory cache (including negative caching)
      if (_cache.hasInMemory(key)) {
        final mem = _cache.getFromMemory(key);
        if (mem != null && downloadToDisk && mem.localFilePath == null) {
          final local = await _cache.getOrDownloadVideo(mem.videoUrl);
          if (local != null) {
            final updated = mem.copyWith(localFilePath: local);
            _cache.putInMemory(key, updated);
            return updated;
          }
        }
        return mem;
      }

      // 2. Query sources in order
      CanvasArtwork? hit;

      // Source 1: Community Canvas manifest
      try {
        final candidate = await _community.search(cleanTitle, cleanArtist, album);
        if (candidate != null &&
            candidate.matches(cleanTitle, cleanArtist, album)) {
          hit = candidate;
        }
      } catch (e, st) {
        ErrorLogger.log('Community canvas search failed',
            error: e, stackTrace: st, category: 'CanvasRepository');
      }

      // Source 2: Apple Music motion artwork
      if (hit == null) {
        try {
          final candidate = await _apple.search(cleanTitle, cleanArtist, album);
          if (candidate != null &&
              candidate.matches(cleanTitle, cleanArtist, album)) {
            hit = candidate;
          }
        } catch (e, st) {
          ErrorLogger.log('Apple Music canvas search failed',
              error: e, stackTrace: st, category: 'CanvasRepository');
        }
      }

      // Source 3: Tidal canvas video search
      if (hit == null) {
        try {
          final candidate = await _tidal.search(cleanTitle, cleanArtist, album);
          if (candidate != null &&
              candidate.matches(cleanTitle, cleanArtist, album)) {
            hit = candidate;
          }
        } catch (e, st) {
          ErrorLogger.log('Tidal canvas search failed',
              error: e, stackTrace: st, category: 'CanvasRepository');
        }
      }

      // 3. Download & Cache to disk if found
      if (hit != null && downloadToDisk) {
        try {
          final localPath = await _cache.getOrDownloadVideo(hit.videoUrl);
          if (localPath != null) {
            hit = hit.copyWith(localFilePath: localPath);
          }
        } catch (e, st) {
          ErrorLogger.log('Canvas video download to disk failed',
              error: e, stackTrace: st, category: 'CanvasRepository');
        }
      }

      // 4. Cache answer (including misses)
      _cache.putInMemory(key, hit);

      return hit;
    });
  }

  /// Resolves the canvas for a release / album page.
  Future<CanvasArtwork?> canvasForAlbum({
    required String album,
    required String artist,
    bool downloadToDisk = true,
  }) async {
    final cleanAlbum = cleanNoise(album);
    final cleanArtist = artist.trim();
    if (cleanAlbum.isEmpty || cleanArtist.isEmpty) return null;

    final key = 'album|$cleanAlbum|$cleanArtist';

    return _lock.protect(() async {
      if (_cache.hasInMemory(key)) {
        final mem = _cache.getFromMemory(key);
        if (mem != null && downloadToDisk && mem.localFilePath == null) {
          final local = await _cache.getOrDownloadVideo(mem.videoUrl);
          if (local != null) {
            final updated = mem.copyWith(localFilePath: local);
            _cache.putInMemory(key, updated);
            return updated;
          }
        }
        return mem;
      }

      CanvasArtwork? hit;

      // Source 1: Community
      try {
        final candidate = await _community.searchAlbum(cleanAlbum, cleanArtist);
        if (candidate != null &&
            candidate.matches(cleanAlbum, cleanArtist, cleanAlbum)) {
          hit = candidate;
        }
      } catch (_) {}

      // Source 2: Apple Music
      if (hit == null) {
        try {
          final candidate = await _apple.searchAlbum(cleanAlbum, cleanArtist);
          if (candidate != null &&
              candidate.matches(cleanAlbum, cleanArtist, cleanAlbum)) {
            hit = candidate;
          }
        } catch (_) {}
      }

      // Source 3: Tidal
      if (hit == null) {
        try {
          final candidate = await _tidal.searchAlbum(cleanAlbum, cleanArtist);
          if (candidate != null &&
              candidate.matches(cleanAlbum, cleanArtist, cleanAlbum)) {
            hit = candidate;
          }
        } catch (_) {}
      }

      if (hit != null && downloadToDisk) {
        try {
          final localPath = await _cache.getOrDownloadVideo(hit.videoUrl);
          if (localPath != null) {
            hit = hit.copyWith(localFilePath: localPath);
          }
        } catch (_) {}
      }

      _cache.putInMemory(key, hit);
      return hit;
    });
  }

  String _cacheKey(String title, String artist, String? album) =>
      'song|${normalizeForMatch(title)}|${normalizeForMatch(artist)}|${album != null ? normalizeForMatch(album) : ''}';
}
