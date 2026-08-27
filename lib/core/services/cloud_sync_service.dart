// lib/core/services/cloud_sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../utils/error_logger.dart';
import 'auth_service.dart';

class SyncRecord {
  final String id;
  final int localVersion;
  final DateTime localModified;
  final Map<String, dynamic> data;

  const SyncRecord({
    required this.id,
    required this.localVersion,
    required this.localModified,
    required this.data,
  });
}

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
  static const String _keySyncFavorites = 'cloud_sync_favorites_enabled';
  static const String _keySyncPlaylists = 'cloud_sync_playlists_enabled';

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

  Future<bool> get isFavoritesSyncEnabled async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keySyncFavorites) ?? true;
  }

  Future<void> setFavoritesSyncEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keySyncFavorites, enabled);
  }

  Future<bool> get isPlaylistsSyncEnabled async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keySyncPlaylists) ?? true;
  }

  Future<void> setPlaylistsSyncEnabled(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keySyncPlaylists, enabled);
  }

  String _stableSongId(SongsTableData song) {
    if (song.remoteId != null && song.remoteId!.isNotEmpty) {
      return 'yt_${song.remoteId}';
    }
    final raw = '${song.path}|${song.title.trim().toLowerCase()}|${song.artist.trim().toLowerCase()}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  String _stablePlaylistId(PlaylistsTableData pl) {
    final raw = '${pl.name.trim().toLowerCase()}|${pl.isSmart}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Future<bool> syncAll({bool syncFavorites = true, bool syncPlaylists = true}) async {
    final user = _authService.currentUser;
    if (user == null) return false;

    try {
      _syncedDocHashes.clear();
      final firestore = FirebaseFirestore.instance;
      final userDoc = firestore.collection('users').doc(user.uid);

      // 1. Upload Local Data to Cloud
      await _uploadLocalData(userDoc, syncFavorites: syncFavorites, syncPlaylists: syncPlaylists);

      // 2. Download & Merge Cloud Data into Local DB
      await _downloadAndMergeCloudData(userDoc, syncFavorites: syncFavorites, syncPlaylists: syncPlaylists);

      await _setLastSyncTime(DateTime.now());
      return true;
    } catch (e, st) {
      ErrorLogger.log('Cloud sync failed', error: e, stackTrace: st, category: 'CloudSyncService');
      return false;
    }
  }

  final Map<String, String> _syncedDocHashes = <String, String>{};

  Future<void> _uploadLocalData(
    DocumentReference userDoc, {
    required bool syncFavorites,
    required bool syncPlaylists,
  }) async {
    final firestore = FirebaseFirestore.instance;
    WriteBatch currentBatch = firestore.batch();
    int opCount = 0;

    Future<void> commitBatchIfFull() async {
      if (opCount >= 200) {
        final batchToCommit = currentBatch;
        currentBatch = firestore.batch();
        opCount = 0;
        try {
          await batchToCommit.commit();
        } catch (e, st) {
          ErrorLogger.log('Batch commit failed', error: e, stackTrace: st, category: 'CloudSync');
        }
      }
    }

    // 1. Upload favorites with stable doc ID and version increment only on change
    if (syncFavorites) {
      final favRes = await _repository.getFavorites();
      final localFavorites = favRes.fold((l) => <SongsTableData>[], (r) => r);
      final favCollection = userDoc.collection('favorites');

      for (final song in localFavorites) {
        final docId = _stableSongId(song);
        final payloadRaw = '${song.title}|${song.artist}|${song.album}|${song.durationMs}|${song.path}|${song.remoteId}|${song.remoteArtworkUrl}|${song.source}|true';
        final hash = sha256.convert(utf8.encode(payloadRaw)).toString();

        if (_syncedDocHashes[docId] == hash) {
          continue; // Content unchanged, skip Firestore write
        }

        final ref = favCollection.doc(docId);
        currentBatch.set(ref, {
          'id': song.id,
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'durationMs': song.durationMs,
          'path': song.path,
          'remoteId': song.remoteId,
          'remoteArtworkUrl': song.remoteArtworkUrl,
          'source': song.source,
          'isFavorite': true,
          'dateAdded': song.dateAdded,
          'contentHash': hash,
          'localVersion': FieldValue.increment(1),
          'modifiedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _syncedDocHashes[docId] = hash;
        opCount++;
        await commitBatchIfFull();
      }
    }

    // 2. Upload playlists with stable playlist doc ID
    if (syncPlaylists) {
      final playlistRes = await _repository.getPlaylists();
      final localPlaylists = playlistRes.fold((l) => <PlaylistsTableData>[], (r) => r);

      for (final pl in localPlaylists) {
        final plDocId = _stablePlaylistId(pl);
        final plPayloadRaw = '${pl.name}|${pl.createdAt.toIso8601String()}|${pl.isSmart}|${pl.smartCriteria}';
        final plHash = sha256.convert(utf8.encode(plPayloadRaw)).toString();
        final plDoc = userDoc.collection('playlists').doc(plDocId);

        if (_syncedDocHashes[plDocId] != plHash) {
          currentBatch.set(plDoc, {
            'id': pl.id,
            'name': pl.name,
            'createdAt': pl.createdAt.toIso8601String(),
            'isSmart': pl.isSmart,
            'smartCriteria': pl.smartCriteria,
            'contentHash': plHash,
            'localVersion': FieldValue.increment(1),
            'modifiedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          _syncedDocHashes[plDocId] = plHash;
          opCount++;
          await commitBatchIfFull();
        }

        final songsRes = await _repository.getPlaylistSongs(pl.id);
        final pSongs = songsRes.fold((l) => <SongsTableData>[], (r) => r);
        for (final song in pSongs) {
          final songDocId = _stableSongId(song);
          final songPayloadRaw = '${song.title}|${song.artist}|${song.album}|${song.path}|${song.remoteId}|${song.remoteArtworkUrl}|${song.durationMs}|${song.source}';
          final sHash = sha256.convert(utf8.encode(songPayloadRaw)).toString();
          final fullKey = '${plDocId}_$songDocId';

          if (_syncedDocHashes[fullKey] != sHash) {
            currentBatch.set(plDoc.collection('songs').doc(songDocId), {
              'id': song.id,
              'title': song.title,
              'artist': song.artist,
              'album': song.album,
              'path': song.path,
              'remoteId': song.remoteId,
              'remoteArtworkUrl': song.remoteArtworkUrl,
              'durationMs': song.durationMs,
              'source': song.source,
              'contentHash': sHash,
              'localVersion': FieldValue.increment(1),
              'modifiedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            _syncedDocHashes[fullKey] = sHash;
            opCount++;
            await commitBatchIfFull();
          }
        }
      }
    }

    if (opCount > 0) {
      try {
        await currentBatch.commit();
      } catch (e, st) {
        ErrorLogger.log('Final batch commit failed', error: e, stackTrace: st, category: 'CloudSync');
      }
    }
  }

  Future<void> _downloadAndMergeCloudData(
    DocumentReference userDoc, {
    required bool syncFavorites,
    required bool syncPlaylists,
  }) async {
    // 1. Merge Favorites
    if (syncFavorites) {
      final favSnapshot = await userDoc.collection('favorites').get();
      final favItems = <Map<String, dynamic>>[];
      if (favSnapshot.docs.isNotEmpty) {
        for (final doc in favSnapshot.docs) {
          favItems.add(doc.data());
        }
      } else {
        // Legacy document fallback
        final favDoc = await userDoc.collection('sync').doc('favorites').get();
        if (favDoc.exists && favDoc.data() != null) {
          final legacyItems = (favDoc.data()!['items'] as List<dynamic>?) ?? [];
          for (final item in legacyItems) {
            if (item is Map<String, dynamic>) favItems.add(item);
          }
        }
      }

      final allLocalSongs = await _db.select(_db.songsTable).get();
      final localByRemoteId = <String, SongsTableData>{};
      final localByTitleArtist = <String, SongsTableData>{};
      for (final s in allLocalSongs) {
        if (s.remoteId != null && s.remoteId!.isNotEmpty) {
          localByRemoteId[s.remoteId!] = s;
        }
        localByTitleArtist['${s.title.toLowerCase()}|||${s.artist.toLowerCase()}'] = s;
      }

      await _db.transaction(() async {
        for (final item in favItems) {
          final title = (item['title'] as String?) ?? '';
          final artist = (item['artist'] as String?) ?? '';
          final remoteId = item['remoteId'] as String?;
          final remoteArtworkUrl = item['remoteArtworkUrl'] as String?;
          final durationMs = (item['durationMs'] as num?)?.toInt() ?? 0;

          if (title.isEmpty) continue;

          SongsTableData? match;
          if (remoteId != null && remoteId.isNotEmpty) {
            match = localByRemoteId[remoteId];
          }
          match ??= localByTitleArtist['${title.toLowerCase()}|||${artist.toLowerCase()}'];

          if (match != null) {
            if (!match.isFavorite) {
              await (_db.update(_db.songsTable)..where((t) => t.id.equals(match!.id)))
                  .write(const SongsTableCompanion(isFavorite: Value(true)));
            }
          } else if (remoteId != null && remoteId.isNotEmpty) {
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
      });
    }

    // 2. Merge Playlists
    if (syncPlaylists) {
      final plSnapshot = await userDoc.collection('playlists').get();
      final existingPlaylistsRes = await _repository.getPlaylists();
      final existingPlaylists = existingPlaylistsRes.fold((l) => <PlaylistsTableData>[], (r) => r);

    if (plSnapshot.docs.isNotEmpty) {
      for (final plDoc in plSnapshot.docs) {
        final plData = plDoc.data();
        final name = (plData['name'] as String?) ?? '';
        if (name.isEmpty) continue;

        final cloudModifiedAt = (plData['modifiedAt'] as Timestamp?)?.toDate();
        var pl = existingPlaylists.where((p) => p.name.toLowerCase() == name.toLowerCase()).firstOrNull;

        if (pl != null && cloudModifiedAt != null) {
          final localModifiedAt = pl.createdAt;
          final diffMs = (localModifiedAt.difference(cloudModifiedAt).inMilliseconds).abs();
          // Conflict Resolution: If local is strictly newer (> 60s diff), preserve local
          if (localModifiedAt.isAfter(cloudModifiedAt) && diffMs > 60000) {
            continue;
          }
        }

        if (pl == null) {
          final createRes = await _repository.createPlaylist(name);
          final newId = createRes.fold((l) => null, (r) => r);
          if (newId != null) {
            pl = await (_db.select(_db.playlistsTable)..where((t) => t.id.equals(newId))).getSingleOrNull();
          }
        }

        if (pl != null) {
          final songDocs = await plDoc.reference.collection('songs').get();
          for (final sDoc in songDocs.docs) {
            final sItem = sDoc.data();
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
    } else {
      // Legacy document fallback
      final plLegacyDoc = await userDoc.collection('sync').doc('playlists').get();
      if (plLegacyDoc.exists && plLegacyDoc.data() != null) {
        final plItems = (plLegacyDoc.data()!['items'] as List<dynamic>?) ?? [];
        for (final plItem in plItems) {
          if (plItem is! Map<String, dynamic>) continue;
          final name = (plItem['name'] as String?) ?? '';
          if (name.isEmpty) continue;

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
  }
}

