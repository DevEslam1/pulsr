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
        await file.writeAsBytes(bytes);
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
        await file.writeAsBytes(bytes);
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
        await file.writeAsBytes(bytes);
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

  static Future<Uri?> resolveArtworkUri(SongsTableData song) async {
    // Remote tracks have no MediaStore id, so querying would be a wasted IPC.
    final remoteUrl = song.remoteArtworkUrl;
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
    var uri = await getArtworkUri(song.id);
    if (uri == null && song.albumId != null) {
      uri = await getAlbumArtUri(song.albumId!);
    }
    return uri;
  }
}
