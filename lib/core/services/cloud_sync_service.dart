// lib/core/services/cloud_sync_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../utils/error_logger.dart';
import 'auth_service.dart';

@singleton
class CloudSyncService {
  final AuthService _authService;
  final IMusicRepository _repository;
  final AppDatabase _db;
  SharedPreferences? _prefs;

  CloudSyncService(
    this._authService,
    this._repository,
    this._db,
  );

  static const String _keyLastSync = 'cloud_sync_last_timestamp';

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  DateTime? get lastSyncTime {
    final millis = _prefs?.getInt(_keyLastSync);
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<void> _setLastSyncTime(DateTime time) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_keyLastSync, time.millisecondsSinceEpoch);
  }

  Future<bool> syncAll() async {
    final user = _authService.currentUser;
    if (user == null) return false;

    try {
      final firestore = FirebaseFirestore.instance;
      final userDoc = firestore.collection('users').doc(user.uid);

      // 1. Upload Local Favorites & Playlists to Cloud
      await _uploadLocalData(userDoc);

      // 2. Download & Merge Cloud Data into Local DB
      await _downloadAndMergeCloudData(userDoc);

      await _setLastSyncTime(DateTime.now());
      return true;
    } catch (e, st) {
      ErrorLogger.log('Cloud sync failed', error: e, stackTrace: st, category: 'CloudSyncService');
      return false;
    }
  }

  Future<void> _uploadLocalData(DocumentReference userDoc) async {
    // 1. Gather local favorites
    final favRes = await _repository.getFavorites();
    final localFavorites = favRes.fold((l) => <SongsTableData>[], (r) => r);

    final favList = localFavorites.map((s) => {
      'title': s.title,
      'artist': s.artist,
      'album': s.album,
      'durationMs': s.durationMs,
      'remoteId': s.remoteId,
      'remoteArtworkUrl': s.remoteArtworkUrl,
      'source': s.source,
      'isFavorite': true,
      'dateAdded': s.dateAdded,
    }).toList();

    // 2. Gather local custom playlists
    final playlistRes = await _repository.getPlaylists();
    final localPlaylists = playlistRes.fold((l) => <PlaylistsTableData>[], (r) => r);

    final playlistsData = <Map<String, dynamic>>[];
    for (final pl in localPlaylists) {
      final songsRes = await _repository.getPlaylistSongs(pl.id);
      final pSongs = songsRes.fold((l) => <SongsTableData>[], (r) => r);

      playlistsData.add({
        'name': pl.name,
        'createdAt': pl.createdAt,
        'songs': pSongs.map((s) => {
          'title': s.title,
          'artist': s.artist,
          'album': s.album,
          'durationMs': s.durationMs,
          'remoteId': s.remoteId,
          'remoteArtworkUrl': s.remoteArtworkUrl,
          'source': s.source,
        }).toList(),
      });
    }

    // Save to Firestore batch/set
    await userDoc.collection('sync').doc('favorites').set({
      'updatedAt': FieldValue.serverTimestamp(),
      'items': favList,
    }, SetOptions(merge: true));

    await userDoc.collection('sync').doc('playlists').set({
      'updatedAt': FieldValue.serverTimestamp(),
      'items': playlistsData,
    }, SetOptions(merge: true));
  }

  Future<void> _downloadAndMergeCloudData(DocumentReference userDoc) async {
    // 1. Merge Favorites
    final favDoc = await userDoc.collection('sync').doc('favorites').get();
    if (favDoc.exists && favDoc.data() != null) {
      final items = (favDoc.data()!['items'] as List<dynamic>?) ?? [];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final title = (item['title'] as String?) ?? '';
        final artist = (item['artist'] as String?) ?? '';
        final remoteId = item['remoteId'] as String?;
        final remoteArtworkUrl = item['remoteArtworkUrl'] as String?;
        final durationMs = (item['durationMs'] as num?)?.toInt() ?? 0;

        if (title.isEmpty) continue;

        // Check if existing song matches
        SongsTableData? match;
        if (remoteId != null && remoteId.isNotEmpty) {
          match = await (_db.select(_db.songsTable)..where((t) => t.remoteId.equals(remoteId))).getSingleOrNull();
        }
        match ??= await (_db.select(_db.songsTable)
              ..where((t) => t.title.lower().equals(title.toLowerCase()) & t.artist.lower().equals(artist.toLowerCase()))
              ..limit(1))
            .getSingleOrNull();

        if (match != null) {
          if (!match.isFavorite) {
            await _repository.toggleFavorite(match.id);
          }
        } else if (remoteId != null && remoteId.isNotEmpty) {
          // Add as an online favorite song
          final track = YtmTrack(
            videoId: remoteId,
            title: title,
            artist: artist,
            duration: Duration(milliseconds: durationMs),
            artworkUrl: remoteArtworkUrl,
          );
          final songData = track.toSongData();
          await _db.into(_db.songsTable).insert(
            SongsTableCompanion(
              id: Value(songData.id),
              title: Value(songData.title),
              artist: Value(songData.artist),
              album: Value(songData.album),
              durationMs: Value(songData.durationMs),
              path: Value(songData.path),
              source: const Value(SongSource.youtube),
              isFavorite: const Value(true),
              remoteId: Value(remoteId),
              remoteArtworkUrl: Value(remoteArtworkUrl),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
    }

    // 2. Merge Playlists
    final plDoc = await userDoc.collection('sync').doc('playlists').get();
    if (plDoc.exists && plDoc.data() != null) {
      final plItems = (plDoc.data()!['items'] as List<dynamic>?) ?? [];
      final existingPlaylistsRes = await _repository.getPlaylists();
      final existingPlaylists = existingPlaylistsRes.fold((l) => <PlaylistsTableData>[], (r) => r);

      for (final plItem in plItems) {
        if (plItem is! Map<String, dynamic>) continue;
        final name = (plItem['name'] as String?) ?? '';
        if (name.isEmpty) continue;

        // Check if playlist exists
        var pl = existingPlaylists.where((p) => p.name.toLowerCase() == name.toLowerCase()).firstOrNull;
        if (pl == null) {
          final createRes = await _repository.createPlaylist(name);
          final newId = createRes.fold((l) => null, (r) => r);
          if (newId != null) {
            pl = await (_db.select(_db.playlistsTable)..where((t) => t.id.equals(newId))).getSingleOrNull();
          }
        }

        if (pl != null) {
          final songs = (plItem['songs'] as List<dynamic>?) ?? [];
          for (final sItem in songs) {
            if (sItem is! Map<String, dynamic>) continue;
            final title = (sItem['title'] as String?) ?? '';
            final artist = (sItem['artist'] as String?) ?? '';
            final remoteId = sItem['remoteId'] as String?;
            final remoteArtworkUrl = sItem['remoteArtworkUrl'] as String?;
            final durationMs = (sItem['durationMs'] as num?)?.toInt() ?? 0;

            if (title.isEmpty) continue;

            SongsTableData? match;
            if (remoteId != null && remoteId.isNotEmpty) {
              match = await (_db.select(_db.songsTable)..where((t) => t.remoteId.equals(remoteId))).getSingleOrNull();
            }
            match ??= await (_db.select(_db.songsTable)
                  ..where((t) => t.title.lower().equals(title.toLowerCase()) & t.artist.lower().equals(artist.toLowerCase()))
                  ..limit(1))
                .getSingleOrNull();

            int? songId = match?.id;
            if (songId == null && remoteId != null && remoteId.isNotEmpty) {
              final track = YtmTrack(
                videoId: remoteId,
                title: title,
                artist: artist,
                duration: Duration(milliseconds: durationMs),
                artworkUrl: remoteArtworkUrl,
              );
              final songData = track.toSongData();
              await _db.into(_db.songsTable).insert(
                SongsTableCompanion(
                  id: Value(songData.id),
                  title: Value(songData.title),
                  artist: Value(songData.artist),
                  album: Value(songData.album),
                  durationMs: Value(songData.durationMs),
                  path: Value(songData.path),
                  source: const Value(SongSource.youtube),
                  remoteId: Value(remoteId),
                  remoteArtworkUrl: Value(remoteArtworkUrl),
                ),
                mode: InsertMode.insertOrReplace,
              );
              songId = songData.id;
            }

            if (songId != null) {
              await _repository.addSongToPlaylist(pl.id, songId);
            }
          }
        }
      }
    }
  }
}
