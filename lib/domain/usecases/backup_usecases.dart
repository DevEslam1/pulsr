// lib/domain/usecases/backup_usecases.dart
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  Future<String> execute() async {
    // 1. Favorites
    final favoritesResult = await _repository.getFavorites();
    final favoritesSongs = favoritesResult.fold((l) => <SongsTableData>[], (r) => r);
    final favoritePaths = favoritesSongs.map((s) => s.path).toList();

    // 2. Playlists with song file paths
    final playlistsResult = await _repository.getPlaylists();
    final playlists = playlistsResult.fold((l) => <PlaylistsTableData>[], (r) => r);
    final playlistsData = <Map<String, dynamic>>[];

    for (final pl in playlists) {
      final songsResult = await _repository.getPlaylistSongs(pl.id);
      final playlistSongs = songsResult.fold((l) => <SongsTableData>[], (r) => r);
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
        ErrorLogger.log('Failed to decode eqPreset from prefs', error: e, stackTrace: st, category: 'Backup');
      }
    }

    final settingsMap = {
      'gaplessPlayback': prefs.getBool('setting_gapless') ?? true,
      'crossfadeSeconds': prefs.getDouble('setting_crossfade') ?? 0.0,
      'minDurationSec': prefs.getInt('setting_min_duration') ?? 30,
      'dynamicThemingEnabled': prefs.getBool('setting_dynamic_theme') ?? true,
      'themeColorSource': prefs.getString('setting_theme_color_source'),
      'resumeAfterInterruption': prefs.getBool('setting_resume_after_interruption') ?? true,
      'themeMode': prefs.getString('setting_theme_mode') ?? 'dark',
      'customAccentColorValue': prefs.getInt('setting_custom_accent') ?? 0xFF9B9EF5,
      'playerThemeMode': prefs.getString('setting_player_theme_mode') ?? 'classic',
      'visualizerStyle': prefs.getString('setting_visualizer_style') ?? 'bar',
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

    return const JsonEncoder.withIndent('  ').convert(backupPayload);
  }
}

@singleton
class ImportBackupUseCase {
  static const int maxBackupSizeBytes = 10 * 1024 * 1024; // 10 MB payload limit

  final IMusicRepository _repository;
  final AppDatabase _db;

  ImportBackupUseCase(this._repository, this._db);

  Future<ImportResult> execute(String jsonString) async {
    if (jsonString.length > maxBackupSizeBytes) {
      throw const FormatException('Backup file exceeds maximum allowed size of 10 MB');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (e, st) {
      ErrorLogger.log('Corrupted JSON structure in backup file', error: e, stackTrace: st, category: 'Backup');
      throw const FormatException('Corrupted or invalid JSON format');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup payload: root object must be a JSON map');
    }

    final data = decoded;
    final version = data['version'];
    if (version == null || version is! int || version < 1) {
      throw const FormatException('Invalid or unsupported backup version');
    }

    return _db.transaction(() async {
    // Fetch all current library songs for path matching
    final songsResult = await _repository.getAllSongs();
    final allSongs = songsResult.fold((l) => <SongsTableData>[], (r) => r);

    // Build lookup maps for robust matching (exact, normalized, filename)
    final exactMap = <String, SongsTableData>{};
    final normalizedMap = <String, SongsTableData>{};
    final filenameMap = <String, SongsTableData>{};

    for (final song in allSongs) {
      exactMap[song.path] = song;
      final normPath = song.path.replaceAll('\\', '/').toLowerCase();
      normalizedMap[normPath] = song;
      final filename = song.path.replaceAll('\\', '/').split('/').last.toLowerCase();
      if (filename.isNotEmpty) {
        filenameMap[filename] = song;
      }
    }

    SongsTableData? matchPath(String path) {
      if (exactMap.containsKey(path)) return exactMap[path];
      final normPath = path.replaceAll('\\', '/').toLowerCase();
      if (normalizedMap.containsKey(normPath)) return normalizedMap[normPath];
      final filename = path.replaceAll('\\', '/').split('/').last.toLowerCase();
      if (filenameMap.containsKey(filename)) return filenameMap[filename];
      return null;
    }

    final unmatchedPaths = <String>{};

    // 1. Restore Favorites
    int restoredFavoritesCount = 0;
    if (data['favorites'] is List) {
      final favList = (data['favorites'] as List).cast<String>();
      for (final path in favList) {
        final matchedSong = matchPath(path);
        if (matchedSong != null) {
          await (_db.update(_db.songsTable)..where((t) => t.id.equals(matchedSong.id)))
              .write(const SongsTableCompanion(isFavorite: Value(true)));
          restoredFavoritesCount++;
        } else {
          unmatchedPaths.add(path);
        }
      }
    }

    // 2. Restore Playlists
    int restoredPlaylistsCount = 0;
    if (data['playlists'] is List) {
      final playlistsList = data['playlists'] as List;
      for (final item in playlistsList) {
        if (item is Map<String, dynamic>) {
          final name = item['name'] as String? ?? 'Restored Playlist';
          final isSmart = item['isSmart'] as bool? ?? false;
          final smartCriteria = item['smartCriteria'] as String?;
          final songPaths = (item['songPaths'] as List?)?.cast<String>() ?? [];

          // Create new playlist or find existing by name
          final existingPlaylistsRes = await _repository.getPlaylists();
          final existingList = existingPlaylistsRes.fold((l) => <PlaylistsTableData>[], (r) => r);
          final existing = existingList.where((p) => p.name == name).firstOrNull;

          int? playlistId;
          if (existing != null) {
            playlistId = existing.id;
            if (isSmart && smartCriteria != null) {
              await _repository.updateSmartPlaylist(existing.id, name, smartCriteria);
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
            // For smart playlists, song items are evaluated dynamically from criteria, not manual entries
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
                await _repository.addSongsToPlaylist(playlistId, matchedSongIds);
              }
            }
            restoredPlaylistsCount++;
          }
        }
      }
    }

    // 3. Restore Settings
    int restoredSettingsCount = 0;
    if (data['settings'] is Map<String, dynamic>) {
      final settings = data['settings'] as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();

      if (settings.containsKey('gaplessPlayback')) {
        await prefs.setBool('setting_gapless', settings['gaplessPlayback'] as bool);
      }
      if (settings.containsKey('crossfadeSeconds')) {
        await prefs.setDouble('setting_crossfade', (settings['crossfadeSeconds'] as num).toDouble());
      }
      if (settings.containsKey('minDurationSec')) {
        await prefs.setInt('setting_min_duration', (settings['minDurationSec'] as num).toInt());
      }
      if (settings.containsKey('dynamicThemingEnabled')) {
        await prefs.setBool('setting_dynamic_theme', settings['dynamicThemingEnabled'] as bool);
      }
      if (settings['themeColorSource'] is String) {
        await prefs.setString('setting_theme_color_source', settings['themeColorSource'] as String);
      }
      if (settings.containsKey('resumeAfterInterruption')) {
        await prefs.setBool('setting_resume_after_interruption', settings['resumeAfterInterruption'] as bool);
      }
      if (settings.containsKey('themeMode')) {
        await prefs.setString('setting_theme_mode', settings['themeMode'] as String);
      }
      if (settings.containsKey('customAccentColorValue')) {
        await prefs.setInt('setting_custom_accent', (settings['customAccentColorValue'] as num).toInt());
      }
      if (settings.containsKey('playerThemeMode')) {
        await prefs.setString('setting_player_theme_mode', settings['playerThemeMode'] as String);
      }
      if (settings.containsKey('visualizerStyle')) {
        await prefs.setString('setting_visualizer_style', settings['visualizerStyle'] as String);
      }
      if (settings.containsKey('eqPreset') && settings['eqPreset'] is Map) {
        await prefs.setString('setting_eq_preset', jsonEncode(settings['eqPreset']));
      }

      restoredSettingsCount = settings.length;
    }

    // 4. Restore Play History
    int restoredHistoryCount = 0;
    if (data['playHistory'] is List) {
      final historyList = data['playHistory'] as List;
      for (final item in historyList) {
        if (item is Map<String, dynamic>) {
          final path = item['path'] as String?;
          final playCount = (item['playCount'] as num?)?.toInt() ?? 0;
          final lastPlayed = (item['lastPlayed'] as num?)?.toInt();

          if (path != null) {
            final matched = matchPath(path);
            if (matched != null) {
              await (_db.update(_db.songsTable)..where((t) => t.id.equals(matched.id))).write(
                SongsTableCompanion(
                  playCount: Value(playCount),
                  lastPlayed: Value(lastPlayed),
                ),
              );
              restoredHistoryCount++;
            } else {
              unmatchedPaths.add(path);
            }
          }
        }
      }
    }

    // 5. Restore Excluded Folders
    int restoredExcludedCount = 0;
    if (data['excludedFolders'] is List) {
      final folderList = (data['excludedFolders'] as List).cast<String>();
      final existingExcluded = await _repository.getExcludedFolderPaths();
      final existingPaths = existingExcluded.fold((l) => <String>[], (r) => r).toSet();

      for (final path in folderList) {
        if (!existingPaths.contains(path)) {
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
    });
  }
}
