// lib/features/remote_sources/remote_cache_index.dart
//
// P0-1 "remote sources": the cache's on-disk index plus the entry record it
// stores.
//
// `<cache>/index.json` maps a logical key ("<sourceId>/<path>") to the hashed
// file name, its size, its last access time and its pinned flag. The index is
// written through a `.partial` file and renamed, and a missing or corrupt index
// is recovered by scanning the `.bin` files that are actually on disk.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/error_logger.dart';

/// One cache entry as tracked in the index file.
class RemoteCacheEntry {
  /// Creates an entry record.
  RemoteCacheEntry({
    required this.key,
    required this.fileName,
    required this.sizeBytes,
    required this.lastAccess,
    required this.pinned,
  });

  /// Logical key: `<sourceId>/<path>`.
  final String key;

  /// File name inside the cache directory.
  final String fileName;

  /// Size on disk in bytes.
  int sizeBytes;

  /// Last read or write, used for LRU ordering.
  DateTime lastAccess;

  /// Pinned entries are exempt from eviction.
  bool pinned;

  /// Serializes the record for the index file.
  Map<String, dynamic> toJson() => {
        'file': fileName,
        'size': sizeBytes,
        'lastAccess': lastAccess.millisecondsSinceEpoch,
        'pinned': pinned,
      };
}

/// Reads and writes `<cache>/index.json`.
class RemoteCacheIndex {
  /// Creates an index over [directory].
  RemoteCacheIndex({required this.directory, required this.clock});

  /// Name of the JSON index file.
  static const String indexFileName = 'index.json';

  /// Suffix of an in-flight file; leftovers are deleted on the next start.
  static const String partialSuffix = '.partial';

  /// Directory the entries live in.
  final Directory directory;

  /// Clock used for index write throttling.
  final DateTime Function() clock;

  /// Deletes every leftover `*.partial` file (an interrupted write).
  Future<void> removeStalePartials() async {
    try {
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith(partialSuffix)) {
          await entity.delete();
        }
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Could not clean stale remote cache partial files',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
  }

  /// Reads the index, keeping only rows whose file still exists.
  ///
  /// Sizes are taken from the files themselves, so an external clean-up cannot
  /// leave the index overstating usage.
  Future<Map<String, RemoteCacheEntry>> read() async {
    final entries = <String, RemoteCacheEntry>{};
    final indexFile = File(p.join(directory.path, indexFileName));
    if (!await indexFile.exists()) return entries;
    try {
      final decoded = jsonDecode(await indexFile.readAsString());
      if (decoded is! Map<String, dynamic>) return entries;
      final rawEntries = decoded['entries'];
      if (rawEntries is! Map<String, dynamic>) return entries;
      for (final item in rawEntries.entries) {
        final value = item.value;
        if (value is! Map<String, dynamic>) continue;
        final lastAccessMs = (value['lastAccess'] as num?)?.toInt() ?? 0;
        final digest = sha256.convert(utf8.encode(item.key)).toString();
        final fileName = value['file'] as String? ?? '$digest.bin';
        final file = File(p.join(directory.path, fileName));
        if (!await file.exists()) continue;
        entries[item.key] = RemoteCacheEntry(
          key: item.key,
          fileName: fileName,
          sizeBytes: await file.length(),
          lastAccess: DateTime.fromMillisecondsSinceEpoch(lastAccessMs),
          pinned: value['pinned'] as bool? ?? false,
        );
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Remote cache index is unreadable; rebuilding from files',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      entries.clear();
    }
    return entries;
  }

  /// Adds `.bin` files that have no index row under [untrackedPrefix].
  ///
  /// Their logical path is unknown, so they can only be evicted; counting them
  /// keeps `currentBytes` honest after an index loss.
  Future<Map<String, RemoteCacheEntry>> scanUntracked(
    Map<String, RemoteCacheEntry> tracked, {
    required String untrackedPrefix,
  }) async {
    final found = <String, RemoteCacheEntry>{};
    try {
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.endsWith('.bin') || name.endsWith(partialSuffix)) continue;
        if (tracked.values.any((entry) => entry.fileName == name)) continue;
        // A file whose index row was lost stays usable; LRU order falls back to
        // its modification time.
        final stat = await entity.stat();
        final key = '$untrackedPrefix$name';
        found[key] = RemoteCacheEntry(
          key: key,
          fileName: name,
          sizeBytes: stat.size,
          lastAccess: stat.modified,
          pinned: false,
        );
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Could not reconcile untracked remote cache files',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
    return found;
  }

  /// Writes the index atomically through a `.partial` file.
  Future<void> write(Map<String, RemoteCacheEntry> entries) async {
    final target = File(p.join(directory.path, indexFileName));
    final temp = File('${target.path}$partialSuffix');
    try {
      final payload = jsonEncode({
        'version': 1,
        'entries': {
          for (final entry in entries.values) entry.key: entry.toJson(),
        },
      });
      await temp.writeAsString(payload, flush: true);
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
    } catch (e, st) {
      ErrorLogger.log(
        'Could not write the remote cache index',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
  }
}
