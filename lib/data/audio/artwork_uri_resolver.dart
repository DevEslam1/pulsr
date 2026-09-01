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

  static void _putLru(LinkedHashMap<int, Uri> map, int key, Uri value) {
    if (map.containsKey(key)) {
      map.remove(key);
    } else if (map.length >= _maxCacheSize) {
      final oldestKey = map.keys.first;
      final oldestUri = map.remove(oldestKey);
      if (oldestUri != null && oldestUri.scheme == 'file') {
        File(oldestUri.toFilePath()).exists().then((exists) {
          if (exists) {
            File(oldestUri.toFilePath()).delete().ignore();
          }
        }).catchError((Object e, StackTrace st) {
          ErrorLogger.log('Failed to delete evicted artwork temp file',
              error: e, stackTrace: st, category: 'ArtworkUriResolver');
        });
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

  static const List<int> _placeholderJpegBytes = [
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
    0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
    0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
    0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
    0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
    0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
    0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
    0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
    0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0A, 0x0B, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F,
    0x00, 0xBF, 0x80, 0xFF, 0xD9
  ];

  static Future<Uri> getPlaceholderArtworkUri() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/pulsr_placeholder.jpg');
      if (!await file.exists()) {
        await file.writeAsBytes(_placeholderJpegBytes, flush: true);
      }
      return Uri.file(file.path);
    } catch (e, st) {
      ErrorLogger.log('Failed to create placeholder artwork file',
          error: e, stackTrace: st, category: 'ArtworkUriResolver');
      return Uri.parse('file:///pulsr_placeholder.jpg');
    }
  }

  static Future<Uri?> getArtworkUri(int songId) async {
    if (_cachedArtworkUris.containsKey(songId)) {
      final uri = _cachedArtworkUris.remove(songId)!;
      _cachedArtworkUris[songId] = uri;
      return uri;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/pulsr_art_$songId.jpg');
      if (await file.exists()) {
        final uri = Uri.file(file.path);
        _putLru(_cachedArtworkUris, songId, uri);
        return uri;
      }
      final bytes = await _audioQuery.queryArtwork(
        songId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 800,
        quality: 95,
      );
      if (bytes != null && bytes.isNotEmpty) {
        await file.writeAsBytes(bytes, flush: true);
        final uri = Uri.file(file.path);
        _putLru(_cachedArtworkUris, songId, uri);
        return uri;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to resolve artwork URI for song ID: $songId',
          error: e, stackTrace: st, category: 'ArtworkUriResolver');
    }
    return null;
  }

  static Future<Uri?> getAlbumArtUri(int albumId) async {
    if (_cachedAlbumArtUris.containsKey(albumId)) {
      final uri = _cachedAlbumArtUris.remove(albumId)!;
      _cachedAlbumArtUris[albumId] = uri;
      return uri;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/pulsr_album_art_$albumId.jpg');
      if (await file.exists()) {
        final uri = Uri.file(file.path);
        _putLru(_cachedAlbumArtUris, albumId, uri);
        return uri;
      }
      final bytes = await _audioQuery.queryArtwork(
        albumId,
        ArtworkType.ALBUM,
        format: ArtworkFormat.JPEG,
        size: 800,
        quality: 95,
      );
      if (bytes != null && bytes.isNotEmpty) {
        await file.writeAsBytes(bytes, flush: true);
        final uri = Uri.file(file.path);
        _putLru(_cachedAlbumArtUris, albumId, uri);
        return uri;
      }
    } catch (e, st) {
      ErrorLogger.log(
          'Failed to resolve album artwork URI for album ID: $albumId',
          error: e,
          stackTrace: st,
          category: 'ArtworkUriResolver');
    }
    return null;
  }

  static Future<Uri?> getArtistArtUri(int artistId) async {
    if (_cachedArtistArtUris.containsKey(artistId)) {
      final uri = _cachedArtistArtUris.remove(artistId)!;
      _cachedArtistArtUris[artistId] = uri;
      return uri;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/pulsr_artist_art_$artistId.jpg');
      if (await file.exists()) {
        final uri = Uri.file(file.path);
        _putLru(_cachedArtistArtUris, artistId, uri);
        return uri;
      }
      final bytes = await _audioQuery.queryArtwork(
        artistId,
        ArtworkType.ARTIST,
        format: ArtworkFormat.JPEG,
        size: 800,
        quality: 95,
      );
      if (bytes != null && bytes.isNotEmpty) {
        await file.writeAsBytes(bytes, flush: true);
        final uri = Uri.file(file.path);
        _putLru(_cachedArtistArtUris, artistId, uri);
        return uri;
      }
    } catch (e, st) {
      ErrorLogger.log(
          'Failed to resolve artist artwork URI for artist ID: $artistId',
          error: e,
          stackTrace: st,
          category: 'ArtworkUriResolver');
    }
    return null;
  }

  /// Resolves YouTube thumbnail fallback chain (maxresdefault -> hqdefault -> mqdefault)
  static String normalizeYtmThumbnail(String url) {
    if (url.contains('ytimg.com/vi/')) {
      // If maxresdefault is present, provide fallback to hqdefault which is universally present
      if (url.contains('maxresdefault.jpg')) {
        return url;
      }
    }
    return url;
  }

  /// Resolves the artwork URI for [song] with a bounded 2s timeout.
  /// Always returns a valid URI (falls back to local placeholder file).
  static Future<Uri> resolveArtworkUri(
    SongsTableData song, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final result = await _resolveInternal(song).timeout(timeout);
      if (result != null) {
        return result;
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Artwork resolution timed out or failed for song: ${song.id} (${song.title})',
        error: e,
        stackTrace: st,
        category: 'ArtworkUriResolver',
      );
    }
    return await getPlaceholderArtworkUri();
  }

  static Future<Uri?> _resolveInternal(SongsTableData song) async {
    // Remote tracks have no MediaStore id, so querying would be a wasted IPC.
    final remoteUrl = song.remoteArtworkUrl;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      final normalized = normalizeYtmThumbnail(remoteUrl);
      final parsed = Uri.tryParse(normalized);
      if (parsed != null &&
          parsed.hasScheme &&
          (parsed.scheme == 'http' ||
              parsed.scheme == 'https' ||
              parsed.scheme == 'content' ||
              parsed.scheme == 'file')) {
        return parsed;
      }
    }
    var uri = await getArtworkUri(song.id);
    if (uri == null && song.albumId != null) {
      uri = await getAlbumArtUri(song.albumId!);
    }
    return uri;
  }
}
