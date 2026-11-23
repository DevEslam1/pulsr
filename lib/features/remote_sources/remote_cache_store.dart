// lib/features/remote_sources/remote_cache_store.dart
//
// P0-1 "remote sources": the disk cache that makes network files playable and
// seekable.
//
// Layout: <cache>/remote_cache/<sha256>.bin  +  <cache>/remote_cache/index.json
// Every write goes to `<hash>.bin.partial` and is renamed into place only after
// the bytes are flushed, so an interrupted download can never leave a truncated
// entry that a player would treat as complete. The cap is enforced with LRU
// eviction (pinned entries are never evicted), and concurrent fetches for the
// same key share one download ("single flight").
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/error_logger.dart';
import 'remote_cache_index.dart';
import 'remote_cache_sink.dart';

/// LRU disk cache for remote source files.
///
/// [directoryProvider] is injectable so tests can point the cache at a temporary
/// directory without the path_provider plugin.
class RemoteCacheStore {
  /// Creates the cache.
  ///
  /// [maxBytes] is the total budget (512 MB by default); [maxEntryBytes]
  /// defaults to the whole budget because a single music file is never expected
  /// to exceed it.
  RemoteCacheStore({
    Future<Directory> Function()? directoryProvider,
    DateTime Function()? clock,
    this.maxBytes = 512 * 1024 * 1024,
    int? maxEntryBytes,
  })  : _directoryProvider = directoryProvider ?? _defaultDirectory,
        _clock = clock ?? DateTime.now,
        maxEntryBytes = maxEntryBytes ?? maxBytes;

  /// Folder name under the app cache directory.
  static const String directoryName = 'remote_cache';

  /// Name of the JSON index file.
  static const String indexFileName = RemoteCacheIndex.indexFileName;

  /// Suffix of an in-flight file; leftovers are deleted on the next start.
  static const String partialSuffix = RemoteCacheIndex.partialSuffix;

  /// Name used for the disambiguating part of a partial file. Two concurrent
  /// writes for the same key must never open the same path: before this, the
  /// second `beginWrite` deleted and reopened the first writer's partial, so
  /// their bytes interleaved and one commit renamed a mixed file into place.
  static String _partialToken() {
    _partialCounter += 1;
    final salt = _partialRandom.nextInt(0xFFFFFF).toRadixString(16);
    return '$_partialCounter$salt';
  }

  static final Random _partialRandom = Random();
  static int _partialCounter = 0;

  /// Key prefix used for files found on disk without an index row. They can
  /// never be served (the logical path is unknown) and are evicted first.
  static const String untrackedPrefix = 'untracked:';

  /// Total bytes this cache may occupy.
  final int maxBytes;

  /// Largest single entry that will be cached.
  final int maxEntryBytes;

  final Future<Directory> Function() _directoryProvider;
  final DateTime Function() _clock;

  final Map<String, RemoteCacheEntry> _entries = <String, RemoteCacheEntry>{};
  final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};
  final Set<RemoteCacheSink> _activeSinks = <RemoteCacheSink>{};
  final Set<String> _pinnedKeys = <String>{};

  /// Tail of the per-key commit queue. Commits for one key run one at a time in
  /// arrival order, so the last finished download wins the index entry instead
  /// of two renames racing over the same target file.
  final Map<String, Future<void>> _commitQueues = <String, Future<void>>{};
  int _clearGeneration = 0;
  Future<void>? _initFuture;
  Directory? _root;
  RemoteCacheIndex? _index;
  DateTime _lastIndexWrite = DateTime.fromMillisecondsSinceEpoch(0);

  /// Monotonic counter that advances whenever an entry is committed, removed or
  /// the whole cache is cleared.
  ///
  /// [RemoteStreamServer] stores the stamp beside each provider stat it memoizes:
  /// a different stamp means the entry changed underneath the memo, so the next
  /// request re-stats instead of trusting a size/validators snapshot that a
  /// finished download, an eviction or a delete just made obsolete.
  int get changeStamp => _changeStamp;
  int _changeStamp = 0;

  /// Cache key for a source id and provider path.
  static String keyFor(String sourceId, String path) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return '$sourceId/$normalized';
  }

  /// Initializes the directory and index; safe to call repeatedly.
  Future<void> ensureInitialized() => _initFuture ??= _initialize();

  /// Returns the cached file for [sourceId]/[path], or `null` on a miss.
  ///
  /// [etag] and [modifiedAt] are the validators the provider just reported for
  /// the file. When a cached entry carries a validator and the server now
  /// reports a different one, the entry is stale: it is deleted and treated as
  /// a miss so playback re-downloads instead of serving old audio. A `null`
  /// validator means "the server did not say", not "changed", so an entry is
  /// kept in that case.
  Future<File?> lookup(
    String sourceId,
    String path, {
    String? etag,
    DateTime? modifiedAt,
  }) async {
    await ensureInitialized();
    final key = keyFor(sourceId, path);
    final entry = _entries[key];
    if (entry == null) return null;
    if (!_matchesValidators(entry, etag: etag, modifiedAt: modifiedAt)) {
      await _deleteEntry(key);
      return null;
    }
    final file = File(p.join(_root!.path, entry.fileName));
    if (!await file.exists()) {
      _entries.remove(key);
      await _persistIndex();
      return null;
    }
    entry.lastAccess = _clock();
    await _persistIndexIfStale();
    return file;
  }

  /// Whether [sourceId]/[path] is fully cached.
  ///
  /// Validators are not checked here: callers that care about staleness use
  /// [lookup] with the provider's etag/mtime.
  Future<bool> contains(String sourceId, String path) async =>
      await lookup(sourceId, path) != null;

  /// Total cached bytes, after pruning entries whose file disappeared.
  Future<int> currentBytes() async {
    await ensureInitialized();
    return _totalBytes();
  }

  /// Starts a write for [sourceId]/[path].
  ///
  /// The returned sink must be committed or aborted; see [RemoteCacheSink].
  /// Throws [StateError] when the cache directory could not be initialized.
  Future<RemoteCacheSink> beginWrite(
    String sourceId,
    String path, {
    bool pin = false,
    String? etag,
    DateTime? modifiedAt,
  }) async {
    await ensureInitialized();
    final root = _root;
    if (root == null) {
      throw StateError('The remote cache directory is unavailable.');
    }
    final key = keyFor(sourceId, path);
    final digest = sha256.convert(utf8.encode(key)).toString();
    // Unique per sink, still `*.partial` so removeStalePartials cleans up a
    // crash. Never delete an existing partial here: it belongs to another sink.
    final partial = File(
        p.join(root.path, '$digest.bin.${_partialToken()}$partialSuffix'));
    await partial.parent.create(recursive: true);
    final sink = partial.openWrite();
    final cacheSink = RemoteCacheSink(
      key: key,
      partialFile: partial,
      sink: sink,
      store: this,
      pinned: pin,
      maxEntryBytes: maxEntryBytes,
      etag: etag,
      modifiedAt: modifiedAt,
      clearGeneration: _clearGeneration,
      onClose: _activeSinks.remove,
    );
    _activeSinks.add(cacheSink);
    return cacheSink;
  }

  /// Downloads [bytes] for [sourceId]/[path] and caches it.
  ///
  /// Returns `null` when the entry exceeded [maxEntryBytes]; in that case the
  /// stream is abandoned early instead of being written to disk.
  Future<File?> store(
    String sourceId,
    String path,
    Stream<List<int>> bytes, {
    bool pin = false,
    String? etag,
    DateTime? modifiedAt,
  }) async {
    RemoteCacheSink? sink;
    try {
      sink = await beginWrite(
        sourceId,
        path,
        pin: pin,
        etag: etag,
        modifiedAt: modifiedAt,
      );
      await for (final chunk in bytes) {
        if (!sink.isActive) break;
        sink.add(chunk);
      }
      return await sink.commit();
    } catch (e, st) {
      await sink?.abort();
      ErrorLogger.log(
        'Remote cache store failed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'source': sourceId},
      );
      return null;
    }
  }

  /// Returns the cached file for [sourceId]/[path], downloading it once.
  ///
  /// Concurrent callers for the same key await the same download instead of
  /// opening several connections (FTP in particular allows one transfer at a
  /// time). Returns `null` when the download failed or the file is too large.
  Future<File?> fetch(
    String sourceId,
    String path, {
    required Stream<List<int>> Function() openStream,
    bool pin = false,
    String? etag,
    DateTime? modifiedAt,
  }) async {
    final key = keyFor(sourceId, path);
    final hit = await lookup(
      sourceId,
      path,
      etag: etag,
      modifiedAt: modifiedAt,
    );
    if (hit != null) return hit;
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = store(
      sourceId,
      path,
      openStream(),
      pin: pin,
      etag: etag,
      modifiedAt: modifiedAt,
    );
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Pins (or unpins) an existing entry so eviction skips it.
  ///
  /// When called before the entry finishes streaming into the cache, the pin is
  /// queued so [commitPartial] persists it atomically on commit.
  Future<void> pin(String sourceId, String path, {bool pinned = true}) async {
    await ensureInitialized();
    final key = keyFor(sourceId, path);
    final entry = _entries[key];
    if (entry == null) {
      if (pinned) {
        _pinnedKeys.add(key);
      } else {
        _pinnedKeys.remove(key);
      }
      return;
    }
    if (pinned) {
      _pinnedKeys.add(key);
    } else {
      _pinnedKeys.remove(key);
    }
    if (entry.pinned == pinned) return;
    entry.pinned = pinned;
    await _persistIndex();
    if (!pinned) await evictIfNeeded();
  }

  /// Pins every cached file of [sourceId] (used when a library is played).
  Future<void> pinSource(String sourceId, {bool pinned = true}) async {
    await ensureInitialized();
    final prefix = '$sourceId/';
    if (!pinned) {
      _pinnedKeys.removeWhere((key) => key.startsWith(prefix));
    }
    var changed = false;
    for (final entry in _entries.values) {
      if (entry.key.startsWith(prefix) && entry.pinned != pinned) {
        entry.pinned = pinned;
        changed = true;
      }
    }
    if (changed) {
      await _persistIndex();
      if (!pinned) await evictIfNeeded();
    }
  }

  /// Deletes one cached file.
  Future<void> remove(String sourceId, String path) async {
    await ensureInitialized();
    _pinnedKeys.remove(keyFor(sourceId, path));
    await _deleteEntry(keyFor(sourceId, path));
  }

  /// Deletes every cached file belonging to [sourceId].
  ///
  /// Used when the user deletes the source, so its audio does not stay on disk
  /// with no way to reach it.
  Future<void> removeSource(String sourceId) async {
    await ensureInitialized();
    final prefix = '$sourceId/';
    _pinnedKeys.removeWhere((key) => key.startsWith(prefix));
    final keys = _entries.keys.where((key) => key.startsWith(prefix)).toList();
    var removed = false;
    for (final key in keys) {
      if (await _deleteEntry(key, persist: false)) {
        removed = true;
      }
    }
    if (removed) await _persistIndex();
  }

  /// Evicts least-recently-used unpinned entries until the cache fits.
  Future<void> evictIfNeeded({String? protectKey}) async {
    await ensureInitialized();
    await _evictOverCap(protectKey);
  }

  /// Eviction without the `ensureInitialized` await, so initialization can call
  /// it without waiting on its own future (which would deadlock).
  Future<void> _evictOverCap(String? protectKey) async {
    var total = _totalBytes();
    if (total <= maxBytes) return;
    final candidates = _entries.values
        .where((e) => !e.pinned && e.key != protectKey)
        .toList()
      ..sort((a, b) => a.lastAccess.compareTo(b.lastAccess));
    var removed = false;
    for (final entry in candidates) {
      if (total <= maxBytes) break;
      total -= entry.sizeBytes;
      if (await _deleteEntry(entry.key, persist: false)) {
        removed = true;
      }
    }
    if (removed) await _persistIndex();
    if (total > maxBytes) {
      ErrorLogger.log(
        'Remote cache still above its cap because the remaining entries are pinned',
        category: 'RemoteSources',
        meta: {'bytes': total, 'cap': maxBytes},
      );
    }
  }

  /// Deletes every cached file and the index, aborting active writes and
  /// draining queued commits first so background work cannot resurrect files.
  Future<void> clear() async {
    await ensureInitialized();
    _clearGeneration++;
    while (_activeSinks.isNotEmpty ||
        _inFlight.isNotEmpty ||
        _commitQueues.isNotEmpty) {
      for (final sink in _activeSinks.toList(growable: false)) {
        await sink.abort();
        _activeSinks.remove(sink);
      }
      for (final future in _inFlight.values.toList(growable: false)) {
        try {
          await future;
        } catch (_) {}
      }
      for (final future in _commitQueues.values.toList(growable: false)) {
        try {
          await future;
        } catch (_) {}
      }
    }
    await _index?.waitForIdle();
    _pinnedKeys.clear();
    _entries.clear();
    _changeStamp++;
    _lastIndexWrite = DateTime.fromMillisecondsSinceEpoch(0);
    final root = _root;
    if (root == null || !await root.exists()) return;
    try {
      await for (final entity in root.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (e, st) {
          ErrorLogger.log(
            'Could not delete a remote cache entry during clear',
            error: e,
            stackTrace: st,
            category: 'RemoteSources',
            meta: {'path': entity.path},
          );
        }
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Could not list the remote cache directory',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
  }

  /// Finishes a write started by [RemoteCacheSink]: renames the partial file
  /// into place, indexes it and evicts if the cache is over its cap.
  Future<File?> commitPartial({
    required String key,
    required File partial,
    required int bytes,
    required bool pinned,
    String? etag,
    DateTime? modifiedAt,
    int? clearGeneration,
  }) {
    // Serialize per key: the rename, the index write and eviction are not
    // reentrant, and two concurrent downloads of one key must finish with a
    // single entry whose bytes are the last writer's ("last commit wins").
    return _serializedPerKey(
      key,
      () => _commitPartialNow(
        key: key,
        partial: partial,
        bytes: bytes,
        pinned: pinned,
        etag: etag,
        modifiedAt: modifiedAt,
        clearGeneration: clearGeneration,
      ),
    );
  }

  /// Runs [action] once every earlier action queued for [key] has finished.
  ///
  /// The queue tail is a completer future, never a failure: an aborted commit
  /// must not poison later commits for the same key.
  Future<T> _serializedPerKey<T>(String key, Future<T> Function() action) {
    final previous = _commitQueues[key];
    final completer = Completer<void>();
    _commitQueues[key] = completer.future;

    Future<T> run() async {
      try {
        if (previous != null) await previous;
        return await action();
      } finally {
        completer.complete();
        if (identical(_commitQueues[key], completer.future)) {
          _commitQueues.remove(key);
        }
      }
    }

    return run();
  }

  Future<File?> _commitPartialNow({
    required String key,
    required File partial,
    required int bytes,
    required bool pinned,
    String? etag,
    DateTime? modifiedAt,
    int? clearGeneration,
  }) async {
    await ensureInitialized();
    if (clearGeneration != null && clearGeneration != _clearGeneration) {
      if (await partial.exists()) await partial.delete();
      return null;
    }
    final root = _root;
    if (root == null) return null;
    final digest = sha256.convert(utf8.encode(key)).toString();
    final target = File(p.join(root.path, '$digest.bin'));
    if (await target.exists()) {
      // Rename onto an existing file is not portable (it fails on Windows).
      await target.delete();
    }
    await partial.rename(target.path);
    final existing = _entries[key];
    final shouldPin = pinned || _pinnedKeys.remove(key) || (existing?.pinned ?? false);
    _entries[key] = RemoteCacheEntry(
      key: key,
      fileName: '$digest.bin',
      sizeBytes: bytes,
      lastAccess: _clock(),
      pinned: shouldPin,
      etag: etag,
      modifiedAt: modifiedAt,
    );
    await _persistIndex();
    _changeStamp++;
    await evictIfNeeded(protectKey: key);
    return target;
  }

  Future<bool> _deleteEntry(String key, {bool persist = true}) async {
    final entry = _entries.remove(key);
    if (entry == null) return false;
    _changeStamp++;
    final root = _root;
    if (root == null) return true;
    final file = File(p.join(root.path, entry.fileName));
    try {
      if (await file.exists()) await file.delete();
    } catch (e, st) {
      ErrorLogger.log(
        'Could not delete a remote cache file',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'key': key},
      );
    }
    if (persist) await _persistIndex();
    return true;
  }

  int _totalBytes() {
    var total = 0;
    for (final entry in _entries.values) {
      total += entry.sizeBytes;
    }
    return total;
  }

  /// True when the cached validators still describe the server's file.
  ///
  /// Seconds are compared, not milliseconds: HTTP `Last-Modified` and FTP
  /// `MDTM` only carry second precision, so a whole-second difference is real
  /// while a sub-second one is encoding noise.
  static bool _matchesValidators(
    RemoteCacheEntry entry, {
    String? etag,
    DateTime? modifiedAt,
  }) {
    final cachedEtag = entry.etag;
    if (etag != null && cachedEtag != null && etag != cachedEtag) return false;
    final cachedModified = entry.modifiedAt;
    if (modifiedAt != null &&
        cachedModified != null &&
        modifiedAt.millisecondsSinceEpoch ~/ 1000 !=
            cachedModified.millisecondsSinceEpoch ~/ 1000) {
      return false;
    }
    return true;
  }

  Future<void> _initialize() async {
    try {
      final dir = await _directoryProvider();
      await dir.create(recursive: true);
      final index = RemoteCacheIndex(directory: dir, clock: _clock);
      _root = dir;
      _index = index;
      await index.removeStalePartials();
      _entries.addAll(await index.read());
      _entries.addAll(
        await index.scanUntracked(_entries, untrackedPrefix: untrackedPrefix),
      );
      await _evictOverCap(null);
    } catch (e, st) {
      // A cache that cannot start must not block playback: lookups miss and
      // streams fall through to the provider.
      ErrorLogger.log(
        'Remote cache initialization failed; continuing without cache',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      _root = null;
      _index = null;
    }
  }

  Future<void> _persistIndexIfStale() async {
    final now = _clock();
    if (now.difference(_lastIndexWrite).inSeconds < 30) return;
    await _persistIndex();
  }

  Future<void> _persistIndex() async {
    final index = _index;
    if (index == null) return;
    await index.write(_entries);
    _lastIndexWrite = _clock();
  }

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationCacheDirectory();
    return Directory(p.join(base.path, directoryName));
  }
}
