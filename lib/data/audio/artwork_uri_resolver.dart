// lib/data/audio/artwork_uri_resolver.dart
import 'dart:collection';
import 'dart:io';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/error_logger.dart';
import '../db/app_database.dart';

class ArtworkUriResolver {
  static final OnAudioQuery _audioQuery = OnAudioQuery();
  static const int _maxCacheSize = 100;

  static final LinkedHashMap<int, Uri> _cachedArtworkUris = LinkedHashMap();
  static final LinkedHashMap<int, Uri> _cachedAlbumArtUris = LinkedHashMap();
  static final LinkedHashMap<int, Uri> _cachedArtistArtUris = LinkedHashMap();
  static final Map<int, Future<Uri?>> _inFlightArtwork = {};
  static final Map<int, Future<Uri?>> _inFlightAlbumArt = {};
  static final Map<int, Future<Uri?>> _inFlightArtistArt = {};

  static void _putLru(LinkedHashMap<int, Uri> map, int key, Uri value) {
    if (map.containsKey(key)) {
      map.remove(key);
    } else if (map.length >= _maxCacheSize) {
      final evictedKey = map.keys.first;
      final evictedUri = map.remove(evictedKey);
      // Issue 21: Cap disk-cache size by deleting evicted artwork temp files
      if (evictedUri != null && evictedUri.isScheme('file')) {
        try {
          final f = File(evictedUri.toFilePath());
          if (f.existsSync()) f.delete().ignore();
        } catch (_) {}
      }
    }
    map[key] = value;
  }

  static Future<void> cleanupTempArtwork() async {
    try {
      final tempDir = await getTemporaryDirectory();
      await for (final entity in tempDir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : '';
          if (name.startsWith('pulsr_art_') ||
              name.startsWith('pulsr_album_art_') ||
              name.startsWith('pulsr_artist_art_')) {
            try {
              await entity.delete();
            } catch (e, st) {
              ErrorLogger.log(
                  'Failed to delete temp artwork file during cleanup: $name',
                  error: e,
                  stackTrace: st,
                  category: 'ArtworkUriResolver');
            }
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to cleanup temp artwork directory',
          error: e, stackTrace: st, category: 'ArtworkUriResolver');
    }
    try {
      _cachedArtworkUris.clear();
      _cachedAlbumArtUris.clear();
      _cachedArtistArtUris.clear();
    } catch (_) {}
  }

  static Uri? getCachedArtworkUri(int songId) => _cachedArtworkUris[songId];
  static Uri? getCachedAlbumArtUri(int albumId) => _cachedAlbumArtUris[albumId];

  /// A cached file:// URI can outlive its file (the OS may purge the cache
  /// directory at any time); handing that out leaves a blank notification
  /// image until the app restarts.
  static bool _stillUsable(Uri uri) {
    if (!uri.isScheme('file')) return true;
    try {
      return File(uri.toFilePath()).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Shared lookup for song / album / artist artwork: LRU cache -> in-flight
  /// de-duplication -> temp-file cache -> MediaStore query. The three public
  /// getters were previously three copies of this body.
  static Future<Uri?> _resolve({
    required int id,
    required ArtworkType type,
    required String filePrefix,
    required LinkedHashMap<int, Uri> cache,
    required Map<int, Future<Uri?>> inFlight,
    required String label,
  }) async {
    // 0 / negative ids mean "unknown"; querying them is a wasted IPC at best
    // and can return an unrelated item's artwork at worst.
    if (id <= 0) return null;

    final cached = cache.remove(id);
    if (cached != null) {
      if (_stillUsable(cached)) {
        cache[id] = cached; // refresh LRU position
        return cached;
      }
      // Stale entry: fall through and rebuild it.
    }

    final pending = inFlight[id];
    if (pending != null) return await pending;

    final future = () async {
      try {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$filePrefix$id.jpg');
        if (await file.exists() && (await file.length()) > 0) {
          final uri = Uri.file(file.path);
          _putLru(cache, id, uri);
          return uri;
        }
        final bytes = await _audioQuery.queryArtwork(
          id,
          type,
          format: ArtworkFormat.JPEG,
          size: 800,
          quality: 95,
        );
        if (bytes != null && bytes.isNotEmpty) {
          // Write to a temp name and rename so a concurrent reader (or a crash
          // mid-write) can never observe a truncated image that still passes
          // the `length() > 0` check above.
          final tmp = File('${file.path}.tmp');
          await tmp.writeAsBytes(bytes, flush: true);
          await tmp.rename(file.path);
          final uri = Uri.file(file.path);
          _putLru(cache, id, uri);
          return uri;
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to resolve $label URI for ID: $id',
            error: e, stackTrace: st, category: 'ArtworkUriResolver');
      }
      return null;
    }();

    inFlight[id] = future;
    try {
      return await future;
    } finally {
      inFlight.remove(id);
    }
  }

  static Future<Uri?> getArtworkUri(int songId) => _resolve(
        id: songId,
        type: ArtworkType.AUDIO,
        filePrefix: 'pulsr_art_',
        cache: _cachedArtworkUris,
        inFlight: _inFlightArtwork,
        label: 'artwork',
      );

  static Future<Uri?> getAlbumArtUri(int albumId) => _resolve(
        id: albumId,
        type: ArtworkType.ALBUM,
        filePrefix: 'pulsr_album_art_',
        cache: _cachedAlbumArtUris,
        inFlight: _inFlightAlbumArt,
        label: 'album artwork',
      );

  static Future<Uri?> getArtistArtUri(int artistId) => _resolve(
        id: artistId,
        type: ArtworkType.ARTIST,
        filePrefix: 'pulsr_artist_art_',
        cache: _cachedArtistArtUris,
        inFlight: _inFlightArtistArt,
        label: 'artist artwork',
      );

  static Future<Uri?> resolveArtworkUri(SongsTableData song) async {
    // Remote tracks have no MediaStore id, so querying would be a wasted IPC.
    final remoteUrl =
        (song.remoteArtworkUrl != null && song.remoteArtworkUrl!.isNotEmpty)
            ? song.remoteArtworkUrl
            : song.artworkUri;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      final parsed = Uri.tryParse(remoteUrl);
      if (parsed != null &&
          parsed.hasScheme &&
          (parsed.scheme == 'http' ||
              parsed.scheme == 'https' ||
              parsed.scheme == 'content' ||
              parsed.scheme == 'file')) {
        return parsed;
      }
    }

    // A remote (YouTube) row's local id is just a DB autoincrement value. It
    // can collide with a real MediaStore id and return some unrelated local
    // song's cover, so never fall back to MediaStore for remote rows.
    final remoteId = song.remoteId;
    if (remoteId != null && remoteId.isNotEmpty) return null;

    var uri = await getArtworkUri(song.id);
    if (uri == null && song.albumId != null) {
      uri = await getAlbumArtUri(song.albumId!);
    }
    return uri;
  }
}
