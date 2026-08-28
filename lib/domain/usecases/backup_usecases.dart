// lib/domain/usecases/backup_usecases.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/backup_crypto.dart';
import '../../core/utils/error_logger.dart';
import '../../data/db/app_database.dart';
import '../repositories/music_repository_interface.dart';

class ImportResult {
  final int restoredFavoritesCount;
  final int restoredPlaylistsCount;
  final int restoredSettingsCount;
  final int restoredHistoryCount;
  final int restoredExcludedFoldersCount;
  final List<String> unmatchedPaths;

  const ImportResult({
    this.restoredFavoritesCount = 0,
    this.restoredPlaylistsCount = 0,
    this.restoredSettingsCount = 0,
    this.restoredHistoryCount = 0,
    this.restoredExcludedFoldersCount = 0,
    this.unmatchedPaths = const [],
  });
}

@singleton
class ExportBackupUseCase {
  final IMusicRepository _repository;

  ExportBackupUseCase(this._repository);

  Future<String> execute({bool encrypt = false, String? passphrase}) async {
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

    // 3. Settings (gapless, crossfade, theme, eqPreset, etc.)
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic>? eqPresetMap;
    final eqPresetStr = prefs.getString('setting_eq_preset');
    if (eqPresetStr != null) {
      try {
        final decoded = jsonDecode(eqPresetStr);
        if (decoded is Map<String, dynamic>) {
          eqPresetMap = decoded;
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to decode eqPreset from prefs',
            error: e, stackTrace: st, category: 'Backup');
      }
    }

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
      'eqEnabled': prefs.getBool('setting_eq_enabled') ?? false,
      'eqGains': prefs.getString('setting_eq_gains'),
      'playbackSpeed': prefs.getDouble('setting_playback_speed') ?? 1.0,
      if (eqPresetMap != null) 'eqPreset': eqPresetMap,
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

    final backupPayload = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'favorites': favoritePaths,
      'playlists': playlistsData,
      'settings': settingsMap,
      'playHistory': historyData,
      'excludedFolders': excludedFolders,
    };

    final rawJson = const JsonEncoder.withIndent('  ').convert(backupPayload);
    if (encrypt) {
      final envelope = BackupCrypto.encryptBackup(
        rawJson,
        passphrase: passphrase ?? BackupCrypto.defaultAppSalt,
      );
      return const JsonEncoder.withIndent('  ').convert(envelope);
    }
    return rawJson;
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
        return execute(content);
      } catch (e) {
        if (e is FormatException) rethrow;
        throw FormatException('Failed reading backup file: $e');
      }
    }
    return execute(file);
  }

  Future<ImportResult> execute(String jsonString, {String? passphrase}) async {
    // Cheap length check first (chars) to avoid double alloc for size check — prevents OOM on low RAM
    if (jsonString.length > maxBackupSizeBytes) {
      if (utf8.encode(jsonString).length > maxBackupSizeBytes) {
        throw const FormatException(
            'Backup file exceeds maximum allowed size of 10 MB');
      }
    } else if (utf8.encode(jsonString).length > maxBackupSizeBytes) {
      throw const FormatException(
          'Backup file exceeds maximum allowed size of 10 MB');
    }

    dynamic decoded;
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

    // Version 2 Encrypted Backup Envelope handling ([S1])
    if (decoded['version'] == 2 || decoded['format'] == BackupCrypto.formatV2) {
      final decryptedPlaintext = BackupCrypto.decryptBackup(
        decoded,
        passphrase: passphrase ?? BackupCrypto.defaultAppSalt,
      );
      final innerDecoded = jsonDecode(decryptedPlaintext);
      if (innerDecoded is! Map<String, dynamic>) {
        throw const FormatException('Decrypted backup payload is not a valid JSON object');
      }
      decoded = innerDecoded;
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
            final existing =
                existingList.where((p) => p.name == name).firstOrNull;

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
      if (settings.containsKey('eqPreset') && settings['eqPreset'] is Map) {
        await prefs.setString(
            'setting_eq_preset', jsonEncode(settings['eqPreset']));
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
      if (settings['eqEnabled'] is bool) await prefs.setBool('setting_eq_enabled', settings['eqEnabled']);
      if (settings['eqGains'] is String) await prefs.setString('setting_eq_gains', settings['eqGains']);
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

    return ImportResult(
      restoredFavoritesCount: restoredFavoritesCount,
      restoredPlaylistsCount: restoredPlaylistsCount,
      restoredSettingsCount: restoredSettingsCount,
      restoredHistoryCount: restoredHistoryCount,
      restoredExcludedFoldersCount: restoredExcludedCount,
      unmatchedPaths: unmatchedPaths.toList(),
    );
  }

  void _validateSchema(Map<String, dynamic> data) {
    final version = data['version'];
    if (version == null || version is! int || version < 1) {
      throw const FormatException('Invalid or unsupported backup version');
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
  }
}
