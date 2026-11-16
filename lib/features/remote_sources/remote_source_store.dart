// lib/features/remote_sources/remote_source_store.dart
//
// P0-1 "remote sources": persistence of the configured libraries.
//
// The whole list is stored as one JSON document under [RemoteSourceStore.prefsKey]
// so a mutation is a single atomic write instead of N key updates. Passwords
// are not part of this document (see RemoteCredentialsStore).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/error_logger.dart';
import '../../domain/models/remote_source.dart';
import 'remote_host_allowlist.dart';
import 'remote_stream_server.dart';

/// Reads and writes the user's remote library list.
///
/// A single instance owns the in-memory list; [ready] completes once the first
/// disk read finished, and every mutation is serialized through a [Mutex] so
/// two quick "add" taps can never lose an entry.
class RemoteSourceStore {
  /// SharedPreferences key holding the JSON list.
  static const String prefsKey = 'remote_sources_v1';

  /// Hard ceiling so a corrupted file or a script cannot bloat the list.
  static const int maxEntries = 100;

  final Mutex _mutex = Mutex();
  final List<RemoteSource> _sources = <RemoteSource>[];
  Future<void>? _loadFuture;
  bool _loadFailed = false;

  /// Completes when the initial read from disk has finished.
  Future<void> get ready => _loadFuture ??= _load();

  /// Current list, in insertion order.
  List<RemoteSource> get list => List<RemoteSource>.unmodifiable(_sources);

  /// Whether the last load hit an unreadable prefs value (the list is empty).
  bool get loadFailed => _loadFailed;

  /// Looks up a source by [id], or `null` when it was deleted.
  RemoteSource? getById(String id) {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  /// Adds [source], replacing an existing entry with the same id.
  ///
  /// Returns the stored source. Throws [StateError] when [source] is invalid or
  /// the list is already at [maxEntries].
  Future<RemoteSource> add(RemoteSource source) async {
    final error = source.validationError;
    if (error != null) throw StateError(error);
    await ready;
    return _mutex.protect(() async {
      final index = _sources.indexWhere((s) => s.id == source.id);
      if (index == -1) {
        if (_sources.length >= maxEntries) {
          throw StateError('You can add at most $maxEntries remote sources.');
        }
        _sources.add(source);
      } else {
        _sources[index] = source;
      }
      await _persist();
      // Artwork/widget fetchers may reach this host from now on (LAN cover
      // art); see RemoteHostAllowlist for the exact scope.
      RemoteHostAllowlist.instance.allowSource(source);
      return source;
    });
  }

  /// Replaces the entry with the same id as [source].
  ///
  /// Behaves like [add] when the id is not present, so an edit that raced a
  /// delete still lands somewhere sensible.
  Future<void> update(RemoteSource source) async {
    await add(source);
  }

  /// Deletes the source with [id]; a no-op when it is already gone.
  ///
  /// Also revokes the loopback stream token of that source, so a URL already
  /// handed to the player cannot keep streaming a library the user removed.
  Future<void> remove(String id) async {
    await ready;
    await _mutex.protect(() async {
      final before = _sources.length;
      _sources.removeWhere((s) => s.id == id);
      if (_sources.length != before) await _persist();
    });
    RemoteHostAllowlist.instance.removeSource(id);
    await RemoteStreamServer.revokeSource(id);
  }

  /// Re-reads the list from disk, discarding unsaved in-memory state.
  Future<void> reload() async {
    _loadFuture = null;
    _sources.clear();
    await ready;
  }

  Future<void> _load() async {
    // The list is the source of truth for the allowlist: rebuild it rather
    // than merging with entries left over from a previous load.
    RemoteHostAllowlist.instance.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _loadFailed = true;
        ErrorLogger.log(
          'Remote source list is not a JSON array; ignoring it',
          category: 'RemoteSources',
        );
        return;
      }
      var skipped = 0;
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          skipped++;
          continue;
        }
        try {
          final source = RemoteSource.fromJson(item);
          if (source.id.isEmpty) {
            skipped++;
            continue;
          }
          _sources.add(source);
          RemoteHostAllowlist.instance.allowSource(source);
        } on FormatException catch (e) {
          skipped++;
          ErrorLogger.log(
            'Skipping an unusable remote source entry',
            error: e,
            category: 'RemoteSources',
          );
        }
      }
      if (skipped > 0) {
        debugPrint('[RemoteSources] skipped $skipped unusable entries');
      }
    } catch (e, st) {
      _loadFailed = true;
      _sources.clear();
      ErrorLogger.log(
        'Failed to load remote sources',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _sources.map((source) => source.toJson()).toList(growable: false),
    );
    final ok = await prefs.setString(prefsKey, encoded);
    if (!ok) {
      ErrorLogger.log(
        'Remote source list could not be written to preferences',
        category: 'RemoteSources',
      );
      throw StateError('Could not save the remote source list.');
    }
  }
}
