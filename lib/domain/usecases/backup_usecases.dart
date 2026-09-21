// lib/domain/usecases/backup_usecases.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/utils/error_logger.dart';
import '../../data/db/app_database.dart';
import '../repositories/music_repository_interface.dart';

class ImportResult {
  final int restoredFavoritesCount;
  final int restoredPlaylistsCount;
  final int restoredSettingsCount;
  final int restoredHistoryCount;
  final int restoredExcludedFoldersCount;
  final int restoredEqProfilesCount;
  final int restoredAutomationRulesCount;
  final int restoredDownloadsCount;
  final List<String> unmatchedPaths;

  const ImportResult({
    this.restoredFavoritesCount = 0,
    this.restoredPlaylistsCount = 0,
    this.restoredSettingsCount = 0,
    this.restoredHistoryCount = 0,
    this.restoredExcludedFoldersCount = 0,
    this.restoredEqProfilesCount = 0,
    this.restoredAutomationRulesCount = 0,
    this.restoredDownloadsCount = 0,
    this.unmatchedPaths = const [],
  });
}

@singleton
class ExportBackupUseCase {
  final IMusicRepository _repository;

  ExportBackupUseCase(this._repository);

  Future<String> execute() async {
    // 1. Favorites
    final favoritesResult = await _repository.getFavorites();
    final favoritesSongs =
        favoritesResult.fold((l) => <SongsTableData>[], (r) => r);
    final favoritePaths = favoritesSongs.map((s) => s.path).toList();

    // 2. Playlists with song file paths
    final playlistsResult = await _repository.getPlaylists();
    final playlists =
        playlistsResult.fold((l) => <PlaylistsTableData>[], (r) => r);
    final playlistsData = <Map<String, dynamic>>[];

    for (final pl in playlists) {
      final songsResult = await _repository.getPlaylistSongs(pl.id);
      final playlistSongs =
          songsResult.fold((l) => <SongsTableData>[], (r) => r);
      playlistsData.add({
        'name': pl.name,
        'isSmart': pl.isSmart,
        'smartCriteria': pl.smartCriteria,
        'songPaths': playlistSongs.map((s) => s.path).toList(),
      });
    }

    // 3. Settings (gapless, crossfade, theme, EQ, etc.)
    final prefs = await SharedPreferences.getInstance();
    final settingsMap = {
      'gaplessPlayback': prefs.getBool('setting_gapless') ?? true,
      'crossfadeSeconds': prefs.getDouble('setting_crossfade') ?? 0.0,
      'minDurationSec': prefs.getInt('setting_min_duration') ?? 30,
      'dynamicThemingEnabled': prefs.getBool('setting_dynamic_theme') ?? true,
      'themeColorSource': prefs.getString('setting_theme_color_source'),
      'resumeAfterInterruption':
          prefs.getBool('setting_resume_after_interruption') ?? true,
      'themeMode': prefs.getString('setting_theme_mode') ?? 'dark',
      'customAccentColorValue':
          prefs.getInt('setting_custom_accent') ?? 0xFF9B9EF5,
      'playerThemeMode':
          prefs.getString('setting_player_theme_mode') ?? 'classic',
      'visualizerStyle': prefs.getString('setting_visualizer_style') ?? 'bar',
      // Extended settings (previously missing — caused data loss on restore)
      'replayGainMode': prefs.getString('setting_replay_gain_mode') ?? 'track',
      'replayGainPreampWithRg': prefs.getDouble('setting_replay_gain_preamp_with_rg') ?? 0.0,
      'replayGainPreampWithoutRg': prefs.getDouble('setting_replay_gain_preamp_without_rg') ?? -3.0,
      'wifiOnlyMode': prefs.getBool('setting_wifi_only_mode') ?? false,
      'offlineOnlyMode': prefs.getBool('setting_offline_only_mode') ?? false,
      'bitPerfectMode': prefs.getBool('setting_bit_perfect') ?? false,
      'dspPreference': prefs.getString('setting_dsp_preference') ?? 'native',
      'streamingQuality': prefs.getString('setting_streaming_quality') ?? 'high',
      'downloadQuality': prefs.getString('setting_download_quality') ?? 'high',
      'isLosslessMode': prefs.getBool('setting_lossless') ?? false,
      // EQ state lives under the EqualizerManager keys (eq_*) — the legacy
      // setting_eq_* keys were never written by anything, so backups silently
      // restored a flat EQ.
      'eqEnabled': prefs.getBool(PrefsKeys.eqEnabled) ?? false,
      'eqGains': prefs.getString(PrefsKeys.eqGains),
      'eqPreset': prefs.getString(PrefsKeys.eqPresetName),
      'eqPreamp': prefs.getDouble(PrefsKeys.eqPreamp),
      'eqBandCount': prefs.getInt(PrefsKeys.eqBandCount),
      'eqCustomFrequencies': prefs.getString(PrefsKeys.eqCustomFrequencies),
      'eqCustom32Frequencies': prefs.getString(PrefsKeys.eqCustom32Frequencies),
      'eqCustom64Frequencies': prefs.getString(PrefsKeys.eqCustom64Frequencies),
      'playbackSpeed': prefs.getDouble('setting_playback_speed') ?? 1.0,
    };

    // 4. Play History (paths, count, lastPlayed)
    final allSongsResult = await _repository.getAllSongs();
    final allSongs = allSongsResult.fold((l) => <SongsTableData>[], (r) => r);
    final historyData = <Map<String, dynamic>>[];
    for (final song in allSongs) {
      if (song.playCount > 0 || song.lastPlayed != null) {
        historyData.add({
          'path': song.path,
          'playCount': song.playCount,
          'lastPlayed': song.lastPlayed,
        });
      }
    }

    // 5. Excluded Folders
    final excludedResult = await _repository.getExcludedFolderPaths();
    final excludedFolders = excludedResult.fold((l) => <String>[], (r) => r);

    // 6. Custom EQ Profiles & Presets
    final customEqProfilesJson = prefs.getString(PrefsKeys.customEqProfiles);
    dynamic customEqProfilesData;
    if (customEqProfilesJson != null) {
      try {
        customEqProfilesData = jsonDecode(customEqProfilesJson);
      } catch (_) {}
    }

    // 7. Automation Rules
    final rulesJson = prefs.getString('setting_automation_rules');
    dynamic automationRulesData;
    if (rulesJson != null) {
      try {
        automationRulesData = jsonDecode(rulesJson);
      } catch (_) {}
    }

    // 7b. Backup v2: DSP snapshots, device profiles, settings profiles.
    // Raw JSON strings carried verbatim so reinstall restores per-device
    // DSP memory and profile links instead of dropping them.
    String? dspSnapshotsRaw;
    String? deviceProfilesRaw;
    String? deviceRegistryRaw;
    String? settingsProfilesRaw;
    try {
      String? readRaw(String key) {
        final v = prefs.getString(key);
        return (v == null || v.isEmpty) ? null : v;
      }

      dspSnapshotsRaw = readRaw('dsp_snapshot_store_v1');
      deviceProfilesRaw = readRaw('setting_device_profile_links');
      deviceRegistryRaw = readRaw('setting_device_registry');
      settingsProfilesRaw = readRaw('setting_custom_profiles');
    } catch (e, st) {
      ErrorLogger.log('Failed reading v2 profile blobs',
          error: e, stackTrace: st, category: 'Backup');
    }
    // 8. Downloaded Tracks Metadata
    final downloadedTracks = allSongs
        .where((s) => s.isDownloaded)
        .map((s) => {
              'title': s.title,
              'artist': s.artist,
              'album': s.album,
              'path': s.path,
              'remoteId': s.remoteId,
              'durationMs': s.durationMs,
            })
        .toList();

    // 9. Per-song data (ratings, BPM, EQ/volume overrides, bookmarks) —
    // previously dropped on reinstall, leaving smart playlists with
    // rating/bpm rules evaluating to empty.
    // Keys are translated from the volatile MediaStore id to a portable
    // path/remoteId identity so a restore on a fresh install (new ids) can
    // re-associate them. Without this the per-song prefs pointed at ids that
    // no longer existed after reinstall.
    Map<String, dynamic>? ratingsData;
    Map<String, dynamic>? bpmData;
    Map<String, dynamic>? perSongEqData;
    Map<String, dynamic>? perSongVolData;
    Map<String, dynamic>? bookmarksData;
    try {
      final songsById = {for (final s in allSongs) s.id.toString(): s};
      String portableKey(String rawKey) {
        String idPart = rawKey;
        if (rawKey.startsWith('id:')) idPart = rawKey.substring(3);
        final song = songsById[idPart];
        if (song == null) return rawKey; // unknown id: keep verbatim
        if (song.remoteId != null && song.remoteId!.isNotEmpty) {
          return 'yt:${song.remoteId}';
        }
        if (song.path.isNotEmpty && !song.path.startsWith('ytmusic://')) {
          return 'path:${song.path}';
        }
        return 'id:$idPart';
      }

      Map<String, dynamic> portable(Map<String, dynamic> src) =>
          {for (final e in src.entries) portableKey(e.key): e.value};

      for (final entry in {
        'song_ratings_v1': 'ratings',
        'per_track_bpm_overrides_v1': 'bpm',
        'per_song_eq_overrides_v1': 'eq',
        'per_song_volume_overrides_v1': 'vol',
        'playback_bookmarks_v1': 'bookmarks',
      }.entries) {
        final raw = prefs.getString(entry.key);
        if (raw == null || raw.isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final mapped = portable(decoded);
          switch (entry.value) {
            case 'ratings':
              ratingsData = mapped;
            case 'bpm':
              bpmData = mapped;
            case 'eq':
              perSongEqData = mapped;
            case 'vol':
              perSongVolData = mapped;
            case 'bookmarks':
              bookmarksData = mapped;
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to encode per-song backup data',
          error: e, stackTrace: st, category: 'Backup');
    }

    // 10. Saved queue (paths in order + current index + position).
    List<String>? queuePaths;
    int? queueIndex;
    int? queuePositionMs;
    try {
      final queueRes = await _repository.getSavedQueue();
      final items = queueRes.fold((l) => <QueueItemsTableData>[], (r) => r);
      if (items.isNotEmpty) {
        items.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        final byId = {for (final s in allSongs) s.id: s};
        queuePaths = [
          for (final it in items)
            if (byId.containsKey(it.songId)) byId[it.songId]!.path
        ];
        final cur = items.indexWhere((e) => e.isCurrent);
        queueIndex = cur == -1 ? 0 : cur;
        queuePositionMs =
            cur == -1 ? 0 : items[cur].positionMs;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to encode queue backup data',
          error: e, stackTrace: st, category: 'Backup');
    }

    final backupPayload = {
      'version': 4,
      'exportedAt': DateTime.now().toIso8601String(),
      'favorites': favoritePaths,
      'playlists': playlistsData,
      'settings': settingsMap,
      'playHistory': historyData,
      'excludedFolders': excludedFolders,
      if (customEqProfilesData != null) 'customEqProfiles': customEqProfilesData,
      if (automationRulesData != null) 'automationRules': automationRulesData,
      if (dspSnapshotsRaw != null) 'dspSnapshots': dspSnapshotsRaw,
      if (deviceProfilesRaw != null) 'deviceProfiles': deviceProfilesRaw,
      if (deviceRegistryRaw != null) 'deviceRegistry': deviceRegistryRaw,
      if (settingsProfilesRaw != null) 'settingsProfiles': settingsProfilesRaw,
      if (downloadedTracks.isNotEmpty) 'downloads': downloadedTracks,
      if (ratingsData != null) 'ratings': ratingsData,
      if (bpmData != null) 'bpmOverrides': bpmData,
      if (perSongEqData != null) 'perSongEq': perSongEqData,
      if (perSongVolData != null) 'perSongVolume': perSongVolData,
      if (bookmarksData != null) 'bookmarks': bookmarksData,
      if (queuePaths != null && queuePaths.isNotEmpty)
        'queue': {
          'paths': queuePaths,
          'currentIndex': queueIndex ?? 0,
          'positionMs': queuePositionMs ?? 0,
        },
    };

    return const JsonEncoder.withIndent('  ').convert(backupPayload);
  }
}

@singleton
class ImportBackupUseCase {
  static const int maxBackupSizeBytes = 10 * 1024 * 1024; // 10 MB payload limit

  final IMusicRepository _repository;
  final AppDatabase _db;

  ImportBackupUseCase(this._repository, this._db);

  Future<ImportResult> executeFromFile(Object file) async {
    if (file is! String) {
      try {
        final len = await (file as dynamic).length();
        if (len > maxBackupSizeBytes) {
          throw const FormatException(
              'Backup file exceeds maximum allowed size of 10 MB');
        }
        final content = await (file as dynamic).readAsString();
        return await execute(content);
      } catch (e) {
        if (e is FormatException) rethrow;
        throw FormatException('Failed reading backup file: $e');
      }
    }
    return execute(file);
  }

  Future<ImportResult> execute(String jsonString) async {
    // Cheap length check first (chars) to avoid double alloc for size check — prevents OOM on low RAM
    if (jsonString.length > maxBackupSizeBytes) {
      throw const FormatException(
          'Backup file exceeds maximum allowed size of 10 MB');
    } else if (utf8.encode(jsonString).length > maxBackupSizeBytes) {
      throw const FormatException(
          'Backup file exceeds maximum allowed size of 10 MB');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (e, st) {
      ErrorLogger.log('Corrupted JSON structure in backup file',
          error: e, stackTrace: st, category: 'Backup');
      throw const FormatException('Corrupted or invalid JSON format');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'Invalid backup payload: root object must be a JSON map');
    }

    final data = decoded;
    _validateSchema(data);

    // Fetch all current library songs (including YTM tracks) for path matching
    final allSongs = await _db.select(_db.songsTable).get();

    // Build lightweight direct lookup maps; fallbacks are initialized lazily only if needed
    final pathMap = <String, SongsTableData>{};
    final remoteIdMap = <String, SongsTableData>{};

    for (final song in allSongs) {
      pathMap[song.path] = song;
      pathMap[song.path.replaceAll('\\', '/').toLowerCase()] = song;
      if (song.remoteId != null && song.remoteId!.isNotEmpty) {
        remoteIdMap[song.remoteId!] = song;
      }
    }

    Map<String, SongsTableData>? lazyParentFilenameMap;
    Map<String, SongsTableData>? lazyUniqueFilenameMap;

    SongsTableData? matchPath(String path) {
      // 1. Exact or normalized path match
      final direct =
          pathMap[path] ?? pathMap[path.replaceAll('\\', '/').toLowerCase()];
      if (direct != null) return direct;

      // 2. Fallback for ytmusic:// paths matching by remoteId
      if (path.startsWith('ytmusic://')) {
        final videoId = path.replaceFirst('ytmusic://', '').split('?').first;
        final remoteMatch = remoteIdMap[videoId];
        if (remoteMatch != null) return remoteMatch;
      }

      final normPath = path.replaceAll('\\', '/').toLowerCase();
      final segments = normPath.split('/');

      // 3. Parent + Filename fallback (lazy init)
      if (segments.length >= 2) {
        lazyParentFilenameMap ??= {
          for (final s in allSongs)
            if (s.path.replaceAll('\\', '/').split('/').length >= 2)
              '${s.path.replaceAll('\\', '/').split('/')[s.path.replaceAll('\\', '/').split('/').length - 2].toLowerCase()}/${s.path.replaceAll('\\', '/').split('/').last.toLowerCase()}':
                  s
        };
        final parentAndFilename =
            '${segments[segments.length - 2]}/${segments.last}';
        final match = lazyParentFilenameMap![parentAndFilename];
        if (match != null) return match;
      }

      // 4. Unique filename fallback (lazy init)
      final filename = segments.isNotEmpty ? segments.last : '';
      if (filename.isNotEmpty) {
        if (lazyUniqueFilenameMap == null) {
          final countMap = <String, int>{};
          final nameMap = <String, SongsTableData>{};
          for (final s in allSongs) {
            final fName =
                s.path.replaceAll('\\', '/').split('/').last.toLowerCase();
            if (fName.isNotEmpty) {
              countMap[fName] = (countMap[fName] ?? 0) + 1;
              nameMap[fName] = s;
            }
          }
          lazyUniqueFilenameMap = {
            for (final entry in nameMap.entries)
              if (countMap[entry.key] == 1) entry.key: entry.value
          };
        }
        final match = lazyUniqueFilenameMap![filename];
        if (match != null) return match;
      }
      return null;
    }

    final unmatchedPaths = <String>{};

    // 1. Restore Favorites (Transaction 1)
    int restoredFavoritesCount = 0;
    if (data['favorites'] != null && data['favorites'] is List) {
      final favList = (data['favorites'] as List)
          .whereType<String>()
          .where((p) => p.trim().isNotEmpty)
          .toList();
      await _db.transaction(() async {
        for (final path in favList) {
          final matchedSong = matchPath(path);
          if (matchedSong != null) {
            await (_db.update(_db.songsTable)
                  ..where((t) => t.id.equals(matchedSong.id)))
                .write(const SongsTableCompanion(isFavorite: Value(true)));
            restoredFavoritesCount++;
          } else {
            unmatchedPaths.add(path);
          }
        }
      });
    }

    // 2. Restore Playlists (Transaction per playlist)
    int restoredPlaylistsCount = 0;
    if (data['playlists'] != null && data['playlists'] is List) {
      final playlistsList = data['playlists'] as List;
      for (final item in playlistsList) {
        if (item is Map<String, dynamic> && item.containsKey('name')) {
          await _db.transaction(() async {
            final name = item['name'] as String? ?? 'Restored Playlist';
            final isSmart = item['isSmart'] as bool? ?? false;
            final smartCriteria = item['smartCriteria'] as String?;
            final songPaths = (item['songPaths'] is List)
                ? (item['songPaths'] as List).whereType<String>().toList()
                : <String>[];

            final existingPlaylistsRes = await _repository.getPlaylists();
            final existingList = existingPlaylistsRes.fold(
                (l) => <PlaylistsTableData>[], (r) => r);
            final existing = existingList
                .where((p) =>
                    p.name.toLowerCase().trim() == name.toLowerCase().trim())
                .firstOrNull;

            int? playlistId;
            if (existing != null) {
              playlistId = existing.id;
              if (isSmart && smartCriteria != null) {
                await _repository.updateSmartPlaylist(
                    existing.id, name, smartCriteria);
              }
            } else {
              final createRes = await _repository.createPlaylist(
                name,
                isSmart: isSmart,
                smartCriteria: smartCriteria,
              );
              playlistId = createRes.fold(
                (f) => null,
                (id) => id,
              );
            }

            if (playlistId != null) {
              if (!isSmart) {
                final matchedSongIds = <int>[];
                for (final path in songPaths) {
                  final matched = matchPath(path);
                  if (matched != null) {
                    if (!matchedSongIds.contains(matched.id)) {
                      matchedSongIds.add(matched.id);
                    }
                  } else {
                    unmatchedPaths.add(path);
                  }
                }

                if (matchedSongIds.isNotEmpty) {
                  await _repository.addSongsToPlaylist(
                      playlistId, matchedSongIds);
                }
              }
              restoredPlaylistsCount++;
            }
          });
        }
      }
    }

    // 3. Restore Settings (No DB transaction required)
    int restoredSettingsCount = 0;
    if (data['settings'] is Map<String, dynamic>) {
      final settings = data['settings'] as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();

      if (settings.containsKey('gaplessPlayback')) {
        await prefs.setBool(
            'setting_gapless', settings['gaplessPlayback'] == true);
      }
      if (settings.containsKey('crossfadeSeconds')) {
        final raw = settings['crossfadeSeconds'];
        final val = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '0') ?? 0.0;
        await prefs.setDouble('setting_crossfade', val);
      }
      if (settings.containsKey('minDurationSec')) {
        final raw = settings['minDurationSec'];
        final val = raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '30') ?? 30;
        await prefs.setInt('setting_min_duration', val);
      }
      if (settings.containsKey('dynamicThemingEnabled')) {
        await prefs.setBool(
            'setting_dynamic_theme', settings['dynamicThemingEnabled'] == true);
      }
      if (settings['themeColorSource'] is String) {
        await prefs.setString('setting_theme_color_source',
            settings['themeColorSource'] as String);
      }
      if (settings.containsKey('resumeAfterInterruption')) {
        await prefs.setBool('setting_resume_after_interruption',
            settings['resumeAfterInterruption'] == true);
      }
      if (settings.containsKey('themeMode')) {
        await prefs.setString(
            'setting_theme_mode', (settings['themeMode'] as String?) ?? 'dark');
      }
      if (settings.containsKey('customAccentColorValue')) {
        await prefs.setInt(
            'setting_custom_accent',
            ((settings['customAccentColorValue'] as num?) ?? 0xFF9B9EF5)
                .toInt());
      }
      if (settings.containsKey('playerThemeMode')) {
        await prefs.setString('setting_player_theme_mode',
            (settings['playerThemeMode'] as String?) ?? 'classic');
      }
      if (settings.containsKey('visualizerStyle')) {
        await prefs.setString('setting_visualizer_style',
            (settings['visualizerStyle'] as String?) ?? 'bar');
      }
      // Restore extended settings with validation
      if (settings['replayGainMode'] is String) await prefs.setString('setting_replay_gain_mode', settings['replayGainMode']);
      if (settings['replayGainPreampWithRg'] is num) await prefs.setDouble('setting_replay_gain_preamp_with_rg', (settings['replayGainPreampWithRg'] as num).toDouble());
      if (settings['replayGainPreampWithoutRg'] is num) await prefs.setDouble('setting_replay_gain_preamp_without_rg', (settings['replayGainPreampWithoutRg'] as num).toDouble());
      if (settings['wifiOnlyMode'] is bool) await prefs.setBool('setting_wifi_only_mode', settings['wifiOnlyMode']);
      if (settings['offlineOnlyMode'] is bool) await prefs.setBool('setting_offline_only_mode', settings['offlineOnlyMode']);
      if (settings['bitPerfectMode'] is bool) await prefs.setBool('setting_bit_perfect', settings['bitPerfectMode']);
      if (settings['dspPreference'] is String) await prefs.setString('setting_dsp_preference', settings['dspPreference']);
      if (settings['streamingQuality'] is String) await prefs.setString('setting_streaming_quality', settings['streamingQuality']);
      if (settings['downloadQuality'] is String) await prefs.setString('setting_download_quality', settings['downloadQuality']);
      if (settings['isLosslessMode'] is bool) await prefs.setBool('setting_lossless', settings['isLosslessMode']);
      if (settings['eqEnabled'] is bool) await prefs.setBool(PrefsKeys.eqEnabled, settings['eqEnabled']);
      if (settings['eqGains'] is String) await prefs.setString(PrefsKeys.eqGains, settings['eqGains']);
      if (settings['eqPreset'] is String) await prefs.setString(PrefsKeys.eqPresetName, settings['eqPreset']);
      if (settings['eqPreamp'] is num) await prefs.setDouble(PrefsKeys.eqPreamp, (settings['eqPreamp'] as num).toDouble());
      if (settings['eqBandCount'] is int) await prefs.setInt(PrefsKeys.eqBandCount, settings['eqBandCount']);
      if (settings['eqCustomFrequencies'] is String) await prefs.setString(PrefsKeys.eqCustomFrequencies, settings['eqCustomFrequencies']);
      if (settings['eqCustom32Frequencies'] is String) await prefs.setString(PrefsKeys.eqCustom32Frequencies, settings['eqCustom32Frequencies']);
      if (settings['eqCustom64Frequencies'] is String) await prefs.setString(PrefsKeys.eqCustom64Frequencies, settings['eqCustom64Frequencies']);
      if (settings['playbackSpeed'] is num) await prefs.setDouble('setting_playback_speed', (settings['playbackSpeed'] as num).toDouble());

      restoredSettingsCount = settings.length;
    }

    // 4. Restore Play History (Batched Transactions of 100)
    int restoredHistoryCount = 0;
    if (data['playHistory'] != null && data['playHistory'] is List) {
      final historyList = data['playHistory'] as List;
      for (var i = 0; i < historyList.length; i += 100) {
        final batch =
            historyList.sublist(i, math.min(i + 100, historyList.length));
        await _db.transaction(() async {
          for (final item in batch) {
            if (item is Map<String, dynamic>) {
              final path = item['path'] as String?;
              final playCount = (item['playCount'] as num?)?.toInt() ?? 0;
              final lastPlayed = (item['lastPlayed'] as num?)?.toInt();

              if (path != null && path.isNotEmpty) {
                final matched = matchPath(path);
                if (matched != null) {
                  // Merge with max to avoid restore reducing play counts incremented since backup
                  final mergedCount = playCount > matched.playCount ? playCount : matched.playCount;
                  final mergedLastPlayed = (lastPlayed != null && matched.lastPlayed != null)
                      ? (lastPlayed > matched.lastPlayed! ? lastPlayed : matched.lastPlayed!)
                      : (lastPlayed ?? matched.lastPlayed);
                  await (_db.update(_db.songsTable)
                        ..where((t) => t.id.equals(matched.id)))
                      .write(
                    SongsTableCompanion(
                      playCount: Value(mergedCount),
                      lastPlayed: Value(mergedLastPlayed),
                    ),
                  );
                  restoredHistoryCount++;
                } else {
                  unmatchedPaths.add(path);
                }
              }
            }
          }
        });
      }
    }

    // 5. Restore Excluded Folders
    int restoredExcludedCount = 0;
    if (data['excludedFolders'] != null && data['excludedFolders'] is List) {
      final folderList =
          (data['excludedFolders'] as List).whereType<String>().toList();
      final existingExcluded = await _repository.getExcludedFolderPaths();
      final existingPaths =
          existingExcluded.fold((l) => <String>[], (r) => r).toSet();

      for (final path in folderList) {
        if (path.isNotEmpty && !existingPaths.contains(path)) {
          await _repository.toggleFolderExclusion(path);
          restoredExcludedCount++;
        }
      }
    }

    // 6. Restore Custom EQ Profiles
    int restoredEqProfilesCount = 0;
    final prefs = await SharedPreferences.getInstance();
    if (data['customEqProfiles'] != null) {
      try {
        final profilesData = data['customEqProfiles'];
        final serialized = jsonEncode(profilesData);
        await prefs.setString(PrefsKeys.customEqProfiles, serialized);
        restoredEqProfilesCount = (profilesData is List) ? profilesData.length : 1;
      } catch (e, st) {
        ErrorLogger.log('Failed restoring custom EQ profiles',
            error: e, stackTrace: st, category: 'Backup');
      }
    }

    // 7. Restore Automation Rules
    int restoredAutomationRulesCount = 0;
    if (data['automationRules'] != null && data['automationRules'] is List) {
      try {
        final rulesList = data['automationRules'] as List;
        await prefs.setString('setting_automation_rules', jsonEncode(rulesList));
        restoredAutomationRulesCount = rulesList.length;
      } catch (e, st) {
        ErrorLogger.log('Failed restoring automation rules',
            error: e, stackTrace: st, category: 'Backup');
      }
    }

    // 8. Restore Downloads Metadata
    int restoredDownloadsCount = 0;
    if (data['downloads'] != null && data['downloads'] is List) {
      final dlList = data['downloads'] as List;
      await _db.transaction(() async {
        for (final item in dlList) {
          if (item is Map<String, dynamic>) {
            final path = item['path'] as String?;
            final remoteId = item['remoteId'] as String?;
            final matched = matchPath(path ?? '') ?? (remoteId != null ? remoteIdMap[remoteId] : null);
            if (matched != null && !matched.isDownloaded) {
              await (_db.update(_db.songsTable)
                    ..where((t) => t.id.equals(matched.id)))
                  .write(const SongsTableCompanion(isDownloaded: Value(true)));
              restoredDownloadsCount++;
            }
          }
        }
      });
    }

    // 9. Restore per-song data (v3 keys; merged, never clobbered). Backup keys
    // are portable (path:/yt:/id:); translate them back to this install's
    // MediaStore id. The id-keyed stores want a bare id, bookmarks want the
    // `id:`/`yt:`/`path:` form produced by PlaybackBookmarkStore.keyFor.
    String remapSongKey(String key, {required bool bookmark}) {
      if (key.startsWith('path:')) {
        final m = matchPath(key.substring(5));
        if (m == null) return key;
        return bookmark ? 'id:${m.id}' : '${m.id}';
      }
      if (key.startsWith('yt:')) {
        final remote = key.substring(3);
        final m = remoteIdMap[remote];
        if (m == null) return key;
        return bookmark ? 'yt:$remote' : '${m.id}';
      }
      if (key.startsWith('id:')) {
        final n = int.tryParse(key.substring(3));
        if (n == null) return key;
        return bookmark ? 'id:$n' : '$n';
      }
      return key;
    }

    Future<void> mergePrefsMap(String key, dynamic incoming,
        {bool bookmark = false}) async {
      if (incoming is! Map) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        final existing = prefs.getString(key);
        final base =
            (existing != null && existing.isNotEmpty) ? jsonDecode(existing) : {};
        final merged = <String, dynamic>{
          if (base is Map<String, dynamic>) ...base,
          for (final e in incoming.entries)
            remapSongKey(e.key.toString(), bookmark: bookmark): e.value,
        };
        await prefs.setString(key, jsonEncode(merged));
      } catch (e, st) {
        ErrorLogger.log('Failed restoring $key',
            error: e, stackTrace: st, category: 'Backup');
      }
    }

    await mergePrefsMap('song_ratings_v1', data['ratings']);
    await mergePrefsMap('per_track_bpm_overrides_v1', data['bpmOverrides']);
    await mergePrefsMap('per_song_eq_overrides_v1', data['perSongEq']);
    await mergePrefsMap('per_song_volume_overrides_v1', data['perSongVolume']);
    await mergePrefsMap('playback_bookmarks_v1', data['bookmarks'],
        bookmark: true);

    // 9b. Backup v2 restore: verbatim raw profile/snapshot blobs.
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final e in {
        'dspSnapshots': 'dsp_snapshot_store_v1',
        'deviceProfiles': 'setting_device_profile_links',
        'deviceRegistry': 'setting_device_registry',
        'settingsProfiles': 'setting_custom_profiles',
      }.entries) {
        final v = data[e.key];
        if (v is String && v.isNotEmpty) {
          await prefs.setString(e.value, v);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed restoring v2 profile blobs',
          error: e, stackTrace: st, category: 'Backup');
    }

    // 10. Restore saved queue (paths resolved against the fresh library).
    if (data['queue'] is Map<String, dynamic>) {
      final q = data['queue'] as Map<String, dynamic>;
      final paths = (q['paths'] is List)
          ? (q['paths'] as List).whereType<String>().toList()
          : <String>[];
      final idx = (q['currentIndex'] as num?)?.toInt() ?? 0;
      final posMs = (q['positionMs'] as num?)?.toInt() ?? 0;
      if (paths.isNotEmpty) {
        try {
          await _db.transaction(() async {
            await _db.delete(_db.queueItemsTable).go();
            var order = 0;
            for (var i = 0; i < paths.length; i++) {
              final matched = matchPath(paths[i]);
              if (matched == null) {
                unmatchedPaths.add(paths[i]);
                continue;
              }
              await _db.into(_db.queueItemsTable).insert(
                    QueueItemsTableCompanion.insert(
                      songId: matched.id,
                      orderIndex: order,
                      isCurrent: Value(i == idx.clamp(0, paths.length - 1)),
                      positionMs:
                          Value(i == idx.clamp(0, paths.length - 1) ? posMs : 0),
                    ),
                  );
              order++;
            }
          });
        } catch (e, st) {
          ErrorLogger.log('Failed restoring queue',
              error: e, stackTrace: st, category: 'Backup');
        }
      }
    }

    return ImportResult(
      restoredFavoritesCount: restoredFavoritesCount,
      restoredPlaylistsCount: restoredPlaylistsCount,
      restoredSettingsCount: restoredSettingsCount,
      restoredHistoryCount: restoredHistoryCount,
      restoredExcludedFoldersCount: restoredExcludedCount,
      restoredEqProfilesCount: restoredEqProfilesCount,
      restoredAutomationRulesCount: restoredAutomationRulesCount,
      restoredDownloadsCount: restoredDownloadsCount,
      unmatchedPaths: unmatchedPaths.toList(),
    );
  }

  void _validateSchema(Map<String, dynamic> data) => validateSchema(data);

  // FIX-E02: Check unsupported future backup versions
  @visibleForTesting
  static void validateSchema(Map<String, dynamic> data) {
    final version = data['version'];
    if (version == null || version is! int || version < 1) {
      throw const FormatException('Invalid backup version: missing or malformed version field');
    }
    if (version > 4) {
      throw FormatException('Unsupported backup version: $version. Please update Pulsr.');
    }

    if (data['favorites'] != null && data['favorites'] is! List) {
      throw const FormatException('favorites must be a list');
    }

    if (data['playlists'] != null) {
      if (data['playlists'] is! List) {
        throw const FormatException('playlists must be a list');
      }
      for (final item in data['playlists'] as List) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Playlist entries must be objects');
        }
        final name = item['name'];
        if (name is! String || name.trim().isEmpty) {
          throw const FormatException('Playlist missing or empty name field');
        }
        if (item['songPaths'] != null && item['songPaths'] is! List) {
          throw const FormatException('Playlist songPaths must be a list');
        }
      }
    }

    if (data['settings'] != null && data['settings'] is! Map) {
      throw const FormatException('settings must be a JSON object');
    }

    if (data['playHistory'] != null && data['playHistory'] is! List) {
      throw const FormatException('playHistory must be a list');
    }

    if (data['excludedFolders'] != null && data['excludedFolders'] is! List) {
      throw const FormatException('excludedFolders must be a list');
    }

    if (data['customEqProfiles'] != null && data['customEqProfiles'] is! List && data['customEqProfiles'] is! Map) {
      throw const FormatException('customEqProfiles must be a list or map');
    }

    if (data['automationRules'] != null && data['automationRules'] is! List) {
      throw const FormatException('automationRules must be a list');
    }

    if (data['downloads'] != null && data['downloads'] is! List) {
      throw const FormatException('downloads must be a list');
    }
  }
}
