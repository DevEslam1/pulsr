// lib/data/scanner/media_scanner_service.dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../db/app_database.dart';
import '../repositories/music_repository.dart';


@singleton
class MediaScannerService {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final MusicRepository _repository;

  MediaScannerService(this._repository);

  Future<bool> checkPermission() async {
    if (Platform.isAndroid) {
      final audio = await Permission.audio.status;
      final storage = await Permission.storage.status;
      return audio.isGranted || storage.isGranted;
    } else if (Platform.isIOS) {
      final status = await Permission.mediaLibrary.status;
      return status.isGranted;
    }
    return true;
  }

  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) return true;
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    } else if (Platform.isIOS) {
      final status = await Permission.mediaLibrary.request();
      return status.isGranted;
    }
    return true;
  }

  Future<int> scanDeviceLibrary({bool ignoreShortFiles = true, int minDurationSec = 30}) async {
    final hasPermission = await checkPermission();
    if (!hasPermission) {
      final granted = await requestPermission();
      if (!granted) return 0;
    }

    final excludedRes = await _repository.getExcludedFolderPaths();
    final excludedFolders = excludedRes.fold((l) => <String>[], (r) => r);

    // Query songs using on_audio_query
    final List<SongModel> songs = await _audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final List<SongsTableCompanion> songCompanions = [];
    final Map<int, AlbumsTableCompanion> albumMap = {};
    final Map<int, ArtistsTableCompanion> artistMap = {};
    final Set<int> validSongIds = {};

    final minDurationMs = ignoreShortFiles ? minDurationSec * 1000 : 0;

    for (final song in songs) {
      final duration = song.duration ?? 0;
      if (duration < minDurationMs) continue;

      final path = song.data;
      // Skip if within an excluded folder
      if (excludedFolders.any((folder) => path.startsWith(folder))) {
        continue;
      }

      final title = song.title.trim().isNotEmpty ? song.title.trim() : 'Unknown Song';
      final artist = (song.artist != null && song.artist!.trim().isNotEmpty && song.artist != '<unknown>')
          ? song.artist!.trim()
          : 'Unknown Artist';
      final album = (song.album != null && song.album!.trim().isNotEmpty && song.album != '<unknown>')
          ? song.album!.trim()
          : 'Unknown Album';

      final genreRaw = song.genre ?? song.getMap['genre']?.toString();
      final genre = (genreRaw != null && genreRaw.trim().isNotEmpty && genreRaw != '<unknown>')
          ? genreRaw.trim()
          : null;
      final yearRaw = song.getMap['year'];
      final int? year = yearRaw is int ? yearRaw : int.tryParse(yearRaw?.toString() ?? '');

      validSongIds.add(song.id);

      songCompanions.add(
        SongsTableCompanion(
          id: Value(song.id),
          title: Value(title),
          artist: Value(artist),
          artistId: Value(song.artistId),
          album: Value(album),
          albumId: Value(song.albumId),
          durationMs: Value(duration),
          path: Value(path),
          uri: Value(song.uri),
          trackNumber: Value(song.track),
          dateAdded: Value(song.dateAdded),
          fileSize: Value(song.size),
          artworkUri: Value(song.id.toString()),
          genre: Value(genre),
          year: Value(year),
        ),
      );

      // Aggregate Albums
      if (song.albumId != null) {
        albumMap[song.albumId!] = AlbumsTableCompanion(
          id: Value(song.albumId!),
          title: Value(album),
          artist: Value(artist),
          artistId: Value(song.artistId),
          songCount: Value((albumMap[song.albumId!]?.songCount.value ?? 0) + 1),
          artworkUri: Value(song.albumId.toString()),
        );
      }

      // Aggregate Artists
      if (song.artistId != null) {
        artistMap[song.artistId!] = ArtistsTableCompanion(
          id: Value(song.artistId!),
          name: Value(artist),
          songCount: Value((artistMap[song.artistId!]?.songCount.value ?? 0) + 1),
          artworkUri: Value(song.artistId.toString()),
        );
      }
    }

    await _repository.syncScannedMusic(
      songs: songCompanions,
      albums: albumMap.values.toList(),
      artists: artistMap.values.toList(),
    );

    // Clean up orphaned entries
    await _repository.cleanupOrphanedSongs(validSongIds);

    return songCompanions.length;
  }

  Future<void> rescanSingleFile(String path) async {
    const channel = MethodChannel('com.example.pulsr/tag_editor');
    try {
      final Map<dynamic, dynamic>? tags = await channel.invokeMapMethod<dynamic, dynamic>('readTags', {'path': path});
      if (tags != null) {
        final title = (tags['title'] as String?)?.trim();
        final artist = (tags['artist'] as String?)?.trim();
        final album = (tags['album'] as String?)?.trim();
        final genre = (tags['genre'] as String?)?.trim();
        final yearStr = (tags['year'] as String?)?.trim();
        final trackStr = (tags['trackNumber'] as String?)?.trim();

        final year = yearStr != null ? int.tryParse(yearStr) : null;
        final trackNumber = trackStr != null ? int.tryParse(trackStr) : null;

        await _repository.updateSongTags(
          path: path,
          title: (title != null && title.isNotEmpty) ? title : 'Unknown Song',
          artist: (artist != null && artist.isNotEmpty) ? artist : 'Unknown Artist',
          album: (album != null && album.isNotEmpty) ? album : 'Unknown Album',
          genre: genre,
          year: year,
          trackNumber: trackNumber,
        );
      }
    } catch (_) {
      // Fallback or ignore error if method channel is unsupported
    }
  }
}

