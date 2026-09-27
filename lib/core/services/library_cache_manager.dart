import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../data/db/app_database.dart';
import '../utils/error_logger.dart';

class LibrarySnapshot {
  final List<SongsTableData> songs;
  final int totalSongCount;
  final int albumCount;
  final int artistCount;
  final DateTime timestamp;

  const LibrarySnapshot({
    required this.songs,
    required this.totalSongCount,
    required this.albumCount,
    required this.artistCount,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'songs': songs.map((s) => s.toJson()).toList(),
        'totalSongCount': totalSongCount,
        'albumCount': albumCount,
        'artistCount': artistCount,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LibrarySnapshot.fromJson(Map<String, dynamic> json) {
    final rawSongs = json['songs'] as List<dynamic>? ?? [];
    final songs = rawSongs
        .whereType<Map<String, dynamic>>()
        .map((s) => SongsTableData.fromJson(s))
        .toList();
    return LibrarySnapshot(
      songs: songs,
      totalSongCount: json['totalSongCount'] as int? ?? songs.length,
      albumCount: json['albumCount'] as int? ?? 0,
      artistCount: json['artistCount'] as int? ?? 0,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

@singleton
class LibraryCacheManager {
  static final LibraryCacheManager _instance =
      LibraryCacheManager._internal();
  factory LibraryCacheManager() => _instance;
  LibraryCacheManager._internal();

  File? _snapshotFile;
  LibrarySnapshot? _inMemorySnapshot;
  Timer? _saveDebounceTimer;

  Future<void> _initFile() async {
    if (_snapshotFile != null) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      _snapshotFile = File(p.join(docDir.path, 'library_snapshot_v1.json'));
    } catch (e, st) {
      ErrorLogger.log('Failed to locate library snapshot file',
          error: e, stackTrace: st, category: 'LibraryCache');
    }
  }

  /// Returns the latest library snapshot to render the library immediately
  /// on cold start before SQLite queries complete.
  Future<LibrarySnapshot?> loadSnapshot() async {
    if (_inMemorySnapshot != null) return _inMemorySnapshot;
    try {
      await _initFile();
      if (_snapshotFile != null && await _snapshotFile!.exists()) {
        final content = await _snapshotFile!.readAsString();
        if (content.isNotEmpty) {
          final decoded = json.decode(content) as Map<String, dynamic>;
          _inMemorySnapshot = LibrarySnapshot.fromJson(decoded);
          return _inMemorySnapshot;
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to load library snapshot',
          error: e, stackTrace: st, category: 'LibraryCache');
    }
    return null;
  }

  /// Debounced asynchronous persistence of the library snapshot.
  void saveSnapshot({
    required List<SongsTableData> songs,
    int? totalSongCount,
    int? albumCount,
    int? artistCount,
  }) {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        await _initFile();
        if (_snapshotFile == null) return;
        // Bounded to 200 songs for instant cold start
        final boundedSongs = songs.take(200).toList();
        final snapshot = LibrarySnapshot(
          songs: boundedSongs,
          totalSongCount: totalSongCount ?? songs.length,
          albumCount: albumCount ?? 0,
          artistCount: artistCount ?? 0,
          timestamp: DateTime.now(),
        );
        _inMemorySnapshot = snapshot;
        final raw = json.encode(snapshot.toJson());
        await _snapshotFile!.writeAsString(raw, flush: false);
      } catch (e, st) {
        ErrorLogger.log('Failed to save library snapshot',
            error: e, stackTrace: st, category: 'LibraryCache');
      }
    });
  }

  /// Clears the library snapshot (e.g. on library reset / full rescan).
  Future<void> clearSnapshot() async {
    _inMemorySnapshot = null;
    try {
      await _initFile();
      if (_snapshotFile != null && await _snapshotFile!.exists()) {
        await _snapshotFile!.delete();
      }
    } catch (_) {}
  }
}
