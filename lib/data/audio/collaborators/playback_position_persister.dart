// lib/data/audio/collaborators/playback_position_persister.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/error_logger.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../position_crash_guard.dart';

/// Immutable point-in-time view of playback position and queue state captured
/// right before persisting to disk and the repository.
class PlaybackPositionSnapshot {
  const PlaybackPositionSnapshot({
    required this.songId,
    required this.queueIndex,
    required this.positionMs,
    required this.queueIds,
    required this.isIdle,
    required this.queueDirty,
    required this.savedQueueIndex,
  });

  final int songId;
  final int queueIndex;
  final int positionMs;
  final List<int> queueIds;
  final bool isIdle;
  final bool queueDirty;
  final int savedQueueIndex;
}

/// Serialized, crash-safe persistence for the active track position and queue.
///
/// Coalesces concurrent triggers (periodic 2s ticks, lifecycle backgrounding,
/// and pause/seek events) so repository and recovery-file writes never overlap
/// or commit out of order.
class PlaybackPositionPersister {
  PlaybackPositionPersister({
    required IMusicRepository repository,
    required PlaybackPositionSnapshot? Function() readSnapshot,
    required int Function() readCurrentPositionMs,
    required bool Function() isDisposed,
    required VoidCallback clearDirty,
    required VoidCallback markDirty,
    required void Function(int savedQueueIndex) onQueueSaved,
    Future<Directory?> Function()? getDocumentsDirectory,
    Future<void> Function({
      required int songId,
      required int queueIndex,
      required int positionMs,
      required List<int> queueIds,
    })? writeCrashSnapshot,
    Future<void> Function()? clearCrashSnapshot,
    int Function()? nowMs,
  })  : _repository = repository,
        _readSnapshot = readSnapshot,
        _readCurrentPositionMs = readCurrentPositionMs,
        _isDisposed = isDisposed,
        _clearDirty = clearDirty,
        _markDirty = markDirty,
        _onQueueSaved = onQueueSaved,
        _getDocumentsDirectory =
            getDocumentsDirectory ?? getApplicationDocumentsDirectory,
        _writeCrashSnapshot =
            writeCrashSnapshot ?? PositionCrashGuard.writeSnapshot,
        _clearCrashSnapshot =
            clearCrashSnapshot ?? PositionCrashGuard.clearSnapshot,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final IMusicRepository _repository;
  final PlaybackPositionSnapshot? Function() _readSnapshot;
  final int Function() _readCurrentPositionMs;
  final bool Function() _isDisposed;
  final VoidCallback _clearDirty;
  final VoidCallback _markDirty;
  final void Function(int savedQueueIndex) _onQueueSaved;
  final Future<Directory?> Function() _getDocumentsDirectory;
  final Future<void> Function({
    required int songId,
    required int queueIndex,
    required int positionMs,
    required List<int> queueIds,
  }) _writeCrashSnapshot;
  final Future<void> Function() _clearCrashSnapshot;
  final int Function() _nowMs;

  File? _cachedRecoveryFile;
  Future<void>? _positionSaveInFlight;
  bool _positionSaveQueued = false;
  int? _lastPersistedSongId;
  int _lastPersistedPositionMs = 0;

  Future<File?> _getLastPositionRecoveryFile() async {
    // Resolved once: this runs every ~2s while playing and the path never
    // changes, so don't hit the path_provider platform channel each time.
    final cached = _cachedRecoveryFile;
    if (cached != null) return cached;
    try {
      final dir = await _getDocumentsDirectory();
      if (dir == null) return null;
      return _cachedRecoveryFile = File(p.join(dir.path, 'last_position.json'));
    } catch (_) {
      return null;
    }
  }

  /// Reads the last atomic position snapshot (`last_position.json` or its
  /// surviving `.tmp` sibling after an interrupted rename).
  Future<Map<String, dynamic>?> readCrashPositionRecovery() async {
    try {
      final file = await _getLastPositionRecoveryFile();
      if (file == null) return null;
      // Prefer the committed file, then fall back to the surviving .tmp: if the
      // process died between writing .tmp and committing the rename, the only
      // valid snapshot lives in .tmp.
      for (final candidate in [file, File('${file.path}.tmp')]) {
        if (await candidate.exists()) {
          final content = await candidate.readAsString();
          if (content.isNotEmpty) {
            return jsonDecode(content) as Map<String, dynamic>;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Persists the current playback position now, coalescing overlapping calls.
  Future<void> saveCurrentPositionImmediate() async {
    final inFlight = _positionSaveInFlight;
    if (inFlight != null) {
      _positionSaveQueued = true;
      return inFlight;
    }
    final completer = Completer<void>();
    _positionSaveInFlight = completer.future;
    try {
      do {
        _positionSaveQueued = false;
        await _writePositionSnapshot();
      } while (_positionSaveQueued && !_isDisposed());
    } finally {
      _positionSaveInFlight = null;
      completer.complete();
    }
  }

  Future<void> _writePositionSnapshot() async {
    final snapshot = _readSnapshot();
    if (snapshot == null) {
      // Nothing to write; clear so the periodic timer does not spin.
      _clearDirty();
      return;
    }

    // B5: Guard against writing positionMs < lastPersisted for the same songId
    // when the player stopped and reset to 0 while idle.
    if (_lastPersistedSongId == snapshot.songId &&
        snapshot.positionMs < _lastPersistedPositionMs &&
        snapshot.positionMs == 0 &&
        snapshot.isIdle) {
      _clearDirty();
      return;
    }

    _lastPersistedSongId = snapshot.songId;
    _lastPersistedPositionMs = snapshot.positionMs;

    await _writeRecoveryFiles(snapshot);
    await _persistToRepository(snapshot);
  }

  Future<void> _writeRecoveryFiles(PlaybackPositionSnapshot snapshot) async {
    try {
      await _writeCrashSnapshot(
        songId: snapshot.songId,
        queueIndex: snapshot.queueIndex,
        positionMs: snapshot.positionMs,
        queueIds: snapshot.queueIds,
      );
      final recoveryFile = await _getLastPositionRecoveryFile();
      if (recoveryFile == null) return;
      final payload = jsonEncode({
        'songId': snapshot.songId,
        'positionMs': snapshot.positionMs,
        'queueIndex': snapshot.queueIndex,
        'timestamp': _nowMs(),
      });
      // Atomic commit: write to a sibling .tmp then rename, so a crash during
      // the write cannot leave a truncated recovery file.
      final tmpFile = File('${recoveryFile.path}.tmp');
      await tmpFile.writeAsString(payload, flush: true);
      try {
        await tmpFile.rename(recoveryFile.path);
      } on FileSystemException {
        // Platforms that reject rename-over-existing (e.g. Windows): copy
        // then delete, leaving the valid .tmp in place until the copy lands.
        await tmpFile.copy(recoveryFile.path);
        try {
          await tmpFile.delete();
        } catch (e, st) {
          ErrorLogger.log('Failed to remove recovery temp file',
              error: e, stackTrace: st, category: 'AudioHandler');
        }
      }
    } catch (_) {}
  }

  Future<void> _persistToRepository(PlaybackPositionSnapshot snapshot) async {
    try {
      await _repository.updateLastPosition(snapshot.songId, snapshot.positionMs);
      if (snapshot.queueDirty ||
          snapshot.queueIndex != snapshot.savedQueueIndex) {
        await _repository.saveQueue(
          snapshot.queueIds,
          snapshot.queueIndex,
          snapshot.positionMs,
        );
        _onQueueSaved(snapshot.queueIndex);
      } else {
        // Same track, later position: refresh just the current row so a cold
        // resume restores where the user actually was, not the position from
        // the last structural queue edit.
        await _repository.updateQueuePosition(snapshot.positionMs);
      }
      // Only clear AFTER a successful write, and only if no newer position
      // arrived while the async database write was in flight.
      if (_readCurrentPositionMs() == snapshot.positionMs) {
        _clearDirty();
      }
      unawaited(_clearCrashSnapshot());
    } catch (e, st) {
      // Re-dirty so the periodic timer (and a later app pause) retries.
      _markDirty();
      ErrorLogger.log('Failed to save current position',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }
}
