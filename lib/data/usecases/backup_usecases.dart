// lib/data/usecases/backup_usecases.dart
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/di/injection.dart';
import '../../core/utils/error_logger.dart';
import '../../data/db/app_database.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../features/settings/cubit/settings_state.dart';
import '../audio/audio_handler.dart';
import '../audio/per_song_eq_store.dart';
import '../audio/per_song_volume_store.dart';
import '../audio/song_rating_store.dart';

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

/// CUE chapters share one container path, so a plain path cannot identify
/// them in a backup. Append the chapter's start offset; imported backups
/// without the suffix keep matching by plain path.
const String _cueRefMarker = '#pulsr_cue=';

String _composeSongRef(String path, int? cueStartMs) {
  if (cueStartMs == null || cueStartMs < 0) return path;
  return '$path$_cueRefMarker$cueStartMs';
}

String _songRef(SongsTableData song) =>
    _composeSongRef(song.path, song.cueStartMs);

({String path, int? cueStartMs}) _parseSongRef(String ref) {
  final markerAt = ref.lastIndexOf(_cueRefMarker);
  if (markerAt < 0) return (path: ref, cueStartMs: null);
  final cueStartMs =
      int.tryParse(ref.substring(markerAt + _cueRefMarker.length));
  if (cueStartMs == null) return (path: ref, cueStartMs: null);
  return (path: ref.substring(0, markerAt), cueStartMs: cueStartMs);
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
    final favoritePaths = favoritesSongs.map(_songRef).toList();

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
        'songPaths': playlistSongs.map(_songRef).toList(),
      });
    }

    // 3. Settings (gapless, crossfade, theme, EQ, etc.)
    final prefs = await SharedPreferences.getInstance();
    final settingsMap = {
      'gaplessPlayback': prefs.getBool('setting_gapless') ?? false,
      'crossfadeSeconds': prefs.getDouble('setting_crossfade') ?? 0.0,
      'minDurationSec': prefs.getInt('setting_min_duration') ?? 30,
      'dynamicThemingEnabled': prefs.getBool('setting_dynamic_theme') ?? true,
      'themeColorSource': prefs.getString('setting_theme_color_source'),
      'resumeAfterInterruption':
          prefs.getBool('setting_resume_after_interruption') ?? true,
      'themeMode': prefs.getString('setting_theme_mode') ?? 'dark',
      'customAccentColorValue':
          prefs.getInt('setting_custom_accent') ?? 0xFF9B9EF5,
      'playerThemeMode': PlayerThemeMode.fromName(
        prefs.getString('setting_player_theme_mode'),
      ).name,
      'playerSliderStyle':
          prefs.getString('setting_player_slider_style') ?? 'normal',
      'appButtonStyle':
          prefs.getString('setting_app_button_style') ?? 'rectangular',
      'visualizerStyle': prefs.getString('setting_visualizer_style') ?? 'bar',
      // Extended settings (previously missing — caused data loss on restore)
      'replayGainMode': prefs.getString('setting_replay_gain_mode') ?? 'track',
      'replayGainPreampWithRg':
          prefs.getDouble('setting_replay_gain_preamp_with_rg') ?? 0.0,
      'replayGainPreampWithoutRg':
          prefs.getDouble('setting_replay_gain_preamp_without_rg') ?? -3.0,
      'wifiOnlyMode': prefs.getBool('setting_wifi_only_mode') ?? false,
      'offlineOnlyMode': prefs.getBool('setting_offline_only_mode') ?? false,
      // The live key is …_output; the old 'setting_bit_perfect' key has no
      // reader, so restoring a backup used to report success while leaving
      // bit-perfect off.
      'bitPerfectMode': prefs.getBool(PrefsKeys.bitPerfectOutput) ?? false,
      'dspPreference': prefs.getString('setting_dsp_preference') ?? 'native',
      'streamingQuality':
          prefs.getString('setting_streaming_quality') ?? 'high',
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
      // Appearance & accessibility: these were omitted from backups, so a
      // device migration silently reset the user's look and comfort settings.
      'languageCode': prefs.getString(PrefsKeys.languageCode) ?? 'system',
      'highContrast': prefs.getBool('setting_high_contrast') ?? false,
      'dimWhitePoint': prefs.getBool('setting_dim_white_point') ?? false,
      'reduceMotion': prefs.getBool('setting_reduce_motion') ?? false,
      'hapticsEnabled': prefs.getBool(PrefsKeys.hapticsEnabled) ?? true,
      'liquidGlassTint': prefs.getDouble(PrefsKeys.liquidGlassTint) ?? 0.8,
      'visualDensityMode':
          prefs.getString(PrefsKeys.visualDensityMode) ?? 'comfortable',
      'customThemeRadius':
          prefs.getDouble('setting_custom_theme_radius') ?? 18.0,
      'customThemeGlow': prefs.getBool('setting_custom_theme_glow') ?? true,
      'miniPlayerSwipeLeft':
          prefs.getString('setting_mini_player_swipe_left'),
      'miniPlayerSwipeRight':
          prefs.getString('setting_mini_player_swipe_right'),
      'nowPlayingDoubleTap':
          prefs.getString('setting_now_playing_double_tap'),
      'nowPlayingArtworkSwipe':
          prefs.getString('setting_now_playing_artwork_swipe'),
      'dockStackMode': prefs.getString(PrefsKeys.dockStackMode),
      'canvasEnabled': prefs.getBool('setting_canvas_enabled') ?? false,
      'canvasAsBackdrop': prefs.getBool('setting_canvas_as_backdrop') ?? false,
      'waveformSeekBar': prefs.getBool('setting_waveform_seek_bar') ?? false,
      'autoThemeByTime': prefs.getBool('setting_auto_theme_by_time') ?? false,
      'themeScheduleStart': prefs.getInt('setting_theme_schedule_start'),
      'themeScheduleEnd': prefs.getInt('setting_theme_schedule_end'),
      for (final k in prefs.getKeys())
        if (k.startsWith('announce_') || k.startsWith('sysbeh_'))
          if (prefs.get(k) != null) k: prefs.get(k),
    };

    // 4. Play History (paths, count, lastPlayed)
    final allSongsResult = await _repository.getAllSongs();
    final allSongs = allSongsResult.fold((l) => <SongsTableData>[], (r) => r);
    final historyData = <Map<String, dynamic>>[];
    for (final song in allSongs) {
      if (song.playCount > 0 || song.lastPlayed != null) {
        historyData.add({
          'path': _songRef(song),
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
    // 8. Downloaded & Online Tracks Metadata (so fresh installs can restore YTM favorites/playlists)
    final onlineReferencedSongs = <int, SongsTableData>{
      for (final s in favoritesSongs)
        if (s.source != SongSource.local || s.path.startsWith('ytmusic://'))
          s.id: s,
    };
    for (final s in allSongs) {
      if (s.source != SongSource.local || s.path.startsWith('ytmusic://')) {
        onlineReferencedSongs[s.id] = s;
      }
    }
    final onlineTracks = onlineReferencedSongs.values
        .map((s) => {
              'title': s.title,
              'artist': s.artist,
              'album': s.album,
              'path': _songRef(s),
              'remoteId': s.remoteId,
              'remoteArtworkUrl': s.remoteArtworkUrl,
              'durationMs': s.durationMs,
            })
        .toList();

    final downloadedTracks = allSongs
        .where((s) => s.isDownloaded)
        .map((s) => {
              'title': s.title,
              'artist': s.artist,
              'album': s.album,
              'path': _songRef(s),
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
          return 'path:${_songRef(song)}';
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
        // Resolve first, then derive the index: indexing the unfiltered list
        // and exporting only matched paths pointed restore at the wrong track
        // whenever a missing song sat before the current one.
        final resolved =
            <({SongsTableData song, bool isCurrent, int positionMs})>[
          for (final it in items)
            if (byId[it.songId] != null)
              (
                song: byId[it.songId]!,
                isCurrent: it.isCurrent,
                positionMs: it.positionMs,
              )
        ];
        if (resolved.isNotEmpty) {
          queuePaths = [for (final e in resolved) _songRef(e.song)];
          final cur = resolved.indexWhere((e) => e.isCurrent);
          queueIndex = cur == -1 ? 0 : cur;
          queuePositionMs = cur == -1 ? 0 : resolved[cur].positionMs;
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to encode queue backup data',
          error: e, stackTrace: st, category: 'Backup');
    }

    final backupPayload = {
      'version': 5,
      'exportedAt': DateTime.now().toIso8601String(),
      'favorites': favoritePaths,
      'playlists': playlistsData,
      'settings': settingsMap,
      'playHistory': historyData,
      'excludedFolders': excludedFolders,
      if (prefs.getString('usb_quirks_v1') != null)
        'usb_quirks_v1': prefs.getString('usb_quirks_v1'),
      if (prefs.getString('audio_profile_default_id') != null)
        'audio_profile_default_id': prefs.getString('audio_profile_default_id'),
      if (prefs.getString('remote_sources_v1') != null)
        'remote_sources_v1': prefs.getString('remote_sources_v1'),
      if (prefs.getBool('assistant_suggestions_enabled') != null)
        'assistant_suggestions_enabled':
            prefs.getBool('assistant_suggestions_enabled'),
      if (prefs.getString('setting_bt_latency_by_device') != null)
        'setting_bt_latency_by_device':
            prefs.getString('setting_bt_latency_by_device'),
      if (prefs.getBool('setting_auto_device_profiles_enabled') != null)
        'setting_auto_device_profiles_enabled':
            prefs.getBool('setting_auto_device_profiles_enabled'),
      if (customEqProfilesData != null)
        'customEqProfiles': customEqProfilesData,
      if (automationRulesData != null) 'automationRules': automationRulesData,
      if (dspSnapshotsRaw != null) 'dspSnapshots': dspSnapshotsRaw,
      if (deviceProfilesRaw != null) 'deviceProfiles': deviceProfilesRaw,
      if (deviceRegistryRaw != null) 'deviceRegistry': deviceRegistryRaw,
      if (settingsProfilesRaw != null) 'settingsProfiles': settingsProfilesRaw,
      if (downloadedTracks.isNotEmpty) 'downloads': downloadedTracks,
      if (onlineTracks.isNotEmpty) 'onlineTracks': onlineTracks,
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

  Future<ImportResult> executeFromFile(File file) async {
    try {
      final len = await file.length();
      if (len > maxBackupSizeBytes) {
        throw const FormatException(
            'Backup file exceeds maximum allowed size of 10 MB');
      }
      final content = await file.readAsString();
      return await execute(content, knownByteLength: len);
    } catch (e) {
      if (e is FormatException) rethrow;
      throw FormatException('Failed reading backup file: $e');
    }
  }

  Future<ImportResult> execute(String jsonString,
      {int? knownByteLength}) async {
    // FIX B3: Avoid double-allocating a second full copy of a ≤10MB string just to check utf8 size.
    // If the caller already know the byte length (e.g. from File.length()), reuse it directly.
    if (knownByteLength != null) {
      if (knownByteLength > maxBackupSizeBytes) {
        throw const FormatException(
            'Backup file exceeds maximum allowed size of 10 MB');
      }
    } else {
      // String character count is <= byte count for UTF-8 (each char is 1-4 bytes).
      // If char count exceeds 10MB, UTF-8 byte count definitely exceeds 10MB.
      if (jsonString.length > maxBackupSizeBytes) {
        throw const FormatException(
            'Backup file exceeds maximum allowed size of 10 MB');
      }
      // If char count * 4 <= maxBackupSizeBytes (2.5 million chars), UTF-8 is guaranteed <= 10MB
      // without needing to materialize an encoded byte array.
      if (jsonString.length > maxBackupSizeBytes ~/ 4 &&
          utf8.encode(jsonString).length > maxBackupSizeBytes) {
        throw const FormatException(
            'Backup file exceeds maximum allowed size of 10 MB');
      }
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
      final ref = _songRef(song);
      pathMap[ref] = song;
      pathMap[ref.toLowerCase()] = song;
      if (song.remoteId != null && song.remoteId!.isNotEmpty) {
        remoteIdMap[song.remoteId!] = song;
      }
    }

    // Seed any missing online/YTM tracks from `onlineTracks` or `downloads` before matching
    // favorites, playlists, and play history on a fresh install.
    final onlineSeedList = <Map<String, dynamic>>[
      if (data['onlineTracks'] is List)
        ...(data['onlineTracks'] as List).whereType<Map<String, dynamic>>(),
      if (data['downloads'] is List)
        ...(data['downloads'] as List).whereType<Map<String, dynamic>>(),
    ];

    Map<String, List<SongsTableData>>? lazyParentFilenameMap;
    Map<String, List<SongsTableData>>? lazyUniqueFilenameMap;
    List<({SongsTableData song, List<String> segments})>? lazySongSegments;

    List<({SongsTableData song, List<String> segments})> getSongSegments() {
      return lazySongSegments ??= allSongs.map((s) {
        return (song: s, segments: s.path.replaceAll(r'\\', '/').split('/'));
      }).toList();
    }

    SongsTableData? matchPath(String rawRef) {
      final parsedRef = _parseSongRef(rawRef);
      final ref = parsedRef.cueStartMs == null
          ? rawRef
          : _composeSongRef(parsedRef.path, parsedRef.cueStartMs);
      // 1. Exact or normalized path/chapter-ref match
      final direct = pathMap[ref] ?? pathMap[ref.toLowerCase()];
      if (direct != null) return direct;
      final path = parsedRef.path;

      // 2. Fallback for ytmusic:// paths matching by remoteId
      if (path.startsWith('ytmusic://')) {
        final videoId = path.replaceFirst('ytmusic://', '').split('?').first;
        final remoteMatch = remoteIdMap[videoId];
        if (remoteMatch != null) return remoteMatch;
      }

      final normPath = path.replaceAll(r'\\', '/').toLowerCase();
      final segments = normPath.split('/');

      // 3. Parent + Filename fallback (lazy init, keyed by (parent/filename, cueStartMs))
      if (segments.length >= 2) {
        if (lazyParentFilenameMap == null) {
          final map = <String, List<SongsTableData>>{};
          for (final item in getSongSegments()) {
            final segs = item.segments;
            if (segs.length >= 2) {
              final key =
                  '${segs[segs.length - 2].toLowerCase()}/${segs.last.toLowerCase()}';
              (map[key] ??= []).add(item.song);
            }
          }
          lazyParentFilenameMap = map;
        }
        final parentAndFilename =
            '${segments[segments.length - 2]}/${segments.last}';
        final candidates = lazyParentFilenameMap![parentAndFilename];
        if (candidates != null && candidates.isNotEmpty) {
          if (parsedRef.cueStartMs != null) {
            final targetCue = parsedRef.cueStartMs!;
            for (final song in candidates) {
              if (song.cueStartMs != null &&
                  (song.cueStartMs! - targetCue).abs() <= 500) {
                return song;
              }
            }
          } else {
            for (final song in candidates) {
              if (song.cueStartMs == null) {
                return song;
              }
            }
          }
        }
      }

      // 4. Unique filename fallback (lazy init, keyed by (filename, cueStartMs))
      final filename = segments.isNotEmpty ? segments.last : '';
      if (filename.isNotEmpty) {
        if (lazyUniqueFilenameMap == null) {
          final map = <String, List<SongsTableData>>{};
          for (final item in getSongSegments()) {
            final segs = item.segments;
            final fName = segs.isNotEmpty ? segs.last.toLowerCase() : '';
            if (fName.isNotEmpty) {
              (map[fName] ??= []).add(item.song);
            }
          }
          lazyUniqueFilenameMap = map;
        }
        final candidates = lazyUniqueFilenameMap![filename];
        if (candidates != null && candidates.isNotEmpty) {
          if (parsedRef.cueStartMs != null) {
            final targetCue = parsedRef.cueStartMs!;
            final matching = candidates
                .where((s) =>
                    s.cueStartMs != null &&
                    (s.cueStartMs! - targetCue).abs() <= 500)
                .toList();
            if (matching.length == 1) {
              return matching.first;
            }
          } else {
            final matching =
                candidates.where((s) => s.cueStartMs == null).toList();
            if (matching.length == 1) {
              return matching.first;
            }
          }
        }
      }
      return null;
    }

    final unmatchedPaths = <String>{};
    int restoredFavoritesCount = 0;
    int restoredPlaylistsCount = 0;
    int restoredHistoryCount = 0;
    int restoredExcludedCount = 0;
    int restoredDownloadsCount = 0;

    // Wrap ALL DB restore phases in one single database transaction
    await _db.transaction(() async {
      // 0. Seed online / YTM tracks
      if (onlineSeedList.isNotEmpty) {
        for (final meta in onlineSeedList) {
          final rawRemoteId = meta['remoteId'];
          final remoteId = rawRemoteId is String ? rawRemoteId.trim() : null;
          final rawPathVal = meta['path'];
          final rawPath = rawPathVal is String ? rawPathVal.trim() : '';
          final videoId = (remoteId != null && remoteId.isNotEmpty)
              ? remoteId
              : (rawPath.startsWith('ytmusic://')
                  ? rawPath.replaceFirst('ytmusic://', '').split('?').first
                  : '');
          if (videoId.isEmpty || remoteIdMap.containsKey(videoId)) continue;
          final ytPath = 'ytmusic://$videoId';
          if (pathMap.containsKey(ytPath)) continue;
          final rawTitle = meta['title'];
          final title = rawTitle is String ? rawTitle.trim() : null;
          final rawArtist = meta['artist'];
          final artist = rawArtist is String ? rawArtist.trim() : null;
          final rawAlbum = meta['album'];
          final album = rawAlbum is String ? rawAlbum.trim() : null;
          final rawArtworkUrl = meta['remoteArtworkUrl'];
          final artworkUrl =
              rawArtworkUrl is String ? rawArtworkUrl.trim() : null;
          final rawDurationMs = meta['durationMs'];
          final durationMs = rawDurationMs is num ? rawDurationMs.toInt() : 0;
          final insertedId = await _db.into(_db.songsTable).insert(
                SongsTableCompanion.insert(
                  title: (title != null && title.isNotEmpty)
                      ? title
                      : 'Unknown Track',
                  artist: Value((artist != null && artist.isNotEmpty)
                      ? artist
                      : 'Unknown Artist'),
                  album: album != null && album.isNotEmpty
                      ? Value(album)
                      : const Value.absent(),
                  durationMs: Value(durationMs),
                  path: ytPath,
                  source: const Value(SongSource.youtube),
                  remoteId: Value(videoId),
                  remoteArtworkUrl: Value(artworkUrl),
                ),
                mode: InsertMode.insertOrIgnore,
              );
          if (insertedId > 0) {
            final row = await (_db.select(_db.songsTable)
                  ..where((t) => t.id.equals(insertedId)))
                .getSingleOrNull();
            if (row != null) {
              allSongs.add(row);
              pathMap[row.path] = row;
              pathMap[row.path.toLowerCase()] = row;
              remoteIdMap[videoId] = row;
              lazySongSegments = null;
              lazyParentFilenameMap = null;
              lazyUniqueFilenameMap = null;
            }
          }
        }
      }

      // 1. Restore Favorites
      if (data['favorites'] != null && data['favorites'] is List) {
        final favList = (data['favorites'] as List)
            .whereType<String>()
            .where((p) => p.trim().isNotEmpty)
            .toList();
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
      }

      // 2. Restore Playlists
      if (data['playlists'] != null && data['playlists'] is List) {
        final playlistsList = data['playlists'] as List;
        final existingPlaylistsRes = await _repository.getPlaylists();
        final existingList = existingPlaylistsRes.fold(
            (l) => <PlaylistsTableData>[], (r) => r.toList());

        for (final item in playlistsList) {
          if (item is Map<String, dynamic> && item.containsKey('name')) {
            final rawName = item['name'];
            final name = rawName is String && rawName.trim().isNotEmpty
                ? rawName
                : 'Restored Playlist';
            final rawIsSmart = item['isSmart'];
            final isSmart = rawIsSmart is bool ? rawIsSmart : false;
            final rawCriteria = item['smartCriteria'];
            final smartCriteria = rawCriteria is String ? rawCriteria : null;
            final songPaths = (item['songPaths'] is List)
                ? (item['songPaths'] as List).whereType<String>().toList()
                : <String>[];

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
              if (playlistId != null) {
                final now = DateTime.now();
                existingList.add(PlaylistsTableData(
                  id: playlistId,
                  name: name,
                  createdAt: now,
                  updatedAt: now,
                  isSmart: isSmart,
                  smartCriteria: smartCriteria,
                ));
              }
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
          }
        }
      }

      // 3. Restore Play History
      if (data['playHistory'] != null && data['playHistory'] is List) {
        final historyList = data['playHistory'] as List;
        for (final item in historyList) {
          if (item is Map<String, dynamic>) {
            final rawPath = item['path'];
            final path = rawPath is String ? rawPath : null;
            final rawPlayCount = item['playCount'];
            final playCount = rawPlayCount is num ? rawPlayCount.toInt() : 0;
            final rawLastPlayed = item['lastPlayed'];
            final lastPlayed =
                rawLastPlayed is num ? rawLastPlayed.toInt() : null;

            if (path != null && path.isNotEmpty) {
              final matched = matchPath(path);
              if (matched != null) {
                final mergedCount = playCount > matched.playCount
                    ? playCount
                    : matched.playCount;
                final mergedLastPlayed =
                    (lastPlayed != null && matched.lastPlayed != null)
                        ? (lastPlayed > matched.lastPlayed!
                            ? lastPlayed
                            : matched.lastPlayed!)
                        : (lastPlayed ?? matched.lastPlayed);
                await (_db.update(_db.songsTable)
                      ..where((t) => t.id.equals(matched.id)))
                    .write(
                  SongsTableCompanion(
                    playCount: Value(mergedCount),
                    lastPlayed: Value(mergedLastPlayed),
                  ),
                );
                if (mergedLastPlayed != null && mergedLastPlayed > 0) {
                  final existingHist = await (_db.select(_db.playHistoryTable)
                        ..where((h) => h.songId.equals(matched.id))
                        ..limit(1))
                      .getSingleOrNull();
                  if (existingHist == null) {
                    await _db.into(_db.playHistoryTable).insert(
                          PlayHistoryTableCompanion.insert(
                            songId: matched.id,
                            playedAt: Value(
                              DateTime.fromMillisecondsSinceEpoch(
                                mergedLastPlayed < 10000000000
                                    ? mergedLastPlayed * 1000
                                    : mergedLastPlayed,
                              ),
                            ),
                          ),
                        );
                  }
                }
                restoredHistoryCount++;
              } else {
                unmatchedPaths.add(path);
              }
            }
          }
        }
      }

      // 4. Restore Excluded Folders
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

      // 5. Restore Downloads Metadata
      if (data['downloads'] != null && data['downloads'] is List) {
        final dlList = data['downloads'] as List;
        for (final item in dlList) {
          if (item is Map<String, dynamic>) {
            final rawPath = item['path'];
            final path = rawPath is String ? rawPath : null;
            final rawRemoteId = item['remoteId'];
            final remoteId = rawRemoteId is String ? rawRemoteId : null;
            final matched = matchPath(path ?? '') ??
                (remoteId != null ? remoteIdMap[remoteId] : null);
            if (matched != null && !matched.isDownloaded) {
              await (_db.update(_db.songsTable)
                    ..where((t) => t.id.equals(matched.id)))
                  .write(const SongsTableCompanion(isDownloaded: Value(true)));
              restoredDownloadsCount++;
            }
          }
        }
      }

      // 6. Restore saved queue (paths resolved against the fresh library).
      if (data['queue'] is Map<String, dynamic>) {
        final q = data['queue'] as Map<String, dynamic>;
        final paths = (q['paths'] is List)
            ? (q['paths'] as List).whereType<String>().toList()
            : <String>[];
        final rawIdx = q['currentIndex'];
        final idx = rawIdx is num ? rawIdx.toInt() : 0;
        final rawPosMs = q['positionMs'];
        final posMs = rawPosMs is num ? rawPosMs.toInt() : 0;
        if (paths.isNotEmpty) {
          final resolved = <({SongsTableData song, int originalIndex})>[];
          for (var i = 0; i < paths.length; i++) {
            final matched = matchPath(paths[i]);
            if (matched == null) {
              unmatchedPaths.add(paths[i]);
            } else {
              resolved.add((song: matched, originalIndex: i));
            }
          }
          if (resolved.isNotEmpty) {
            final currentOriginal = idx.clamp(0, paths.length - 1);
            var currentOrdinal =
                resolved.indexWhere((e) => e.originalIndex == currentOriginal);
            if (currentOrdinal == -1) currentOrdinal = 0;
            await _db.delete(_db.queueItemsTable).go();
            for (var order = 0; order < resolved.length; order++) {
              await _db.into(_db.queueItemsTable).insert(
                    QueueItemsTableCompanion.insert(
                      songId: resolved[order].song.id,
                      orderIndex: order,
                      isCurrent: Value(order == currentOrdinal),
                      positionMs: Value(order == currentOrdinal ? posMs : 0),
                    ),
                  );
            }
          }
        }
      }
    });

    // APPLY SharedPreferences writes ONLY after commit:
    int restoredSettingsCount = 0;
    if (data['settings'] is Map<String, dynamic>) {
      final settings = data['settings'] as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();

      if (settings.containsKey('gaplessPlayback')) {
        await prefs.setBool(
            'setting_gapless', settings['gaplessPlayback'] == true);
        restoredSettingsCount++;
      }
      if (settings.containsKey('crossfadeSeconds')) {
        final raw = settings['crossfadeSeconds'];
        final val = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '0') ?? 0.0;
        await prefs.setDouble('setting_crossfade', val);
        restoredSettingsCount++;
      }
      if (settings.containsKey('minDurationSec')) {
        final raw = settings['minDurationSec'];
        final val = raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '30') ?? 30;
        await prefs.setInt('setting_min_duration', val);
        restoredSettingsCount++;
      }
      if (settings.containsKey('dynamicThemingEnabled')) {
        await prefs.setBool(
            'setting_dynamic_theme', settings['dynamicThemingEnabled'] == true);
        restoredSettingsCount++;
      }
      if (settings['themeColorSource'] is String) {
        await prefs.setString('setting_theme_color_source',
            settings['themeColorSource'] as String);
        restoredSettingsCount++;
      }
      if (settings.containsKey('resumeAfterInterruption')) {
        await prefs.setBool('setting_resume_after_interruption',
            settings['resumeAfterInterruption'] == true);
        restoredSettingsCount++;
      }
      if (settings.containsKey('themeMode')) {
        final rawThemeMode = settings['themeMode'];
        await prefs.setString('setting_theme_mode',
            rawThemeMode is String ? rawThemeMode : 'dark');
        restoredSettingsCount++;
      }
      if (settings.containsKey('customAccentColorValue')) {
        final rawAccent = settings['customAccentColorValue'];
        await prefs.setInt('setting_custom_accent',
            rawAccent is num ? rawAccent.toInt() : 0xFF9B9EF5);
        restoredSettingsCount++;
      }
      if (settings.containsKey('playerSliderStyle')) {
        final rawSliderStyle = settings['playerSliderStyle'];
        await prefs.setString('setting_player_slider_style',
            rawSliderStyle is String ? rawSliderStyle : 'normal');
        restoredSettingsCount++;
      }
      if (settings.containsKey('appButtonStyle')) {
        final rawButtonStyle = settings['appButtonStyle'];
        await prefs.setString('setting_app_button_style',
            rawButtonStyle is String ? rawButtonStyle : 'rectangular');
        restoredSettingsCount++;
      }
      if (settings.containsKey('playerThemeMode')) {
        final rawPlayerTheme = settings['playerThemeMode'];
        final migratedTheme = PlayerThemeMode.fromName(
          rawPlayerTheme is String ? rawPlayerTheme : null,
        );
        await prefs.setString('setting_player_theme_mode', migratedTheme.name);
        restoredSettingsCount++;
      }
      if (settings.containsKey('visualizerStyle')) {
        final rawVisualizer = settings['visualizerStyle'];
        await prefs.setString('setting_visualizer_style',
            rawVisualizer is String ? rawVisualizer : 'bar');
        restoredSettingsCount++;
      }
      // Restore extended settings with validation
      if (settings['replayGainMode'] is String) {
        await prefs.setString(
            'setting_replay_gain_mode', settings['replayGainMode']);
        restoredSettingsCount++;
      }
      if (settings['replayGainPreampWithRg'] is num) {
        await prefs.setDouble('setting_replay_gain_preamp_with_rg',
            (settings['replayGainPreampWithRg'] as num).toDouble());
        restoredSettingsCount++;
      }
      if (settings['replayGainPreampWithoutRg'] is num) {
        await prefs.setDouble('setting_replay_gain_preamp_without_rg',
            (settings['replayGainPreampWithoutRg'] as num).toDouble());
        restoredSettingsCount++;
      }
      if (settings['wifiOnlyMode'] is bool) {
        await prefs.setBool('setting_wifi_only_mode', settings['wifiOnlyMode']);
        restoredSettingsCount++;
      }
      if (settings['offlineOnlyMode'] is bool) {
        await prefs.setBool(
            'setting_offline_only_mode', settings['offlineOnlyMode']);
        restoredSettingsCount++;
      }
      if (settings['bitPerfectMode'] is bool) {
        await prefs.setBool(
            PrefsKeys.bitPerfectOutput, settings['bitPerfectMode']);
        restoredSettingsCount++;
      }
      // Appearance & accessibility keys restored in the same pass, so a backup
      // is a complete snapshot rather than a partial one.
      if (settings['languageCode'] is String) {
        await prefs.setString(PrefsKeys.languageCode, settings['languageCode']);
        restoredSettingsCount++;
      }
      for (final entry in <String, String>{
        'highContrast': 'setting_high_contrast',
        'dimWhitePoint': 'setting_dim_white_point',
        'reduceMotion': 'setting_reduce_motion',
        'hapticsEnabled': PrefsKeys.hapticsEnabled,
        'customThemeGlow': 'setting_custom_theme_glow',
        'canvasEnabled': 'setting_canvas_enabled',
        'canvasAsBackdrop': 'setting_canvas_as_backdrop',
        'waveformSeekBar': 'setting_waveform_seek_bar',
        'autoThemeByTime': 'setting_auto_theme_by_time',
      }.entries) {
        final value = settings[entry.key];
        if (value is bool) {
          await prefs.setBool(entry.value, value);
          restoredSettingsCount++;
        }
      }
      for (final entry in <String, String>{
        'liquidGlassTint': PrefsKeys.liquidGlassTint,
        'customThemeRadius': 'setting_custom_theme_radius',
      }.entries) {
        final value = settings[entry.key];
        if (value is int) {
          await prefs.setInt(entry.value, value);
          restoredSettingsCount++;
        }
      }
      for (final entry in <String, String>{
        'headphoneSafety': PrefsKeys.headphoneSafetyEnabled,
        'soundFeedback': PrefsKeys.soundFeedbackEnabled,
      }.entries) {
        final value = settings[entry.key];
        if (value is bool) {
          await prefs.setBool(entry.value, value);
          restoredSettingsCount++;
        }
      }
      if (settings.containsKey('themeScheduleStart')) {
        final v = settings['themeScheduleStart'];
        if (v is int) {
          await prefs.setInt('setting_theme_schedule_start', v);
          restoredSettingsCount++;
        }
      }
      if (settings.containsKey('themeScheduleEnd')) {
        final v = settings['themeScheduleEnd'];
        if (v is int) {
          await prefs.setInt('setting_theme_schedule_end', v);
          restoredSettingsCount++;
        }
      }
      if (settings['audioDoseBudget'] is num) {
        await prefs.setDouble('audio_dose_budget',
            (settings['audioDoseBudget'] as num).toDouble());
        restoredSettingsCount++;
      }
      if (settings['dockStackMode'] is String) {
        await prefs.setString(
            PrefsKeys.dockStackMode, settings['dockStackMode']);
        restoredSettingsCount++;
      }
      if (settings['dspPreference'] is String) {
        await prefs.setString(
            'setting_dsp_preference', settings['dspPreference']);
        restoredSettingsCount++;
      }
      if (settings['streamingQuality'] is String) {
        await prefs.setString(
            'setting_streaming_quality', settings['streamingQuality']);
        restoredSettingsCount++;
      }
      if (settings['downloadQuality'] is String) {
        await prefs.setString(
            'setting_download_quality', settings['downloadQuality']);
        restoredSettingsCount++;
      }
      if (settings.containsKey('isLosslessMode')) {
        await prefs.setBool(
            'setting_lossless', settings['isLosslessMode'] == true);
        restoredSettingsCount++;
      }
      // EQ keys: restored through the live EqualizerManager keys so audio
      // applies the backup's EQ immediately without an app restart.
      if (settings.containsKey('eqEnabled')) {
        await prefs.setBool(
            PrefsKeys.eqEnabled, settings['eqEnabled'] == true);
        restoredSettingsCount++;
      }
      if (settings['eqGains'] is String) {
        await prefs.setString(PrefsKeys.eqGains, settings['eqGains']);
        restoredSettingsCount++;
      }
      if (settings['eqPreset'] is String) {
        await prefs.setString(PrefsKeys.eqPresetName, settings['eqPreset']);
        restoredSettingsCount++;
      }
      if (settings['eqPreamp'] is num) {
        await prefs.setDouble(
            PrefsKeys.eqPreamp, (settings['eqPreamp'] as num).toDouble());
        restoredSettingsCount++;
      }
      if (settings['eqBandCount'] is int) {
        await prefs.setInt(PrefsKeys.eqBandCount, settings['eqBandCount']);
        restoredSettingsCount++;
      }
      if (settings['eqCustomFrequencies'] is String) {
        await prefs.setString(
            PrefsKeys.eqCustomFrequencies, settings['eqCustomFrequencies']);
        restoredSettingsCount++;
      }
      if (settings['eqCustom32Frequencies'] is String) {
        await prefs.setString(PrefsKeys.eqCustom32Frequencies,
            settings['eqCustom32Frequencies']);
        restoredSettingsCount++;
      }
      if (settings['eqCustom64Frequencies'] is String) {
        await prefs.setString(PrefsKeys.eqCustom64Frequencies,
            settings['eqCustom64Frequencies']);
        restoredSettingsCount++;
      }
      if (settings['playbackSpeed'] is num) {
        await prefs.setDouble(
            'setting_playback_speed', (settings['playbackSpeed'] as num).toDouble());
        restoredSettingsCount++;
      }

      // Restore v5 announce_* and sysbeh_* settings from settings map
      for (final entry in settings.entries) {
        final k = entry.key;
        final v = entry.value;
        if (k.startsWith('announce_') || k.startsWith('sysbeh_')) {
          if (v is bool) {
            await prefs.setBool(k, v);
            restoredSettingsCount++;
          } else if (v is int) {
            await prefs.setInt(k, v);
            restoredSettingsCount++;
          } else if (v is double) {
            await prefs.setDouble(k, v);
            restoredSettingsCount++;
          } else if (v is String) {
            await prefs.setString(k, v);
            restoredSettingsCount++;
          } else if (v is List<String>) {
            await prefs.setStringList(k, v);
            restoredSettingsCount++;
          } else if (v is List) {
            await prefs.setStringList(k, v.map((e) => e.toString()).toList());
            restoredSettingsCount++;
          }
        }
      }
    }

    // Restore v5 keys from top-level data or settings map
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsMap = (data['settings'] is Map<String, dynamic>)
          ? data['settings'] as Map<String, dynamic>
          : const <String, dynamic>{};

      final usbQuirks = data['usb_quirks_v1'] ?? settingsMap['usb_quirks_v1'];
      if (usbQuirks is String && usbQuirks.trim().isNotEmpty) {
        try {
          jsonDecode(usbQuirks);
          await prefs.setString('usb_quirks_v1', usbQuirks);
          restoredSettingsCount++;
        } catch (_) {}
      }

      final audioProfDefault = data['audio_profile_default_id'] ??
          settingsMap['audio_profile_default_id'];
      if (audioProfDefault is String && audioProfDefault.isNotEmpty) {
        await prefs.setString('audio_profile_default_id', audioProfDefault);
        restoredSettingsCount++;
      }

      final remoteSources =
          data['remote_sources_v1'] ?? settingsMap['remote_sources_v1'];
      if (remoteSources is String && remoteSources.trim().isNotEmpty) {
        try {
          jsonDecode(remoteSources);
          await prefs.setString('remote_sources_v1', remoteSources);
          restoredSettingsCount++;
        } catch (_) {}
      }

      final assistantSuggestions = data['assistant_suggestions_enabled'] ??
          settingsMap['assistant_suggestions_enabled'];
      if (assistantSuggestions is bool) {
        await prefs.setBool(
            'assistant_suggestions_enabled', assistantSuggestions);
        restoredSettingsCount++;
      }

      final btLatency = data['setting_bt_latency_by_device'] ??
          settingsMap['setting_bt_latency_by_device'];
      if (btLatency is String && btLatency.trim().isNotEmpty) {
        try {
          jsonDecode(btLatency);
          await prefs.setString('setting_bt_latency_by_device', btLatency);
          restoredSettingsCount++;
        } catch (_) {}
      }

      final autoDeviceProfiles =
          data['setting_auto_device_profiles_enabled'] ??
              settingsMap['setting_auto_device_profiles_enabled'];
      if (autoDeviceProfiles is bool) {
        await prefs.setBool(
            'setting_auto_device_profiles_enabled', autoDeviceProfiles);
        restoredSettingsCount++;
      }

      for (final entry in data.entries) {
        final k = entry.key;
        final v = entry.value;
        if ((k.startsWith('announce_') || k.startsWith('sysbeh_')) &&
            !settingsMap.containsKey(k)) {
          if (v is bool) {
            await prefs.setBool(k, v);
            restoredSettingsCount++;
          } else if (v is int) {
            await prefs.setInt(k, v);
            restoredSettingsCount++;
          } else if (v is double) {
            await prefs.setDouble(k, v);
            restoredSettingsCount++;
          } else if (v is String) {
            await prefs.setString(k, v);
            restoredSettingsCount++;
          } else if (v is List<String>) {
            await prefs.setStringList(k, v);
            restoredSettingsCount++;
          } else if (v is List) {
            await prefs.setStringList(k, v.map((e) => e.toString()).toList());
            restoredSettingsCount++;
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed restoring v5 settings keys',
          error: e, stackTrace: st, category: 'Backup');
    }

    // 6. Restore Custom EQ Profiles
    int restoredEqProfilesCount = 0;
    final prefs = await SharedPreferences.getInstance();
    if (data['customEqProfiles'] != null) {
      try {
        final profilesData = data['customEqProfiles'];
        final serialized = jsonEncode(profilesData);
        await prefs.setString(PrefsKeys.customEqProfiles, serialized);
        restoredEqProfilesCount =
            (profilesData is List) ? profilesData.length : 1;
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
        await prefs.setString(
            'setting_automation_rules', jsonEncode(rulesList));
        restoredAutomationRulesCount = rulesList.length;
      } catch (e, st) {
        ErrorLogger.log('Failed restoring automation rules',
            error: e, stackTrace: st, category: 'Backup');
      }
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
        final base = (existing != null && existing.isNotEmpty)
            ? jsonDecode(existing)
            : {};
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
        if (v is String && v.trim().isNotEmpty) {
          try {
            jsonDecode(v);
            await prefs.setString(e.value, v);
          } catch (err, st) {
            ErrorLogger.log('Corrupted v2 blob for ${e.key}',
                error: err, stackTrace: st, category: 'Backup');
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed restoring v2 profile blobs',
          error: e, stackTrace: st, category: 'Backup');
    }

    // 11. Live store refresh: ratings/BPM/EQ/volume/bookmarks/DSP snapshots
    // are cached in memory by their stores, so without this a restore stayed
    // invisible until the next app launch.
    await _reloadLiveStoresAfterImport();

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

  /// Re-reads the stores that cache restored prefs maps in memory. Missing
  /// registrations (e.g. unit tests constructing the use case directly) are
  /// skipped; the handler owns BPM/bookmark/DSP snapshot instances.
  Future<void> _reloadLiveStoresAfterImport() async {
    await _reloadStore<SongRatingStore>((s) => s.reload());
    await _reloadStore<PerSongEqStore>((s) => s.reload());
    await _reloadStore<PerSongVolumeStore>((s) => s.reload());
    await _reloadStore<PulsrAudioHandler>((handler) async {
      await Future.wait<void>([
        handler.bpmOverrideStore.reload(),
        handler.bookmarkStore.reload(),
        handler.dspSnapshotStore.reload(),
      ]);
    });
  }

  Future<void> _reloadStore<T extends Object>(
      Future<void> Function(T store) action) async {
    try {
      if (!getIt.isRegistered<T>()) return;
      // `getIt<T>()` throws for an async singleton that is not ready yet;
      // skipping then is correct, the store's own load() will pick the
      // restored prefs up on construction.
      final store = getIt<T>();
      await action(store);
    } catch (e, st) {
      ErrorLogger.log('Failed to reload live store after backup import',
          error: e, stackTrace: st, category: 'Backup');
    }
  }

  // FIX-E02: Check unsupported future backup versions
  @visibleForTesting
  static void validateSchema(Map<String, dynamic> data) {
    final version = data['version'];
    if (version == null || version is! int || version < 1) {
      throw const FormatException(
          'Invalid backup version: missing or malformed version field');
    }
    if (version > 5) {
      throw FormatException(
          'Unsupported backup version: $version. Please update Pulsr.');
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

    if (data['customEqProfiles'] != null &&
        data['customEqProfiles'] is! List &&
        data['customEqProfiles'] is! Map) {
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
