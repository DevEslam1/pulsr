// lib/features/remote_sources/remote_cache_sink.dart
//
// P0-1 "remote sources": the cache entry record and the write handle.
//
// Split from the cache store so the store keeps its size/index policy in one
// readable class while the "append bytes, then rename atomically" mechanics live
// here. A sink is only ever constructed by RemoteCacheStore.beginWrite.
import 'dart:io';

import '../../core/utils/error_logger.dart';
import 'remote_cache_store.dart';

/// Handle for one in-progress cache write.
///
/// Bytes are appended to a `.partial` file; [commit] renames it into place and
/// registers the entry, [abort] deletes it. When the entry grows past the
/// cache's per-entry limit the sink goes inactive, drops further bytes and
/// [commit] returns `null`, so a caller streaming to a player is never broken
/// by a file that is simply too big to cache.
class RemoteCacheSink {
  /// Creates a sink. Call [RemoteCacheStore.beginWrite] instead of this.
  RemoteCacheSink({
    required this.key,
    required File partialFile,
    required IOSink sink,
    required RemoteCacheStore store,
    required this.pinned,
    required int maxEntryBytes,
  })  : _partialFile = partialFile,
        _sink = sink,
        _store = store,
        _maxEntryBytes = maxEntryBytes;

  /// Logical cache key this sink writes.
  final String key;

  /// Whether the entry is pinned on commit.
  final bool pinned;

  final File _partialFile;
  final RemoteCacheStore _store;
  final int _maxEntryBytes;
  IOSink? _sink;
  int _bytes = 0;
  bool _active = true;
  bool _closed = false;

  /// Whether the sink still accepts bytes.
  bool get isActive => _active;

  /// Bytes accepted so far.
  int get bytesWritten => _bytes;

  /// Appends [chunk]; a no-op once the sink went inactive or closed.
  ///
  /// Synchronous so a streaming loop can tee without awaiting disk I/O for
  /// every chunk; failures surface from [commit].
  void add(List<int> chunk) {
    if (!_active || _closed) return;
    _bytes += chunk.length;
    if (_bytes > _maxEntryBytes) {
      _active = false;
      return;
    }
    try {
      _sink?.add(chunk);
    } catch (e, st) {
      _active = false;
      ErrorLogger.log(
        'Remote cache write failed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
  }

  /// Flushes, renames the partial file into place and indexes the entry.
  ///
  /// Returns the cached file, or `null` when the write was aborted or the entry
  /// exceeded the per-entry limit (the partial file is deleted in both cases).
  Future<File?> commit() async {
    if (_closed) return null;
    _closed = true;
    final sink = _sink;
    _sink = null;
    if (!_active || sink == null) {
      // Close the handle first: on Windows an open sink keeps the file locked
      // and the partial would survive (and be picked up again) after a crash.
      try {
        await sink?.close();
      } catch (e, st) {
        ErrorLogger.log(
          'Remote cache sink did not close after an aborted write',
          error: e,
          stackTrace: st,
          category: 'RemoteSources',
        );
      }
      await _discard();
      return null;
    }
    try {
      await sink.flush();
      await sink.close();
      return await _store.commitPartial(
        key: key,
        partial: _partialFile,
        bytes: _bytes,
        pinned: pinned,
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Remote cache commit failed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      await _discard();
      return null;
    }
  }

  /// Abandons the write and deletes the partial file.
  Future<void> abort() async {
    if (_closed) return;
    _closed = true;
    final sink = _sink;
    _sink = null;
    try {
      await sink?.close();
    } catch (e, st) {
      ErrorLogger.log(
        'Remote cache sink close failed after abort',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
    await _discard();
  }

  Future<void> _discard() async {
    try {
      if (await _partialFile.exists()) await _partialFile.delete();
    } catch (e, st) {
      ErrorLogger.log(
        'Could not delete a remote cache partial file',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'file': _partialFile.path},
      );
    }
  }
}
