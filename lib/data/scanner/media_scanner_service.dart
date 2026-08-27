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
import '../../core/utils/error_logger.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../db/app_database.dart';

@singleton
class MediaScannerService {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final IMusicRepository _repository;
  final StreamController<double> _progressController = StreamController<double>.broadcast();

  Stream<double> get scanProgress => _progressController.stream;

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
      if (!audioStatus.isPermanentlyDenied) {
        final storageStatus = await Permission.storage.request();
        return storageStatus.isGranted;
      }
      return false;
    } else if (Platform.isIOS) {
      final status = await Permission.mediaLibrary.request();
      return status.isGranted;
    }
    return true;
  }

  static const List<String> systemIgnoredPathPatterns = [
    // WhatsApp
    '/whatsapp/media/whatsapp voice notes',
    '/whatsapp/media/whatsapp audio',
    '/android/media/com.whatsapp',
    '/com.whatsapp.w4b',
    // Telegram
    '/telegram/telegram audio',
    '/telegram/telegram voice',
    '/android/media/org.telegram.messenger',
    '/android/media/org.telegram.plus',
    // Call & Voice recordings
    '/recordings',
    '/callrecordings',
    '/call_recordings',
    '/voicerecorder',
    '/voice_recorder',
    '/soundrecorder',
    '/sound_recorder',
    '/audiorecorder',
    '/audio_recorder',
    '/miui/sound_recorder',
    '/samsung/voicerecorder',
    // System tones & cache
    '/ringtones',
    '/notifications',
    '/alarms',
    '/.thumbnails',
    '/.trash',
    '/.cache',
  ];

  static bool isSystemIgnoredPath(String filePath) {
    final lower = filePath.toLowerCase().replaceAll('\\', '/');
    for (final pattern in systemIgnoredPathPatterns) {
      if (lower.contains(pattern)) return true;
    }
    final fileName = lower.split('/').lastOrNull ?? '';
    if (fileName.startsWith('ptt-') || (fileName.startsWith('aud-') && fileName.length > 20)) {
      if (lower.contains('whatsapp') || lower.contains('opus')) return true;
    }
    // Ignore hidden dot folders (.thumbnails, .private, etc.)
    final parts = lower.split('/');
    if (parts.any((p) => p.startsWith('.') && p != '.' && p != '..')) {
      return true;
    }
    return false;
  }

  Future<int> scanDeviceLibrary({
    bool ignoreShortFiles = true,
    int minDurationSec = 30,
    bool autoHideSystemMedia = true,
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
        ErrorLogger.log('on_audio_query querySongs failed', error: e, stackTrace: stack, category: 'scanner');
        return 0;
      }

      final minDurationMs = ignoreShortFiles ? minDurationSec * 1000 : 0;
      ErrorLogger.addBreadcrumb('Scanner started with ${songs.length} raw MediaStore songs', category: 'scanner');

      _progressController.add(0.3);

      // Offload CPU-heavy metadata parsing and aggregation to background isolate
      final parseInput = _ScanMediaInput(
        rawSongs: songs.map((s) => s.getMap).toList(),
        excludedFolders: excludedFolders,
        minDurationMs: minDurationMs,
        autoHideSystemMedia: autoHideSystemMedia,
        pathSeparator: Platform.pathSeparator,
      );

      final parseResult = await compute(_parseScannedMediaInIsolate, parseInput);
      _progressController.add(0.7);

      await _repository.syncScannedMusic(
        songs: parseResult.songs,
        albums: parseResult.albums,
        artists: parseResult.artists,
      );

      _progressController.add(0.9);

      // Clean up orphaned entries
      await _repository.cleanupOrphanedSongs(parseResult.validSongIds);
      _progressController.add(1.0);

      ErrorLogger.addBreadcrumb('Scanner completed: ${parseResult.songs.length} valid songs indexed', category: 'scanner');

      return parseResult.songs.length;
    } catch (e, st) {
      ErrorLogger.log('Media scanner failed', error: e, stackTrace: st, category: 'scanner');
      rethrow;
    }
  }

  Future<void> rescanSingleFile(String path) async {
    const channel = MethodChannel('com.pulsr.music/tag_editor');
    try {
      final Map<dynamic, dynamic>? tags = await channel.invokeMapMethod<dynamic, dynamic>('readTags', {
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
          artist: (artist != null && artist.isNotEmpty) ? artist : 'Unknown Artist',
          album: (album != null && album.isNotEmpty) ? album : 'Unknown Album',
          genre: genre,
          year: year,
          trackNumber: trackNumber,
        );
      }
    } catch (e, stack) {
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
    if (path.isEmpty || path.startsWith('http') || path.startsWith('ytmusic://')) {
      return;
    }
    const channel = MethodChannel('com.pulsr.music/tag_editor');
    try {
      final Map<dynamic, dynamic>? tags = await channel.invokeMapMethod<dynamic, dynamic>('readTags', {
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
        bitrateKbps: bitrateKbps != null && bitrateKbps > 0 ? bitrateKbps : null,
        codec: (codec != null && codec.isNotEmpty) ? codec : null,
        loudnessRange: lraVal,
      );
    } catch (e, stack) {
      ErrorLogger.log(
        'Failed to enrich audio quality: $path',
        error: e,
        stackTrace: stack,
        category: 'MediaScanner',
      );
    }
  }

  /// Batch enriches audio quality for multiple songs, processing in batches of 10 concurrently.
  Future<void> enrichAudioQualityBatch(
    List<SongsTableData> songs, {
    void Function(int processed, int total)? onProgress,
  }) async {
    if (!Platform.isAndroid || songs.isEmpty) return;

    final eligible = songs.where((s) =>
      s.codec == null &&
      s.path.isNotEmpty &&
      !s.path.startsWith('http') &&
      !s.path.startsWith('ytmusic://')
    ).toList();

    final total = eligible.length;
    int processed = 0;

    for (int i = 0; i < eligible.length; i += 10) {
      final batch = eligible.sublist(i, (i + 10).clamp(0, eligible.length));
      await Future.wait(batch.map((song) => enrichAudioQuality(song.id, song.path)));
      processed += batch.length;
      onProgress?.call(processed, total);
    }
  }

  /// Computes inter-sample peak using 4x oversampling interpolation.
  /// Standard PCM sample peak misses peaks occurring between samples during DAC reconstruction.
  static double computeTruePeak(List<int> samples, {int bitDepth = 16}) {
    if (samples.isEmpty) return 0.0;
    final maxInt = (1 << (bitDepth - 1)).toDouble();
    double maxTruePeak = 0.0;

    for (int i = 0; i < samples.length - 1; i++) {
      final s0 = (i > 0 ? samples[i - 1] : samples[i]) / maxInt;
      final s1 = samples[i] / maxInt;
      final s2 = samples[i + 1] / maxInt;
      final s3 = (i + 2 < samples.length ? samples[i + 2] : samples[i + 1]) / maxInt;

      // 4-point cubic Hermite interpolation for 4x oversampling
      for (double t = 0.0; t < 1.0; t += 0.25) {
        final t2 = t * t;
        final t3 = t2 * t;
        final val = 0.5 * (
          (2.0 * s1) +
          (-s0 + s2) * t +
          (2.0 * s0 - 5.0 * s1 + 4.0 * s2 - s3) * t2 +
          (-s0 + 3.0 * s1 - 3.0 * s2 + s3) * t3
        );
        final absVal = val.abs();
        if (absVal > maxTruePeak) {
          maxTruePeak = absVal;
        }
      }
    }
    return maxTruePeak;
  }

  /// Computes EBU R128 Loudness Range (LRA in LU) from short-term loudness blocks.
  /// LRA measures the variation of loudness over time (10th to 95th percentile difference).
  static double computeLoudnessRange(List<double> shortTermLufs) {
    if (shortTermLufs.length < 5) return 0.0;

    // Filter out silence/gating below -70 LUFS
    final validLufs = shortTermLufs.where((l) => l > -70.0).toList();
    if (validLufs.isEmpty) return 0.0;

    validLufs.sort();
    final p10Idx = (validLufs.length * 0.10).floor().clamp(0, validLufs.length - 1);
    final p95Idx = (validLufs.length * 0.95).floor().clamp(0, validLufs.length - 1);

    final lra = validLufs[p95Idx] - validLufs[p10Idx];
    return lra.clamp(0.0, 30.0);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class _ScanMediaInput {
  final List<Map<dynamic, dynamic>> rawSongs;
  final List<String> excludedFolders;
  final int minDurationMs;
  final bool autoHideSystemMedia;
  final String pathSeparator;

  _ScanMediaInput({
    required this.rawSongs,
    required this.excludedFolders,
    required this.minDurationMs,
    required this.autoHideSystemMedia,
    required this.pathSeparator,
  });
}

class _ScanMediaResult {
  final List<SongsTableCompanion> songs;
  final List<AlbumsTableCompanion> albums;
  final List<ArtistsTableCompanion> artists;
  final Set<int> validSongIds;

  _ScanMediaResult({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.validSongIds,
  });
}

_ScanMediaResult _parseScannedMediaInIsolate(_ScanMediaInput input) {
  final List<SongsTableCompanion> songCompanions = [];
  final Map<int, AlbumsTableCompanion> albumMap = {};
  final Map<int, ArtistsTableCompanion> artistMap = {};
  final Set<int> validSongIds = {};

  for (final raw in input.rawSongs) {
    final id = raw['_id'] as int? ?? raw['id'] as int? ?? 0;
    final duration = raw['duration'] as int? ?? 0;
    if (duration < input.minDurationMs) continue;

    final path = (raw['_data'] as String?) ?? (raw['data'] as String?) ?? '';
    if (path.isEmpty || !AudioFormats.isSupportedExtension(path)) {
      continue;
    }

    // Auto-hide system media / messenger voice notes
    if (input.autoHideSystemMedia && MediaScannerService.isSystemIgnoredPath(path)) {
      continue;
    }

    // Skip if within a user-excluded folder
    if (input.excludedFolders.any((folder) {
      final prefix = folder.endsWith(input.pathSeparator) ? folder : '$folder${input.pathSeparator}';
      return path.startsWith(prefix) || path == folder;
    })) {
      continue;
    }

    final rawTitle = raw['title'] as String?;
    final title = (rawTitle != null && rawTitle.trim().isNotEmpty) ? rawTitle.trim() : 'Unknown Song';

    final rawArtist = raw['artist'] as String?;
    final artist = (rawArtist != null && rawArtist.trim().isNotEmpty && rawArtist != '<unknown>')
        ? rawArtist.trim()
        : 'Unknown Artist';

    final rawAlbum = raw['album'] as String?;
    final album = (rawAlbum != null && rawAlbum.trim().isNotEmpty && rawAlbum != '<unknown>')
        ? rawAlbum.trim()
        : 'Unknown Album';

    final rawGenre = raw['genre']?.toString();
    final genre = (rawGenre != null && rawGenre.trim().isNotEmpty && rawGenre != '<unknown>')
        ? rawGenre.trim()
        : null;

    final yearRaw = raw['year'];
    final int? year = yearRaw is int ? yearRaw : int.tryParse(yearRaw?.toString() ?? '');

    final artistId = raw['artist_id'] as int? ?? raw['artistId'] as int?;
    final albumId = raw['album_id'] as int? ?? raw['albumId'] as int?;
    final uri = raw['_uri'] as String? ?? raw['uri'] as String?;
    final track = raw['track'] as int?;
    final dateAdded = raw['date_added'] as int? ?? raw['dateAdded'] as int?;
    final size = raw['_size'] as int? ?? raw['size'] as int?;

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
      albumMap[albumId] = AlbumsTableCompanion(
        id: Value(albumId),
        title: Value(album),
        artist: Value(artist),
        artistId: Value(artistId),
        songCount: Value((albumMap[albumId]?.songCount.value ?? 0) + 1),
        artworkUri: Value(albumId.toString()),
      );
    }

    // Aggregate Artists
    if (artistId != null) {
      artistMap[artistId] = ArtistsTableCompanion(
        id: Value(artistId),
        name: Value(artist),
        songCount: Value((artistMap[artistId]?.songCount.value ?? 0) + 1),
        artworkUri: Value(artistId.toString()),
      );
    }
  }

  return _ScanMediaResult(
    songs: songCompanions,
    albums: albumMap.values.toList(),
    artists: artistMap.values.toList(),
    validSongIds: validSongIds,
  );
}


