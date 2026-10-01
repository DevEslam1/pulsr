// lib/data/audio/position_crash_guard.dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PositionCrashSnapshot {
  final int songId;
  final int queueIndex;
  final int positionMs;
  final List<int> queueIds;
  final int timestamp;

  const PositionCrashSnapshot({
    required this.songId,
    required this.queueIndex,
    required this.positionMs,
    required this.queueIds,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'queueIndex': queueIndex,
        'positionMs': positionMs,
        'queueIds': queueIds,
        'timestamp': timestamp,
      };

  factory PositionCrashSnapshot.fromJson(Map<String, dynamic> json) =>
      PositionCrashSnapshot(
        songId: (json['songId'] as num?)?.toInt() ?? 0,
        queueIndex: (json['queueIndex'] as num?)?.toInt() ?? 0,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        queueIds: (json['queueIds'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [],
        timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      );
}

/// Guards playback position across process death, OOM kills, and OS force-stop.
class PositionCrashGuard {
  static const String keyLastCleanShutdownTs = 'last_clean_shutdown_ts';

  static Future<File?> _getFile({bool tmp = false}) async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File(
          p.join(dir.path, tmp ? 'crash_guard.json.tmp' : 'crash_guard.json'));
    } catch (_) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        return File(p.join(
            docDir.path, tmp ? 'crash_guard.json.tmp' : 'crash_guard.json'));
      } catch (_) {
        return null;
      }
    }
  }

  /// Writes an atomic crash recovery snapshot. Writes to .tmp first then renames.
  static Future<void> writeSnapshot({
    required int songId,
    required int queueIndex,
    required int positionMs,
    required List<int> queueIds,
  }) async {
    try {
      final file = await _getFile();
      final tmpFile = await _getFile(tmp: true);
      if (file == null || tmpFile == null) return;

      final snapshot = PositionCrashSnapshot(
        songId: songId,
        queueIndex: queueIndex,
        positionMs: positionMs,
        queueIds: queueIds.take(50).toList(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final jsonStr = jsonEncode(snapshot.toJson());
      await tmpFile.writeAsString(jsonStr, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmpFile.rename(file.path);
    } catch (_) {}
  }

  /// Reads crash recovery snapshot if it exists.
  static Future<PositionCrashSnapshot?> readSnapshot() async {
    try {
      final file = await _getFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          return PositionCrashSnapshot.fromJson(json);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Deletes the crash guard file upon successful clean database persistence.
  static Future<void> clearSnapshot() async {
    try {
      final file = await _getFile();
      if (file != null && await file.exists()) {
        await file.delete();
      }
      final tmpFile = await _getFile(tmp: true);
      if (tmpFile != null && await tmpFile.exists()) {
        await tmpFile.delete();
      }
    } catch (_) {}
  }

  /// Alias for clearSnapshot.
  static Future<void> deleteSnapshot() => clearSnapshot();

  /// Records a clean shutdown timestamp in SharedPreferences.
  static Future<void> recordCleanShutdown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          keyLastCleanShutdownTs, DateTime.now().millisecondsSinceEpoch);
      await clearSnapshot();
    } catch (_) {}
  }

  /// Checks if an unclean shutdown occurred and if crash guard snapshot is newer than DB.
  static Future<bool> shouldPreferCrashGuard(int dbTimestampMs) async {
    try {
      final snapshot = await readSnapshot();
      if (snapshot == null) return false;

      // If snapshot is newer than DB last saved timestamp, prefer crash guard
      if (snapshot.timestamp > dbTimestampMs) {
        return true;
      }

      // Check last clean shutdown
      final prefs = await SharedPreferences.getInstance();
      final lastClean = prefs.getInt(keyLastCleanShutdownTs) ?? 0;
      if (snapshot.timestamp > lastClean) {
        return true;
      }
    } catch (_) {}
    return false;
  }
}
