// lib/core/services/cloud_sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide Query;
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../utils/error_logger.dart';
import '../config/app_config.dart';
import '../constants/prefs_keys.dart';
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

@lazySingleton
class CloudSyncService {
  final AuthService _authService;
  final IMusicRepository _repository;
  final AppDatabase _db;
  SharedPreferences? _prefs;

  static const String _keyLocalModifiedFavorites =
      'cloud_sync_local_modified_favorites';
  static final Map<String, int> _localModifiedFavorites = {};
  static bool _localModifiedLoaded = false;
  static Future<void>? _localModifiedPersistChain;

  static Future<void> _ensureLocalModifiedFavoritesLoaded() async {
    if (_localModifiedLoaded) return;
    _localModifiedLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyLocalModifiedFavorites);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final k = entry.key?.toString();
            final v = entry.value;
            if (k != null &&
                v is num &&
                !_localModifiedFavorites.containsKey(k)) {
              _localModifiedFavorites[k] = v.toInt();
            }
          }
        }
      }
    } catch (_) {
      // Best-effort: pure-Dart tests run without a platform SP binding.
    }
  }

  static void _persistLocalModifiedFavoritesAsync() {
    final previous = _localModifiedPersistChain ?? Future<void>.value();
    _localModifiedPersistChain = previous.then((_) async {
      await _ensureLocalModifiedFavoritesLoaded();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _keyLocalModifiedFavorites, jsonEncode(_localModifiedFavorites));
      } catch (_) {
        // Best-effort: pure-Dart tests run without a platform SP binding.
      }
    });
  }

  static void recordLocalFavoriteModified(String stableOrRemoteId,
      [int? timestampMs]) {
    if (stableOrRemoteId.isEmpty) return;
    _localModifiedFavorites[stableOrRemoteId] =
        timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    _persistLocalModifiedFavoritesAsync();
  }

  /// Computes the canonical cloud-sync stable id for [song].
  static String stableSongIdFor(SongsTableData song) {
    if (song.remoteId != null && song.remoteId!.isNotEmpty) {
      return 'yt_${song.remoteId}';
    }
    final raw =
        '${song.path}|${song.title.trim().toLowerCase()}|${song.artist.trim().toLowerCase()}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// Records a local favorite mutation for [song] under every identifier key
  /// that [_downloadAndMergeCloudData] may check during LWW reconciliation.
  static void recordSongFavoriteModified(SongsTableData song,
      [int? timestampMs]) {
    final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    _localModifiedFavorites[stableSongIdFor(song)] = ts;
    _localModifiedFavorites[song.id.toString()] = ts;
    final remoteId = song.remoteId;
    if (remoteId != null && remoteId.isNotEmpty) {
      _localModifiedFavorites[remoteId] = ts;
      _localModifiedFavorites['yt_$remoteId'] = ts;
    }
    _persistLocalModifiedFavoritesAsync();
  }

  @visibleForTesting
  static void clearLocalModifiedFavoritesForTesting() {
    _localModifiedFavorites.clear();
    _localModifiedLoaded = false;
    _localModifiedPersistChain = null;
  }

  @visibleForTesting
  static void simulateRestartForTesting() {
    _localModifiedFavorites.clear();
    _localModifiedLoaded = false;
  }

  @visibleForTesting
  static Future<void> flushLocalModifiedFavoritesForTesting() async {
    await _localModifiedPersistChain;
  }

  @visibleForTesting
  static Future<int?> localFavoriteModifiedAtForTesting(
      String stableOrRemoteId) async {
    await _ensureLocalModifiedFavoritesLoaded();
    return _localModifiedFavorites[stableOrRemoteId];
  }

  static int extractCloudTimestamp(Map<String, dynamic> data) {
    final mod = data['modifiedAt'];
    if (mod is Timestamp) return mod.millisecondsSinceEpoch;
    if (mod is int) return mod;
    if (mod is String) {
      final parsed = DateTime.tryParse(mod);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    final dev = data['deviceTimestamp'];
    if (dev is int) return dev;
    if (dev is Timestamp) return dev.millisecondsSinceEpoch;
    return 0;
  }

  static bool shouldCloudWin({required int cloudTimestamp, int? localTimestamp}) {
    if (localTimestamp == null || localTimestamp == 0) return true;
    return cloudTimestamp >= localTimestamp;
  }

  CloudSyncService(
    this._authService,
    this._repository,
    this._db,
  ) {
    _authService.registerSignOutHook(resetSessionState);
  }

  static const String _keyLastSync = 'cloud_sync_last_timestamp';
  static const String _keyLastSyncedUid = 'cloud_sync_last_uid';
  static const String _keySyncFavorites = 'cloud_sync_favorites_enabled';
  static const String _keySyncPlaylists = 'cloud_sync_playlists_enabled';
  static const String _keyDeviceId = 'cloud_sync_device_id';
  static const String _keyUploadedFavoriteIds =
      'cloud_sync_uploaded_favorite_ids';
  static const String _keyUploadedPlaylistSongs =
      'cloud_sync_uploaded_playlist_songs';
  static const String _keyUploadedPlaylistIds =
      'cloud_sync_uploaded_playlist_ids';

  // What *this device* last uploaded. Only ids in this set can be tombstoned,
  // so a fresh install can never delete favorites/playlist members added by
  // another device that it has not merged yet.
  Set<String> _lastUploadedFavoriteIds = <String>{};
  Map<String, Set<String>> _lastUploadedPlaylistSongIds =
      <String, Set<String>>{};
  Set<String> _lastUploadedPlaylistIds = <String>{};
  String? _lastSyncedUid;

  Future<void> resetSessionState() async {
    final pendingPersist = _localModifiedPersistChain;
    if (pendingPersist != null) {
      try {
        await pendingPersist;
      } catch (e, st) {
        ErrorLogger.log('Pending local-modified persist failed before reset',
            error: e, stackTrace: st, category: 'CloudSync');
      }
    }
    _localModifiedFavorites.clear();
    _localModifiedLoaded = false;
    _localModifiedPersistChain = null;
    _syncedDocHashes.clear();
    _lastUploadedFavoriteIds.clear();
    _lastUploadedPlaylistIds.clear();
    _lastUploadedPlaylistSongIds.clear();
    _lastSyncedUid = null;
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_keyLocalModifiedFavorites);
      await prefs.remove(_keySyncedHashes);
      await prefs.remove(_keyUploadedFavoriteIds);
      await prefs.remove(_keyUploadedPlaylistIds);
      await prefs.remove(_keyUploadedPlaylistSongs);
      await prefs.remove(_keyLastSync);
      await prefs.remove(_keyLastSyncedUid);
      final keysToRemove = prefs
          .getKeys()
          .where((k) =>
              k.startsWith('sync_pl_') ||
              k.startsWith('sync_cloud_pl_'))
          .toList(growable: false);
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
    } catch (e, st) {
      // Best-effort: pure-Dart tests may run without a platform SP binding.
      ErrorLogger.log('Failed to clear cloud sync session prefs',
          error: e, stackTrace: st, category: 'CloudSync');
    }
  }

  Future<String> getDeviceId() async {
    final prefs = await _getPrefs();
    var id = prefs.getString(_keyDeviceId);
    if (id == null || id.isEmpty) {
      final seed =
          '${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}';
      id = sha256.convert(utf8.encode(seed)).toString().substring(0, 16);
      await prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

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

  static const String _keySyncedHashes = 'cloud_sync_hashes_cache';

  String _stableSongId(SongsTableData song) => stableSongIdFor(song);

  static bool _isFilesystemOrContentPath(String rawPath) {
    final path = rawPath.trim();
    if (path.isEmpty) return false;
    final lower = path.toLowerCase();
    if (path.startsWith('/') ||
        path.startsWith(r'\') ||
        lower.startsWith('file:') ||
        lower.startsWith('content:')) {
      return true;
    }
    return RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(path);
  }

  static bool isPrivateLocalPath(SongsTableData song) {
    if (_isFilesystemOrContentPath(song.path)) return true;
    if (song.remoteId != null && song.remoteId!.isNotEmpty) return false;
    final lower = song.path.trim().toLowerCase();
    return !lower.startsWith('http://') &&
        !lower.startsWith('https://') &&
        !lower.startsWith('ytmusic://');
  }

  String _stablePlaylistId(PlaylistsTableData pl,
      [SharedPreferences? prefsOverride]) {
    final prefs = prefsOverride ?? _prefs;
    final cached = prefs?.getString('sync_pl_stable_id_${pl.id}');
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final raw =
        'pl_${pl.id}_${pl.createdAt.millisecondsSinceEpoch}_${pl.name.trim().toLowerCase()}';
    final generated =
        sha256.convert(utf8.encode(raw)).toString().substring(0, 24);
    prefs?.setString('sync_pl_stable_id_${pl.id}', generated);
    return generated;
  }

  Future<void> _loadSyncedHashes() async {
    final prefs = await _getPrefs();
    final jsonStr = prefs.getString(_keySyncedHashes);
    if (jsonStr != null) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          _syncedDocHashes.clear();
          decoded.forEach((k, v) => _syncedDocHashes[k] = v.toString());
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to decode synced hashes',
            error: e, stackTrace: st, category: 'CloudSync');
      }
    }
  }

  Future<void> _persistSyncedHashes() async {
    final prefs = await _getPrefs();
    try {
      await prefs.setString(_keySyncedHashes, jsonEncode(_syncedDocHashes));
    } catch (e, st) {
      ErrorLogger.log('Failed to persist synced hashes',
          error: e, stackTrace: st, category: 'CloudSync');
    }
  }

  Future<void> _loadUploadBaselines() async {
    final prefs = await _getPrefs();
    try {
      final favRaw = prefs.getString(_keyUploadedFavoriteIds);
      if (favRaw != null && favRaw.isNotEmpty) {
        final decoded = jsonDecode(favRaw);
        if (decoded is List) {
          _lastUploadedFavoriteIds = decoded.whereType<String>().toSet();
        }
      }
      final plIdsRaw = prefs.getString(_keyUploadedPlaylistIds);
      if (plIdsRaw != null && plIdsRaw.isNotEmpty) {
        final decoded = jsonDecode(plIdsRaw);
        if (decoded is List) {
          _lastUploadedPlaylistIds = decoded.whereType<String>().toSet();
        }
      }
      final plRaw = prefs.getString(_keyUploadedPlaylistSongs);
      if (plRaw != null && plRaw.isNotEmpty) {
        final decoded = jsonDecode(plRaw);
        if (decoded is Map) {
          _lastUploadedPlaylistSongIds = {
            for (final e in decoded.entries)
              if (e.value is List)
                e.key.toString(): (e.value as List).whereType<String>().toSet(),
          };
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to load cloud-sync upload baselines',
          error: e, stackTrace: st, category: 'CloudSync');
    }
  }

  Future<void> _persistUploadBaselines() async {
    final prefs = await _getPrefs();
    try {
      await prefs.setString(_keyUploadedFavoriteIds,
          jsonEncode(_lastUploadedFavoriteIds.toList()));
      await prefs.setString(
          _keyUploadedPlaylistSongs,
          jsonEncode(_lastUploadedPlaylistSongIds
              .map((k, v) => MapEntry(k, v.toList()))));
      await prefs.setString(_keyUploadedPlaylistIds,
          jsonEncode(_lastUploadedPlaylistIds.toList()));
    } catch (e, st) {
      ErrorLogger.log('Failed to persist cloud-sync upload baselines',
          error: e, stackTrace: st, category: 'CloudSync');
    }
  }

  bool _syncInProgress = false;

  Future<bool> syncAll({bool? syncFavorites, bool? syncPlaylists}) async {
    // Serialize syncs: concurrent runs would race on the shared synced-hash
    // map and the playlist stable-id prefs written by the merge step.
    if (_syncInProgress) return false;
    _syncInProgress = true;
    try {
      return await _syncAllInternal(
          syncFavorites: syncFavorites, syncPlaylists: syncPlaylists);
    } finally {
      _syncInProgress = false;
    }
  }

  Future<bool> _syncAllInternal(
      {bool? syncFavorites, bool? syncPlaylists}) async {
    // Pulsr Pure (prod offline): cloud sync is hard-off — no Firebase traffic
    // even if prefs/account state linger from another flavor.
    if (!AppConfig.isCloudSyncAllowed) return false;
    // User-facing Offline-only mode: never sync even in network builds.
    final prefs = await _getPrefs();
    if (prefs.getBool(PrefsKeys.offlineOnlyMode) == true) return false;
    final user = _authService.currentUser;
    if (user == null) return false;

    final persistedUid = _lastSyncedUid ?? prefs.getString(_keyLastSyncedUid);
    if (persistedUid != null &&
        persistedUid.isNotEmpty &&
        persistedUid != user.uid) {
      await resetSessionState();
    }
    _lastSyncedUid = user.uid;
    await prefs.setString(_keyLastSyncedUid, user.uid);

    // Fall back to the persisted per-scope toggles when the caller does not
    // pass explicit values, so the dashboard switches actually gate syncing.
    final favEnabled = syncFavorites ?? await isFavoritesSyncEnabled;
    final plEnabled = syncPlaylists ?? await isPlaylistsSyncEnabled;
    if (!favEnabled && !plEnabled) return true;

    try {
      await _loadSyncedHashes();
      await _loadUploadBaselines();
      final firestore = FirebaseFirestore.instance;
      final userDoc = firestore.collection('users').doc(user.uid);

      // 1. Upload Local Data to Cloud. A permanent/partial write failure must
      // never be reported as a successful sync.
      final uploadOk = await _uploadLocalData(userDoc,
          syncFavorites: favEnabled, syncPlaylists: plEnabled);
      if (!uploadOk) {
        ErrorLogger.log(
            'Cloud sync incomplete: one or more uploads failed permanently',
            category: 'CloudSyncService');
        return false;
      }

      // 2. Download & Merge Cloud Data into Local DB
      await _downloadAndMergeCloudData(userDoc,
          syncFavorites: favEnabled, syncPlaylists: plEnabled);

      await _setLastSyncTime(DateTime.now());
      await _persistSyncedHashes();
      await _persistUploadBaselines();
      return true;
    } catch (e, st) {
      ErrorLogger.log('Cloud sync failed',
          error: e, stackTrace: st, category: 'CloudSyncService');
      return false;
    }
  }

  final Map<String, String> _syncedDocHashes = <String, String>{};

  Future<bool> _commitWithRetry(WriteBatch batch) async {
    int attempts = 0;
    while (attempts < 3) {
      attempts++;
      try {
        await batch.commit();
        return true;
      } catch (e, st) {
        // Quota / permission errors are permanent — retrying burns quota
        // and delays the user-facing error. Fail fast with a clear log.
        if (e is FirebaseException) {
          final code = e.code.toLowerCase();
          if (code.contains('quota') ||
              code.contains('resource-exhausted') ||
              code.contains('permission-denied') ||
              code.contains('unauthenticated')) {
            ErrorLogger.log('Batch commit failed permanently (${e.code})',
                error: e, stackTrace: st, category: 'CloudSync');
            return false;
          }
        }
        if (attempts >= 3) {
          ErrorLogger.log('Batch commit failed after 3 attempts',
              error: e, stackTrace: st, category: 'CloudSync');
          return false;
        }
        await Future<void>.delayed(Duration(milliseconds: 200 * attempts));
      }
    }
    return false;
  }

  @visibleForTesting
  Future<bool> uploadLocalDataForTesting(
    DocumentReference userDoc, {
    required bool syncFavorites,
    required bool syncPlaylists,
    FirebaseFirestore? firestoreOverride,
  }) =>
      _uploadLocalData(
        userDoc,
        syncFavorites: syncFavorites,
        syncPlaylists: syncPlaylists,
        firestoreOverride: firestoreOverride,
      );

  Future<bool> _uploadLocalData(
    DocumentReference userDoc, {
    required bool syncFavorites,
    required bool syncPlaylists,
    FirebaseFirestore? firestoreOverride,
  }) async {
    final prefs = await _getPrefs();
    final firestore = firestoreOverride ?? FirebaseFirestore.instance;
    final deviceId = await getDeviceId();
    WriteBatch currentBatch = firestore.batch();
    // Hashes for the docs currently staged in `currentBatch`. They are merged
    // into `_syncedDocHashes` only after a commit succeeds, so a permanent
    // write failure can never mark unsynced content as synced.
    Map<String, String> pendingHashes = <String, String>{};
    Set<String>? favoriteBaseline;
    Set<String>? playlistBaseline;
    Map<String, Set<String>>? playlistSongBaseline;
    int opCount = 0;
    bool commitFailed = false;

    Future<void> commitBatchIfFull() async {
      if (opCount >= 200) {
        final batchToCommit = currentBatch;
        final hashesToCommit = pendingHashes;
        currentBatch = firestore.batch();
        pendingHashes = <String, String>{};
        opCount = 0;
        final ok = await _commitWithRetry(batchToCommit);
        if (ok) {
          _syncedDocHashes.addAll(hashesToCommit);
        } else {
          commitFailed = true;
        }
      }
    }

    // 1. Upload favorites with stable doc ID and version increment only on change
    if (syncFavorites) {
      final favRes = await _repository.getFavorites();
      final localFavorites = favRes.fold((l) => <SongsTableData>[], (r) => r);
      final favCollection = userDoc.collection('favorites');
      final localFavoriteDocIds = <String>{};

      for (final song in localFavorites) {
        final docId = _stableSongId(song);
        localFavoriteDocIds.add(docId);
        final payloadRaw =
            '${song.title}|${song.artist}|${song.album}|${song.durationMs}|${song.path}|${song.remoteId}|${song.remoteArtworkUrl}|${song.source}|true';
        final hash = sha256.convert(utf8.encode(payloadRaw)).toString();

        if (_syncedDocHashes[docId] == hash) {
          continue; // Content unchanged, skip Firestore write
        }

        final ref = favCollection.doc(docId);
        // Privacy: hash local/Windows/content paths, keep remoteId for YTM (path is PII)
        final isLocalPath = isPrivateLocalPath(song);
        final sanitizedPath = isLocalPath ? null : song.path;
        final pathHash = isLocalPath
            ? sha256.convert(utf8.encode(song.path)).toString()
            : null;
        currentBatch.set(
            ref,
            {
              'id': song.id,
              'title': song.title,
              'artist': song.artist,
              'album': song.album,
              'durationMs': song.durationMs,
              'path': sanitizedPath,
              'pathHash': pathHash,
              'remoteId': song.remoteId,
              'remoteArtworkUrl': song.remoteArtworkUrl,
              'source': song.source,
              'isFavorite': true,
              'deleted': false,
              'dateAdded': song.dateAdded,
              'contentHash': hash,
              'localVersion': FieldValue.increment(1),
              'modifiedAt': FieldValue.serverTimestamp(),
              'lastModifiedBy': deviceId,
              'deviceTimestamp': DateTime.now().millisecondsSinceEpoch,
            },
            SetOptions(merge: true));
        pendingHashes[docId] = hash;
        opCount++;
        await commitBatchIfFull();
        if (commitFailed) return false;
      }

      // Tombstone favorites this device previously uploaded and no longer has.
      // The baseline makes this safe on a fresh install: ids this device never
      // uploaded (e.g. added by another device) are never deleted.
      for (final removedId
          in _lastUploadedFavoriteIds.difference(localFavoriteDocIds)) {
        currentBatch.set(
            favCollection.doc(removedId),
            {
              'deleted': true,
              'isFavorite': false,
              'contentHash': 'deleted',
              'localVersion': FieldValue.increment(1),
              'modifiedAt': FieldValue.serverTimestamp(),
              'lastModifiedBy': deviceId,
              'deviceTimestamp': DateTime.now().millisecondsSinceEpoch,
            },
            SetOptions(merge: true));
        pendingHashes[removedId] = 'deleted';
        opCount++;
        await commitBatchIfFull();
        if (commitFailed) return false;
      }
      favoriteBaseline = localFavoriteDocIds;
    }

    // 2. Upload playlists with stable playlist doc ID
    if (syncPlaylists) {
      playlistSongBaseline = <String, Set<String>>{};
      final playlistRes = await _repository.getPlaylists();
      final localPlaylists =
          playlistRes.fold((l) => <PlaylistsTableData>[], (r) => r);
      final localPlaylistDocIds = <String>{};

      for (final pl in localPlaylists) {
        final plDocId = _stablePlaylistId(pl, prefs);
        localPlaylistDocIds.add(plDocId);
        final plPayloadRaw =
            '${pl.name}|${pl.createdAt.toIso8601String()}|${pl.isSmart}|${pl.smartCriteria}';
        final plHash = sha256.convert(utf8.encode(plPayloadRaw)).toString();
        final plDoc = userDoc.collection('playlists').doc(plDocId);

        if (_syncedDocHashes[plDocId] != plHash) {
          currentBatch.set(
              plDoc,
              {
                'id': pl.id,
                'syncId': plDocId,
                'name': pl.name,
                'createdAt': pl.createdAt.toIso8601String(),
                'isSmart': pl.isSmart,
                'smartCriteria': pl.smartCriteria,
                'deleted': false,
                'contentHash': plHash,
                'localVersion': FieldValue.increment(1),
                'modifiedAt': FieldValue.serverTimestamp(),
                'lastModifiedBy': deviceId,
                'deviceTimestamp': DateTime.now().millisecondsSinceEpoch,
              },
              SetOptions(merge: true));
          pendingHashes[plDocId] = plHash;
          opCount++;
          await commitBatchIfFull();
          if (commitFailed) return false;
        }

        final songsRes = await _repository.getPlaylistSongs(pl.id);
        final pSongs = songsRes.fold((l) => <SongsTableData>[], (r) => r);
        final localSongDocIds = <String>{};
        for (final song in pSongs) {
          final songDocId = _stableSongId(song);
          localSongDocIds.add(songDocId);
          final songPayloadRaw =
              '${song.title}|${song.artist}|${song.album}|${song.path}|${song.remoteId}|${song.remoteArtworkUrl}|${song.durationMs}|${song.source}';
          final sHash = sha256.convert(utf8.encode(songPayloadRaw)).toString();
          final fullKey = '${plDocId}_$songDocId';

          if (_syncedDocHashes[fullKey] != sHash) {
            final isLocalSongPath = isPrivateLocalPath(song);
            currentBatch.set(
                plDoc.collection('songs').doc(songDocId),
                {
                  'id': song.id,
                  'title': song.title,
                  'artist': song.artist,
                  'album': song.album,
                  'path': isLocalSongPath ? null : song.path,
                  'pathHash': isLocalSongPath
                      ? sha256.convert(utf8.encode(song.path)).toString()
                      : null,
                  'remoteId': song.remoteId,
                  'remoteArtworkUrl': song.remoteArtworkUrl,
                  'durationMs': song.durationMs,
                  'source': song.source,
                  'deleted': false,
                  'contentHash': sHash,
                  'localVersion': FieldValue.increment(1),
                  'modifiedAt': FieldValue.serverTimestamp(),
                  'lastModifiedBy': deviceId,
                  'deviceTimestamp': DateTime.now().millisecondsSinceEpoch,
                },
                SetOptions(merge: true));
            pendingHashes[fullKey] = sHash;
            opCount++;
            await commitBatchIfFull();
            if (commitFailed) return false;
          }
        }

        final previousSongIds =
            _lastUploadedPlaylistSongIds[plDocId] ?? const <String>{};
        for (final removedId in previousSongIds.difference(localSongDocIds)) {
          currentBatch.set(
              plDoc.collection('songs').doc(removedId),
              {
                'deleted': true,
                'contentHash': 'deleted',
                'localVersion': FieldValue.increment(1),
                'modifiedAt': FieldValue.serverTimestamp(),
                'lastModifiedBy': deviceId,
                'deviceTimestamp': DateTime.now().millisecondsSinceEpoch,
              },
              SetOptions(merge: true));
          pendingHashes['${plDocId}_$removedId'] = 'deleted';
          opCount++;
          await commitBatchIfFull();
          if (commitFailed) return false;
        }
        playlistSongBaseline ??= <String, Set<String>>{};
        playlistSongBaseline[plDocId] = localSongDocIds;
      }

      final playlistCollection = userDoc.collection('playlists');
      for (final removedId
          in _lastUploadedPlaylistIds.difference(localPlaylistDocIds)) {
        currentBatch.set(
            playlistCollection.doc(removedId),
            {
              'deleted': true,
              'contentHash': 'deleted',
              'localVersion': FieldValue.increment(1),
              'modifiedAt': FieldValue.serverTimestamp(),
              'lastModifiedBy': deviceId,
              'deviceTimestamp': DateTime.now().millisecondsSinceEpoch,
            },
            SetOptions(merge: true));
        pendingHashes['pl_tombstone_$removedId'] = 'deleted';
        opCount++;
        await commitBatchIfFull();
        if (commitFailed) return false;
      }
      playlistBaseline = localPlaylistDocIds;
    }

    if (commitFailed) return false;
    if (opCount > 0) {
      final ok = await _commitWithRetry(currentBatch);
      if (ok) {
        _syncedDocHashes.addAll(pendingHashes);
      } else {
        commitFailed = true;
      }
    }
    if (!commitFailed) {
      if (favoriteBaseline != null) {
        _lastUploadedFavoriteIds = favoriteBaseline;
      }
      if (playlistBaseline != null) {
        _lastUploadedPlaylistIds = playlistBaseline;
      }
      if (playlistSongBaseline != null) {
        _lastUploadedPlaylistSongIds
          ..clear()
          ..addAll(playlistSongBaseline);
      }
    }
    return !commitFailed;
  }

  @visibleForTesting
  Future<void> downloadAndMergeCloudDataForTesting(
    DocumentReference userDoc, {
    required bool syncFavorites,
    required bool syncPlaylists,
  }) =>
      _downloadAndMergeCloudData(
        userDoc,
        syncFavorites: syncFavorites,
        syncPlaylists: syncPlaylists,
      );

  int? _maxLocalFavoriteTimestamp({
    String? docId,
    String? remoteId,
    SongsTableData? match,
  }) {
    int? best;
    void consider(String? candidateKey) {
      if (candidateKey == null || candidateKey.isEmpty) return;
      final ts = _localModifiedFavorites[candidateKey];
      if (ts != null && (best == null || ts > best!)) {
        best = ts;
      }
    }

    consider(docId);
    consider(remoteId);
    if (remoteId != null && remoteId.isNotEmpty) {
      consider('yt_$remoteId');
    }
    if (match != null) {
      consider(_stableSongId(match));
      consider(match.id.toString());
    }
    return best;
  }

  Future<SongsTableData> _upsertCloudYtmTrack({
    required String remoteId,
    required String title,
    required String artist,
    required int durationMs,
    String? remoteArtworkUrl,
    bool markFavorite = false,
  }) async {
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
            isFavorite: Value(markFavorite),
            remoteId: Value(remoteId),
            remoteArtworkUrl: Value(remoteArtworkUrl),
          ),
          mode: InsertMode.insertOrIgnore,
        );

    final existing = await (_db.select(_db.songsTable)
          ..where((t) => t.id.equals(songData.id) | t.remoteId.equals(remoteId))
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) {
      return songData;
    }

    final needsFavorite = markFavorite && !existing.isFavorite;
    final needsArtwork = remoteArtworkUrl != null &&
        remoteArtworkUrl.isNotEmpty &&
        (existing.remoteArtworkUrl == null ||
            existing.remoteArtworkUrl!.isEmpty);
    if (needsFavorite || needsArtwork) {
      await (_db.update(_db.songsTable)
            ..where((t) => t.id.equals(existing.id)))
          .write(SongsTableCompanion(
        isFavorite: needsFavorite ? const Value(true) : const Value.absent(),
        remoteArtworkUrl:
            needsArtwork ? Value(remoteArtworkUrl) : const Value.absent(),
      ));
      return (_db.select(_db.songsTable)
            ..where((t) => t.id.equals(existing.id)))
          .getSingle();
    }
    return existing;
  }

  void _indexSongInMaps(
    SongsTableData song, {
    required Map<String, SongsTableData> byStableId,
    required Map<String, SongsTableData> byRemoteId,
    Map<(String, String), SongsTableData>? byTitleArtist,
    String? extraDocId,
  }) {
    byStableId[_stableSongId(song)] = song;
    if (extraDocId != null && extraDocId.isNotEmpty) {
      byStableId[extraDocId] = song;
    }
    final rid = song.remoteId;
    if (rid != null && rid.isNotEmpty) {
      byRemoteId[rid] = song;
    }
    if (byTitleArtist != null) {
      byTitleArtist[(song.title.toLowerCase(), song.artist.toLowerCase())] =
          song;
    }
  }

  Future<void> _downloadAndMergeCloudData(
    DocumentReference userDoc, {
    required bool syncFavorites,
    required bool syncPlaylists,
  }) async {
    await _getPrefs();
    final initialLastSync = lastSyncTime;

    // 1. Merge Favorites
    if (syncFavorites) {
      await _ensureLocalModifiedFavoritesLoaded();
      Query<Map<String, dynamic>> favQuery = userDoc.collection('favorites');
      if (initialLastSync != null) {
        // Delta reads with 7-day tombstone window
        final deltaThreshold =
            initialLastSync.subtract(const Duration(days: 7));
        favQuery = favQuery.where('modifiedAt',
            isGreaterThan: Timestamp.fromDate(deltaThreshold));
      }
      final favSnapshot = await favQuery.get();
      final favItems = <Map<String, dynamic>>[];
      if (favSnapshot.docs.isNotEmpty) {
        for (final doc in favSnapshot.docs) {
          favItems.add({...doc.data(), '__docId': doc.id});
        }
      } else if (initialLastSync == null) {
        // Legacy document fallback runs only on initial sync when favorites
        // collection itself has no entries.
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
      final localByStableId = <String, SongsTableData>{};
      for (final s in allLocalSongs) {
        if (s.remoteId != null && s.remoteId!.isNotEmpty) {
          localByRemoteId[s.remoteId!] = s;
        }
        localByStableId[_stableSongId(s)] = s;
      }

      await _db.transaction(() async {
        for (final item in favItems) {
          final title = (item['title'] as String?) ?? '';
          final artist = (item['artist'] as String?) ?? '';
          final remoteId = item['remoteId'] as String?;
          final remoteArtworkUrl = item['remoteArtworkUrl'] as String?;
          final durationMs = (item['durationMs'] as num?)?.toInt() ?? 0;
          final docId = item['__docId'] as String?;
          final isDeleted = item['deleted'] == true;

          if (title.isEmpty && !isDeleted) continue;

          SongsTableData? match;
          if (docId != null) match = localByStableId[docId];
          if (remoteId != null && remoteId.isNotEmpty) {
            match ??= localByRemoteId[remoteId];
          }

          // LWW check: never let stale cloud state override newer local change
          final localModTime = _maxLocalFavoriteTimestamp(
            docId: docId,
            remoteId: remoteId,
            match: match,
          );
          final cloudTime = extractCloudTimestamp(item);
          if (!shouldCloudWin(
              cloudTimestamp: cloudTime, localTimestamp: localModTime)) {
            continue;
          }

          // A tombstone must remove the favorite
          if (isDeleted) {
            if (match != null && match.isFavorite) {
              await (_db.update(_db.songsTable)
                    ..where((t) => t.id.equals(match!.id)))
                  .write(const SongsTableCompanion(isFavorite: Value(false)));
            }
            continue;
          }

          if (match != null) {
            if (!match.isFavorite) {
              await (_db.update(_db.songsTable)
                    ..where((t) => t.id.equals(match!.id)))
                  .write(const SongsTableCompanion(isFavorite: Value(true)));
            }
          } else if (remoteId != null && remoteId.isNotEmpty) {
            final inserted = await _upsertCloudYtmTrack(
              remoteId: remoteId,
              title: title,
              artist: artist,
              durationMs: durationMs,
              remoteArtworkUrl: remoteArtworkUrl,
              markFavorite: true,
            );
            _indexSongInMaps(
              inserted,
              byStableId: localByStableId,
              byRemoteId: localByRemoteId,
              extraDocId: docId,
            );
          }
        }
      });
    }

    // 2. Merge Playlists
    if (syncPlaylists) {
      final plSnapshot = await userDoc.collection('playlists').get();
      final existingPlaylistsRes = await _repository.getPlaylists();
      final existingPlaylists =
          existingPlaylistsRes.fold((l) => <PlaylistsTableData>[], (r) => r)
              .toList();
      final prefs = await _getPrefs();
      final deviceId = await getDeviceId();
      final playlistSongsAll = await _db.select(_db.songsTable).get();
      final localByStableId = {
        for (final s in playlistSongsAll) _stableSongId(s): s,
      };
      final localByRemoteId = <String, SongsTableData>{};
      final localByTitleArtist = <(String, String), SongsTableData>{};
      for (final s in playlistSongsAll) {
        final rid = s.remoteId;
        if (rid != null && rid.isNotEmpty) localByRemoteId[rid] = s;
        localByTitleArtist[(s.title.toLowerCase(), s.artist.toLowerCase())] = s;
      }

      if (plSnapshot.docs.isNotEmpty) {
        for (final plDoc in plSnapshot.docs) {
          final plData = plDoc.data();
          if (plData['deleted'] == true) continue;
          final name = (plData['name'] as String?) ?? '';
          if (name.isEmpty) continue;

          final remoteModifiedBy = plData['lastModifiedBy'] as String?;
          if (remoteModifiedBy != null && remoteModifiedBy != deviceId) {
            ErrorLogger.log(
              'CloudSync: Remote playlist change for "$name" was modified by another device ($remoteModifiedBy)',
              category: 'CloudSyncService',
            );
          }

          final cloudSyncId = (plData['syncId'] as String?) ?? plDoc.id;
          final mappedLocalId = prefs.getInt('sync_cloud_pl_$cloudSyncId');

          PlaylistsTableData? pl;
          if (mappedLocalId != null) {
            pl = existingPlaylists
                .where((p) => p.id == mappedLocalId)
                .firstOrNull;
          }
          if (pl == null) {
            // Find candidates with the same name that are NOT mapped to a different cloud playlist
            final candidates = existingPlaylists
                .where((p) => p.name.toLowerCase() == name.toLowerCase())
                .toList();
            for (final cand in candidates) {
              final mapped = prefs.getString('sync_pl_stable_id_${cand.id}');
              if (mapped == null || mapped == cloudSyncId) {
                pl = cand;
                await prefs.setString('sync_pl_stable_id_${cand.id}', cloudSyncId);
                await prefs.setInt('sync_cloud_pl_$cloudSyncId', cand.id);
                break;
              }
            }
          }

          if (pl == null) {
            final createRes = await _repository.createPlaylist(name);
            final newId = createRes.fold((l) => null, (r) => r);
            if (newId != null) {
              pl = await (_db.select(_db.playlistsTable)
                    ..where((t) => t.id.equals(newId)))
                  .getSingleOrNull();
              if (pl != null) {
                existingPlaylists.add(pl);
                await prefs.setString('sync_pl_stable_id_${pl.id}', cloudSyncId);
                await prefs.setInt('sync_cloud_pl_$cloudSyncId', pl.id);
              }
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
              final isDeleted = sItem['deleted'] == true;

              SongsTableData? match = localByStableId[sDoc.id];
              if (remoteId != null && remoteId.isNotEmpty) {
                match ??= localByRemoteId[remoteId];
              }
              if (isDeleted) {
                if (match != null) {
                  await _repository.removeSongFromPlaylist(pl.id, match.id);
                }
                continue;
              }

              if (title.isEmpty) continue;

              match ??= localByTitleArtist[(
                title.toLowerCase(),
                artist.toLowerCase()
              )];

              int? songId = match?.id;
              if (songId == null && remoteId != null && remoteId.isNotEmpty) {
                final inserted = await _upsertCloudYtmTrack(
                  remoteId: remoteId,
                  title: title,
                  artist: artist,
                  durationMs: durationMs,
                  remoteArtworkUrl: remoteArtworkUrl,
                );
                _indexSongInMaps(
                  inserted,
                  byStableId: localByStableId,
                  byRemoteId: localByRemoteId,
                  byTitleArtist: localByTitleArtist,
                  extraDocId: sDoc.id,
                );
                songId = inserted.id;
              }

              if (songId != null) {
                await _repository.addSongToPlaylist(pl.id, songId);
              }
            }
          }
        }
      } else if (initialLastSync == null) {
        // Legacy document fallback (only on initial sync)
        final plLegacyDoc =
            await userDoc.collection('sync').doc('playlists').get();
        if (plLegacyDoc.exists && plLegacyDoc.data() != null) {
          final plItems =
              (plLegacyDoc.data()!['items'] as List<dynamic>?) ?? [];
          for (final plItem in plItems) {
            if (plItem is! Map<String, dynamic>) continue;
            final name = (plItem['name'] as String?) ?? '';
            if (name.isEmpty) continue;

            var pl = existingPlaylists
                .where((p) => p.name.toLowerCase() == name.toLowerCase())
                .firstOrNull;
            if (pl == null) {
              final createRes = await _repository.createPlaylist(name);
              final newId = createRes.fold((l) => null, (r) => r);
              if (newId != null) {
                pl = await (_db.select(_db.playlistsTable)
                      ..where((t) => t.id.equals(newId)))
                    .getSingleOrNull();
                if (pl != null) {
                  existingPlaylists.add(pl);
                }
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
                  match = localByRemoteId[remoteId] ??
                      await (_db.select(_db.songsTable)
                            ..where((t) => t.remoteId.equals(remoteId)))
                          .getSingleOrNull();
                }
                match ??= localByTitleArtist[(
                      title.toLowerCase(),
                      artist.toLowerCase()
                    )] ??
                    await (_db.select(_db.songsTable)
                          ..where((t) =>
                              t.title.lower().equals(title.toLowerCase()) &
                              t.artist.lower().equals(artist.toLowerCase()))
                          ..limit(1))
                        .getSingleOrNull();

                int? songId = match?.id;
                if (songId == null && remoteId != null && remoteId.isNotEmpty) {
                  final inserted = await _upsertCloudYtmTrack(
                    remoteId: remoteId,
                    title: title,
                    artist: artist,
                    durationMs: durationMs,
                    remoteArtworkUrl: remoteArtworkUrl,
                  );
                  _indexSongInMaps(
                    inserted,
                    byStableId: localByStableId,
                    byRemoteId: localByRemoteId,
                    byTitleArtist: localByTitleArtist,
                  );
                  songId = inserted.id;
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
