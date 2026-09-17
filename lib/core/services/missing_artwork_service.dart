// lib/core/services/missing_artwork_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/db/app_database.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../config/app_config.dart';
import '../di/injection.dart';
import '../utils/error_logger.dart';

class _ArtworkRateLimiter {
  final int maxRequests;
  final Duration interval;
  final List<DateTime> _timestamps = [];

  _ArtworkRateLimiter({this.maxRequests = 5, Duration? interval})
      : interval = interval ?? const Duration(seconds: 1);

  Future<void> acquire() async {
    while (true) {
      final now = DateTime.now();
      _timestamps.removeWhere((t) => now.difference(t) > interval);
      if (_timestamps.length < maxRequests) {
        _timestamps.add(now);
        return;
      }
      final oldest = _timestamps.first;
      final waitMs = interval.inMilliseconds - now.difference(oldest).inMilliseconds + 10;
      if (waitMs > 0) {
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
  }
}

@singleton
class MissingArtworkService {
  final http.Client _client;
  final _ArtworkRateLimiter _rateLimiter = _ArtworkRateLimiter(maxRequests: 5);

  MissingArtworkService([http.Client? client])
      : _client = client ?? http.Client();

  void dispose() {
    _client.close();
  }

  /// Scans albums and identifies those lacking artwork.
  List<AlbumsTableData> findMissingArtworkAlbums(
      List<AlbumsTableData> allAlbums) {
    return allAlbums.where((album) {
      return album.artworkUri == null || album.artworkUri!.isEmpty;
    }).toList();
  }

  /// Searches iTunes Cover Art API for missing album artwork with rate limiting & exponential backoff.
  /// Returns null immediately when offline-only mode is enabled.
  Future<String?> fetchArtworkForAlbum(
      String albumTitle, String artistName, {int maxRetries = 2}) async {
    try {
      if (!AppConfig.isCloudSyncAllowed) return null;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('setting_offline_only_mode') == true) return null;
    } catch (e, st) {
      ErrorLogger.log('Failed to read offline-only preference for artwork',
          error: e, stackTrace: st, category: 'MissingArtwork');
    }
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      await _rateLimiter.acquire();
      try {
        final query = '$albumTitle $artistName'.trim();
        final uri = Uri.parse(
            'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=album&limit=1');
        final res = await _client.get(uri).timeout(const Duration(seconds: 8));

        if (res.statusCode == 429) {
          if (attempt < maxRetries) {
            await Future.delayed(Duration(milliseconds: 1000 * (attempt + 1)));
            continue;
          }
          return null;
        }

        if (res.statusCode == 200) {
          final jsonMap = json.decode(res.body);
          final results = jsonMap['results'] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            final first = results.first;
            final rawUrl = first['artworkUrl100'] as String?;
            if (rawUrl != null) {
              // Replace 100x100 with 600x600 HD artwork
              return rawUrl.replaceAll('100x100bb.jpg', '600x600bb.jpg');
            }
          }
          return null;
        }
      } catch (e, st) {
        if (attempt == maxRetries) {
          ErrorLogger.log('Failed to fetch artwork for $albumTitle after retries',
              error: e, stackTrace: st, category: 'MissingArtworkService');
        } else {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }
    return null;
  }

  /// Fetches artwork for a list of albums in batches of 5 with 500ms delay and progress callback.
  Future<Map<int, String>> batchFetchArtwork(
    List<AlbumsTableData> albums, {
    void Function(int processed, int total)? onProgress,
  }) async {
    final results = <int, String>{};
    final total = albums.length;
    int processed = 0;

    for (int i = 0; i < albums.length; i += 5) {
      final batch = albums.sublist(i, (i + 5).clamp(0, albums.length));
      final batchFutures = batch.map((album) async {
        final url = await fetchArtworkForAlbum(album.title, album.artist);
        if (url != null) {
          results[album.id] = url;
        }
      });
      await Future.wait(batchFutures);
      processed += batch.length;
      onProgress?.call(processed, total);

      if (i + 5 < albums.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    return results;
  }

  /// Finds albums without artwork, looks each one up on iTunes and writes every
  /// resolved URL back to the `albums` table. Returns the number of albums
  /// updated. No-ops (returns 0) when offline-only mode is enabled.
  Future<int> fetchAndPersistMissingArtwork({
    void Function(int processed, int total)? onProgress,
  }) async {
    try {
      if (!AppConfig.isCloudSyncAllowed) return 0;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('setting_offline_only_mode') == true) return 0;
    } catch (e, st) {
      ErrorLogger.log('Failed to read offline-only preference for artwork',
          error: e, stackTrace: st, category: 'MissingArtwork');
    }

    if (!getIt.isRegistered<IMusicRepository>()) return 0;
    final repo = getIt<IMusicRepository>();

    final albumsRes = await repo.getAlbums();
    final albums = albumsRes.fold((_) => const <AlbumsTableData>[], (r) => r);
    final missing = findMissingArtworkAlbums(albums);
    if (missing.isEmpty) return 0;

    final fetched = await batchFetchArtwork(missing, onProgress: onProgress);

    int persisted = 0;
    for (final entry in fetched.entries) {
      final res = await repo.updateAlbumArtwork(entry.key, entry.value);
      res.fold((_) {}, (_) {
        persisted++;
      });
    }
    return persisted;
  }
}
