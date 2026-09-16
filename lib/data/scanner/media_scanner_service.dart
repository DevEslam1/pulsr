// lib/data/scanner/media_scanner_service.dart
import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/audio_formats.dart';
import '../../core/constants/channels.dart';
import '../../core/di/injection.dart';
import '../../core/services/playlist_suggestions_service.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../db/app_database.dart';

class ScanError {
  final String path;
  final String message;
  final Object? error;

  const ScanError({
    required this.path,
    required this.message,
    this.error,
  });
}

@singleton
class MediaScannerService {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final IMusicRepository _repository;
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  final StreamController<ScanError> _errorController =
      StreamController<ScanError>.broadcast();

  Stream<double> get scanProgress => _progressController.stream;
  Stream<ScanError> get scanErrors => _errorController.stream;

  DateTime? _lastScanAt;
  int? _lastScanEpochSec;
  DateTime? get lastScanAt => _lastScanAt;
  int? get lastScanEpochSec => _lastScanEpochSec;

  /// True when a resume-triggered delta scan is worthwhile (default: 15 min
  /// since last successful scan). Used by app-resume hooks to avoid a full
  /// MediaStore query on every foreground.
  bool shouldRescanOnResume({Duration threshold = const Duration(minutes: 15)}) {
    final last = _lastScanAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= threshold;
  }

  void markScanComplete({int? epochSec}) {
    _lastScanAt = DateTime.now();
    _lastScanEpochSec = epochSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  MediaScannerService(this._repository);

  void dispose() {
    if (!_progressController.isClosed) _progressController.close();
    if (!_errorController.isClosed) _errorController.close();
  }

  Future<bool> checkPermission() async {
    if (Platform.isAndroid) {
      final audio = await Permission.audio.status;
      final storage = await Permission.storage.status;
      return audio.isGranted || audio.isLimited || storage.isGranted || storage.isLimited;
    } else if (Platform.isIOS) {
      final status = await Permission.mediaLibrary.status;
      return status.isGranted || status.isLimited;
    }
    return true;
  }

  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted || audioStatus.isLimited) return true;
      // On Android 13+ Permission.storage (READ_EXTERNAL_STORAGE, maxSdk 32)
      // is always denied — requesting it after audio denial only produces a
      // second instant-deny dialog. Only touch it when it can still succeed:
      // pre-13 devices on first run, or upgrades where it was already granted.
      final storageCurrent = await Permission.storage.status;
      if (storageCurrent.isGranted || storageCurrent.isLimited) return true;
      if (storageCurrent.isPermanentlyDenied) return false;
      if (audioStatus.isPermanentlyDenied) return false;
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted || storageStatus.isLimited;
    } else if (Platform.isIOS) {
      final status = await Permission.mediaLibrary.request();
      return status.isGranted || status.isLimited;
    }
    return true;
  }

  static const List<String> systemIgnoredPathPatterns = [
    // WhatsApp
    '/whatsapp/media/whatsapp voice notes/',
    '/whatsapp/media/whatsapp audio/',
    '/android/media/com.whatsapp/',
    '/com.whatsapp.w4b/',
    // Telegram
    '/telegram/telegram audio/',
    '/telegram/telegram voice/',
    '/android/media/org.telegram.messenger/',
    '/android/media/org.telegram.plus/',
    // Call & Voice recordings
    '/recordings/',
    '/callrecordings/',
    '/call_recordings/',
    '/voicerecorder/',
    '/voice_recorder/',
    '/soundrecorder/',
    '/sound_recorder/',
    '/audiorecorder/',
    '/audio_recorder/',
    '/miui/sound_recorder/',
    '/samsung/voicerecorder/',
    // System tones & cache
    '/ringtones/',
    '/notifications/',
    '/alarms/',
    '/.thumbnails/',
    '/.trash/',
    '/.cache/',
  ];

  static bool isSystemIgnoredPath(String filePath) {
    final lower = filePath.toLowerCase().replaceAll('\\', '/');
    for (final pattern in systemIgnoredPathPatterns) {
      if (lower.contains(pattern)) return true;
    }
    final fileName = lower.split('/').lastOrNull ?? '';
    if (fileName.startsWith('ptt-') ||
        (fileName.startsWith('aud-') && fileName.length > 20)) {
      if (lower.contains('whatsapp') || lower.contains('opus')) return true;
    }
    // Ignore only known system dot folders — user dot folders like .my_collection are now allowed
    final parts = lower.split('/');
    const knownSystemDotFolders = {'.thumbnails', '.trash', '.cache'};
    if (parts.any((p) => knownSystemDotFolders.contains(p))) {
      return true;
    }
    return false;
  }

  /// Returns true when any parent directory of [filePath] contains a
  /// `.nomedia` marker. Results are cached per directory; call
  /// [clearNomediaCache] after the user edits exclusions.
  static final Map<String, bool> _nomediaDirCache = {};
  static const int _nomediaCacheMax = 2000;

  static bool isInNomediaDirectory(String filePath) {
    try {
      final normalized = filePath.replaceAll('\\', '/');
      final idx = normalized.lastIndexOf('/');
      if (idx <= 0) return false;
      var dir = normalized.substring(0, idx);
      // Walk up a bounded number of levels (covers nested albums).
      for (var depth = 0; depth < 12; depth++) {
        final cached = _nomediaDirCache[dir];
        if (cached != null) {
          if (cached) return true;
        } else {
          var hasMarker = false;
          try {
            // dart:io is available here (scanner is Android-only path);
            // guard with File.existsSync inside try for isolate safety.
            // ignore: avoid_dynamic_calls
            hasMarker = _nomediaMarkerExists(dir);
          } catch (_) {
            hasMarker = false;
          }
          if (_nomediaDirCache.length >= _nomediaCacheMax) {
            _nomediaDirCache.clear();
          }
          _nomediaDirCache[dir] = hasMarker;
          if (hasMarker) return true;
        }
        final parent = dir.lastIndexOf('/');
        if (parent <= 0) break;
        dir = dir.substring(0, parent);
      }
    } catch (_) {}
    return false;
  }

  static bool _nomediaMarkerExists(String dir) {
    try {
      // Local import to keep web builds compiling (dart:io unavailable).
      // ignore: avoid_dynamic_calls
      final file = File('$dir/.nomedia');
      return file.existsSync();
    } catch (_) {
      return false;
    }
  }

  static void clearNomediaCache() => _nomediaDirCache.clear();

  Future<int> scanDeviceLibrary({
    bool ignoreShortFiles = true,
    int minDurationSec = 30,
    int minSizeKb = 0,
    bool autoHideSystemMedia = true,
    int? addedAfterEpochSec,
  }) async {
    _progressController.add(0.0);
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        final granted = await requestPermission();
        if (!granted) return 0;
      }

      _progressController.add(0.1);
      final excludedRes = await _repository.getExcludedFolderPaths();
      final excludedFolders = excludedRes.fold((l) => <String>[], (r) => r);

      // Query songs using on_audio_query
      List<SongModel> songs = [];
      try {
        songs = await _audioQuery.querySongs(
          sortType: SongSortType.DATE_ADDED,
          orderType: OrderType.DESC_OR_GREATER,
          uriType: UriType.EXTERNAL,
          ignoreCase: true,
        );
      } catch (e, stack) {
        ErrorLogger.log('on_audio_query querySongs failed',
            error: e, stackTrace: stack, category: 'scanner');
        return 0;
      }

      // Query genres mapping from MediaStore to populate genre names
      final Map<int, String> songGenres = {};
      try {
        final genres = await _audioQuery.queryGenres();
        for (final g in genres) {
          final genreName = g.genre.trim();
          if (genreName.isEmpty || genreName.toLowerCase() == '<unknown>') continue;
          try {
            final audios = await _audioQuery.queryAudiosFrom(
              AudiosFromType.GENRE_ID,
              g.id,
            );
            for (final a in audios) {
              songGenres[a.id] = genreName;
            }
          } catch (_) {}
        }
      } catch (e) {
        ErrorLogger.log('queryGenres failed', error: e, category: 'scanner');
      }

      final minDurationMs = ignoreShortFiles ? minDurationSec * 1000 : 0;
      ErrorLogger.addBreadcrumb(
          'Scanner started with ${songs.length} raw MediaStore songs',
          category: 'scanner');

      _progressController.add(0.3);

      // Offload CPU-heavy metadata parsing and aggregation to background isolate
      final parseInput = _ScanMediaInput(
        rawSongs: songs.map((s) => s.getMap).toList(),
        songGenres: songGenres,
        excludedFolders: excludedFolders,
        minDurationMs: minDurationMs,
        minSizeBytes: minSizeKb * 1024,
        autoHideSystemMedia: autoHideSystemMedia,
        pathSeparator: Platform.pathSeparator,
      );

      final parseResult =
          await compute(_parseScannedMediaInIsolate, parseInput);
      _progressController.add(0.7);

      await _repository.syncScannedMusic(
        songs: parseResult.songs,
        albums: parseResult.albums,
        artists: parseResult.artists,
      );

      _progressController.add(0.9);

      // Clean up orphaned entries
      await _repository.cleanupOrphanedSongs(parseResult.validSongIds);

      // Expand sibling CUE sheets into virtual per-track rows. Runs after
      // cleanup so it only touches live files and is idempotent on rescans.
      await _repository.expandCueSheets();
      _progressController.add(1.0);

      // A completed scan changes the library, so drop any cached
      // "Suggested for you" mixes generated from the previous snapshot.
      try {
        if (getIt.isRegistered<PlaylistSuggestionsService>()) {
          getIt<PlaylistSuggestionsService>().invalidateCache();
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to invalidate playlist suggestions',
            error: e, stackTrace: st, category: 'scanner');
      }

      ErrorLogger.addBreadcrumb(
          'Scanner completed: ${parseResult.songs.length} valid songs indexed'
          '${parseResult.nativeDecoderRequiredCount > 0 ? ', ${parseResult.nativeDecoderRequiredCount} file(s) need a native decoder (not indexed)' : ''}',
          category: 'scanner');

      // addedAfterEpochSec is advisory: DATE_ADDED filtering is applied by
      // callers doing delta scans; record completion for resume heuristics.
      markScanComplete();
      return parseResult.songs.length;
    } catch (e, st) {
      ErrorLogger.log('Media scanner failed',
          error: e, stackTrace: st, category: 'scanner');
      rethrow;
    }
  }

  Future<void> rescanSingleFile(String path) async {
    const channel = MethodChannel(PulsrChannels.tagEditor);
    try {
      final Map<dynamic, dynamic>? tags =
          await channel.invokeMapMethod<dynamic, dynamic>('readTags', {
        'path': path,
        'includeArtwork': false,
      });
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
          artist:
              (artist != null && artist.isNotEmpty) ? artist : 'Unknown Artist',
          album: (album != null && album.isNotEmpty) ? album : 'Unknown Album',
          genre: genre,
          year: year,
          trackNumber: trackNumber,
        );
      }
    } catch (e, stack) {
      _errorController.add(ScanError(
        path: path,
        message: 'Failed to rescan single file metadata',
        error: e,
      ));
      ErrorLogger.log(
        'Failed to rescan single file metadata: $path',
        error: e,
        stackTrace: stack,
        category: 'MediaScanner',
      );
    }
  }

  /// Reads the real audio-header fields for a local song via the tag channel
  /// and persists them, so the quality badge reflects actual metadata. Runs
  /// once per song: callers should skip songs that already have [codec] set.
  ///
  /// Must run on the main isolate (uses a platform channel); the bulk scan runs
  /// in a background isolate and therefore cannot do this inline.
  Future<void> enrichAudioQuality(int songId, String path) async {
    if (!Platform.isAndroid) return;
    if (path.isEmpty ||
        path.startsWith('http') ||
        path.startsWith('ytmusic://')) {
      return;
    }
    const channel = MethodChannel(PulsrChannels.tagEditor);
    try {
      final Map<dynamic, dynamic>? tags =
          await channel.invokeMapMethod<dynamic, dynamic>('readTags', {
        'path': path,
        'includeArtwork': false,
      });
      if (tags == null) return;

      final sampleRate = _asInt(tags['sampleRate']);
      final bitDepth = _asInt(tags['bitsPerSample']);
      // Header bitRate is in kbps for lossy, bps-ish for some lossless; jaudiotagger reports kbps here.
      final bitrateKbps = _asInt(tags['bitRate']);
      final codec = (tags['format'] as String?)?.trim();
      final lraVal = (tags['loudnessRange'] as num?)?.toDouble();

      await _repository.updateAudioQuality(
        songId: songId,
        sampleRate: sampleRate != null && sampleRate > 0 ? sampleRate : null,
        bitDepth: bitDepth != null && bitDepth > 0 ? bitDepth : null,
        bitrateKbps:
            bitrateKbps != null && bitrateKbps > 0 ? bitrateKbps : null,
        codec: (codec != null && codec.isNotEmpty) ? codec : null,
        loudnessRange: lraVal,
      );
    } catch (e, stack) {
      _errorController.add(ScanError(
        path: path,
        message: 'Failed to enrich audio quality',
        error: e,
      ));
      ErrorLogger.log(
        'Failed to enrich audio quality: $path',
        error: e,
        stackTrace: stack,
        category: 'MediaScanner',
      );
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class _ScanMediaInput {
  final List<Map<dynamic, dynamic>> rawSongs;
  final Map<int, String> songGenres;
  final List<String> excludedFolders;
  final int minDurationMs;
  final int minSizeBytes;
  final bool autoHideSystemMedia;
  final String pathSeparator;

  _ScanMediaInput({
    required this.rawSongs,
    this.songGenres = const {},
    required this.excludedFolders,
    required this.minDurationMs,
    this.minSizeBytes = 0,
    required this.autoHideSystemMedia,
    required this.pathSeparator,
  });
}

class _ScanMediaResult {
  final List<SongsTableCompanion> songs;
  final List<AlbumsTableCompanion> albums;
  final List<ArtistsTableCompanion> artists;
  final Set<int> validSongIds;
  final int nativeDecoderRequiredCount;

  _ScanMediaResult({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.validSongIds,
    this.nativeDecoderRequiredCount = 0,
  });
}

_ScanMediaResult _parseScannedMediaInIsolate(_ScanMediaInput input) {
  final List<SongsTableCompanion> songCompanions = [];
  final Map<int, AlbumsTableCompanion> albumMap = {};
  final Map<int, ArtistsTableCompanion> artistMap = {};
  final Map<int, int> albumSongCounts = {};
  final Map<int, int> artistSongCounts = {};
  final Set<int> validSongIds = {};
  int nativeDecoderRequiredCount = 0;

  int? parseInt(Object? val) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    return int.tryParse(val?.toString() ?? '');
  }

  String? parseString(Object? val) {
    if (val == null) return null;
    final str = val.toString().trim();
    return str.isNotEmpty ? str : null;
  }

  for (final raw in input.rawSongs) {
    final id = parseInt(raw['_id']) ?? parseInt(raw['id']) ?? 0;
    if (id <= 0 || validSongIds.contains(id)) continue;

    final duration = parseInt(raw['duration']) ?? 0;
    if (duration < input.minDurationMs) continue;

    final fileSize = parseInt(raw['_size']) ?? parseInt(raw['size']) ?? 0;
    if (input.minSizeBytes > 0 && fileSize < input.minSizeBytes) continue;

    final path = parseString(raw['_data']) ?? parseString(raw['data']) ?? '';
    if (path.isEmpty) {
      continue;
    }
    if (!AudioFormats.isSupportedExtension(path)) {
      // Recognized native-tier formats are counted for an honest diagnostics
      // surface but never indexed as playable songs.
      if (AudioFormats.requiresNativeDecoder(path)) {
        nativeDecoderRequiredCount++;
      }
      continue;
    }

    // Auto-hide system media / messenger voice notes
    if (input.autoHideSystemMedia &&
        MediaScannerService.isSystemIgnoredPath(path)) {
      continue;
    }

    // Honor .nomedia markers: MediaStore usually excludes these, but
    // direct file scans and some OEM ROMs leak them through.
    if (MediaScannerService.isInNomediaDirectory(path)) {
      continue;
    }

    // Skip if within a user-excluded folder (case-insensitive, normalized)
    if (input.excludedFolders.any((folder) {
      final sep = input.pathSeparator;
      final normPath = path.toLowerCase();
      final normFolder = folder.toLowerCase();
      final prefix =
          normFolder.endsWith(sep) ? normFolder : '$normFolder$sep';
      return normPath.startsWith(prefix) || normPath == normFolder;
    })) {
      continue;
    }

    final rawTitle = parseString(raw['title']);
    final title =
        (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : 'Unknown Song';

    final rawArtist = parseString(raw['artist']);
    final artist =
        (rawArtist != null && rawArtist.isNotEmpty && rawArtist != '<unknown>')
            ? rawArtist
            : 'Unknown Artist';

    final rawAlbum = parseString(raw['album']);
    final album =
        (rawAlbum != null && rawAlbum.isNotEmpty && rawAlbum != '<unknown>')
            ? rawAlbum
            : 'Unknown Album';

    final rawGenre = input.songGenres[id] ?? parseString(raw['genre']);
    final genre =
        (rawGenre != null && rawGenre.isNotEmpty && rawGenre != '<unknown>')
            ? rawGenre
            : null;

    final int? year = parseInt(raw['year']);
    final artistId = parseInt(raw['artist_id']) ?? parseInt(raw['artistId']);
    final albumId = parseInt(raw['album_id']) ?? parseInt(raw['albumId']);
    final uri = parseString(raw['_uri']) ?? parseString(raw['uri']);
    final track = parseInt(raw['track']);
    final dateAdded = parseInt(raw['date_added']) ?? parseInt(raw['dateAdded']);
    final size = parseInt(raw['_size']) ?? parseInt(raw['size']);

    validSongIds.add(id);

    songCompanions.add(
      SongsTableCompanion(
        id: Value(id),
        title: Value(title),
        artist: Value(artist),
        artistId: Value(artistId),
        album: Value(album),
        albumId: Value(albumId),
        durationMs: Value(duration),
        path: Value(path),
        uri: Value(uri),
        trackNumber: Value(track),
        dateAdded: Value(dateAdded),
        fileSize: Value(size),
        artworkUri: Value(id.toString()),
        genre: Value(genre),
        year: Value(year),
      ),
    );

    // Aggregate Albums
    if (albumId != null) {
      albumSongCounts[albumId] = (albumSongCounts[albumId] ?? 0) + 1;
      if (!albumMap.containsKey(albumId)) {
        albumMap[albumId] = AlbumsTableCompanion(
          id: Value(albumId),
          title: Value(album),
          artist: Value(artist),
          artistId: Value(artistId),
          artworkUri: Value(albumId.toString()),
        );
      }
    }

    // Aggregate Artists
    if (artistId != null) {
      artistSongCounts[artistId] = (artistSongCounts[artistId] ?? 0) + 1;
      if (!artistMap.containsKey(artistId)) {
        artistMap[artistId] = ArtistsTableCompanion(
          id: Value(artistId),
          name: Value(artist),
          artworkUri: Value(artistId.toString()),
        );
      }
    }
  }

  final finalAlbums = albumMap.entries.map((e) {
    return e.value.copyWith(songCount: Value(albumSongCounts[e.key] ?? 1));
  }).toList();

  final finalArtists = artistMap.entries.map((e) {
    return e.value.copyWith(songCount: Value(artistSongCounts[e.key] ?? 1));
  }).toList();

  return _ScanMediaResult(
    songs: songCompanions,
    albums: finalAlbums,
    artists: finalArtists,
    validSongIds: validSongIds,
    nativeDecoderRequiredCount: nativeDecoderRequiredCount,
  );
}
