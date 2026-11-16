// lib/features/audio_profiles/audio_profile_service.dart
//
// File-backed store for shareable audio profiles plus the only code path that
// writes a profile into the live audio settings. Each apply takes a snapshot
// first, keeps a durable backup of it, and restores the snapshot when any key
// fails to write.

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_error.dart';
import '../../core/utils/error_logger.dart';
import 'audio_profile.dart';
import 'audio_profile_keys.dart';
import 'audio_profile_strings.dart';

/// Raised when a profile file cannot be read, written, imported or deleted.
class AudioProfileStoreError extends AppError {
  const AudioProfileStoreError({
    required super.code,
    required super.userMessage,
    super.cause,
    super.stackTrace,
  });
}

/// Raised when [AudioProfileService.apply] could not write every setting.
///
/// [rolledBack] reports whether the pre-apply snapshot was restored and
/// [appliedKeys] lists the keys that had been written before the failure.
class AudioProfileApplyError extends AppError {
  const AudioProfileApplyError({
    required super.code,
    required super.userMessage,
    this.rolledBack = false,
    this.appliedKeys = const <String>[],
    super.cause,
    super.stackTrace,
  });

  /// Whether the previous settings were restored.
  final bool rolledBack;

  /// Settings written before the failure.
  final List<String> appliedKeys;
}

/// Outcome of a successful [AudioProfileService.apply].
class AudioProfileApplyReport {
  const AudioProfileApplyReport({
    required this.appliedCount,
    required this.skippedKeys,
    required this.backupSaved,
  });

  /// Number of settings written to shared preferences.
  final int appliedCount;

  /// Profile keys that are outside [AudioProfileKeys.whitelist].
  final List<String> skippedKeys;

  /// Whether the durable pre-apply backup was written.
  final bool backupSaved;
}

/// Captures, stores, exports and applies [AudioProfile]s.
class AudioProfileService {
  AudioProfileService({
    required SharedPreferences prefs,
    Future<Directory> Function()? rootDirectory,
    String Function()? appVersion,
    DateTime Function()? clock,
  })  : _prefs = prefs,
        _rootDirectory = rootDirectory ?? getApplicationSupportDirectory,
        _appVersion = appVersion ?? (() => AppConfig.appVersion),
        _clock = clock ?? DateTime.now;

  /// Folder under the app support directory that holds the profile files.
  static const String directoryName = 'audio_profiles';

  /// Sub-folder that holds the automatic pre-apply backups.
  static const String backupDirectoryName = 'backups';

  /// How many pre-apply backups are kept; older ones are pruned.
  static const int maxBackups = 10;

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,80}$');
  static final Random _random = Random();

  final SharedPreferences _prefs;
  final Future<Directory> Function() _rootDirectory;
  final String Function() _appVersion;
  final DateTime Function() _clock;
  late final _ProfileBackups _backups = _ProfileBackups(
    directory: () => _directory(backups: true),
    clock: _clock,
  );

  /// Every saved profile, newest first. Unreadable files are logged and
  /// skipped so one corrupt profile cannot hide the rest.
  Future<List<AudioProfile>> list() async {
    try {
      final directory = await _directory();
      final profiles = <AudioProfile>[];
      await for (final entity in directory.list()) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
          continue;
        }
        try {
          profiles.add(await _readProfile(entity));
        } catch (e, st) {
          ErrorLogger.log(
            'Skipping unreadable audio profile',
            error: e,
            stackTrace: st,
            category: 'AudioProfileService',
            meta: <String, dynamic>{'file': p.basename(entity.path)},
          );
        }
      }
      profiles.sort((a, b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate != 0 ? byDate : a.name.compareTo(b.name);
      });
      return profiles;
    } catch (e, st) {
      ErrorLogger.log(
        'Listing audio profiles failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
      );
      throw AudioProfileStoreError(
        code: 'audio-profile-list-failed',
        userMessage: AudioProfileStrings.storeFailed,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Captures the whitelisted settings currently in shared preferences and
  /// stores them as a new profile called [name].
  Future<AudioProfile> captureCurrent(
    String name, {
    int? deviceVid,
    int? devicePid,
    String? deviceName,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const AudioProfileStoreError(
        code: 'audio-profile-name-empty',
        userMessage: AudioProfileStrings.nameRequired,
      );
    }
    final values = <String, Object?>{};
    for (final key in AudioProfileKeys.whitelist) {
      final value = _prefs.get(key);
      if (value != null) values[key] = value;
    }
    final profile = AudioProfile(
      id: _newId(),
      name: trimmed,
      createdAt: _clock(),
      appVersion: _appVersion(),
      deviceVid: deviceVid,
      devicePid: devicePid,
      deviceName: deviceName,
      values: values,
    );
    return _persist(profile);
  }

  /// Writes [profile] to a fresh temporary `.json` file and returns it, ready
  /// to hand to the share sheet.
  Future<File> export(AudioProfile profile) async {
    try {
      final directory =
          await Directory.systemTemp.createTemp('pulsr_audio_profile_');
      final file = File(p.join(directory.path, _exportFileName(profile)));
      await file.writeAsString(profile.toJsonString(), flush: true);
      return file;
    } catch (e, st) {
      ErrorLogger.log(
        'Exporting audio profile failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
        meta: <String, dynamic>{'profileId': profile.id},
      );
      throw AudioProfileStoreError(
        code: 'audio-profile-export-failed',
        userMessage: AudioProfileStrings.shareFailed,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Applies [profile] to the live settings.
  ///
  /// Only keys inside [AudioProfileKeys.whitelist] are written; anything else
  /// is reported in [AudioProfileApplyReport.skippedKeys]. The current values
  /// are snapshotted (and backed up as a file) before the first write, and the
  /// snapshot is restored if a write fails part-way through.
  Future<AudioProfileApplyReport> apply(AudioProfile profile) async {
    final snapshot = <String, Object?>{
      for (final key in AudioProfileKeys.whitelist) key: _prefs.get(key),
    };
    final backup = AudioProfile(
      id: _newId(),
      name: AudioProfileStrings.backupOf(profile.name),
      createdAt: _clock(),
      appVersion: _appVersion(),
      deviceVid: profile.deviceVid,
      devicePid: profile.devicePid,
      deviceName: profile.deviceName,
      values: <String, Object?>{
        for (final entry in snapshot.entries)
          if (entry.value != null) entry.key: entry.value!,
      },
    );
    final backupSaved = await _backups.save(backup);

    final applied = <String>[];
    final skipped = <String>[];
    try {
      for (final entry in profile.values.entries) {
        if (!AudioProfileKeys.isWhitelisted(entry.key)) {
          skipped.add(entry.key);
          continue;
        }
        final written = await writeKeyValue(entry.key, entry.value);
        if (!written) {
          throw _WriteRejected(entry.key);
        }
        applied.add(entry.key);
      }
      return AudioProfileApplyReport(
        appliedCount: applied.length,
        skippedKeys: List<String>.unmodifiable(skipped),
        backupSaved: backupSaved,
      );
    } catch (e, st) {
      final rolledBack = await _restore(snapshot);
      ErrorLogger.log(
        'Applying audio profile failed${rolledBack ? ' (rolled back)' : ' (rollback incomplete)'}',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
        meta: <String, dynamic>{
          'profileId': profile.id,
          'appliedKeys': applied.length,
        },
      );
      throw AudioProfileApplyError(
        code: e is _WriteRejected
            ? 'audio-profile-write-rejected'
            : 'audio-profile-apply-failed',
        userMessage: AudioProfileStrings.applyFailed,
        rolledBack: rolledBack,
        appliedKeys: List<String>.unmodifiable(applied),
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Reads a profile from the file at [path] and stores it as a new profile.
  ///
  /// A file that already uses a taken id is re-keyed, so importing the same
  /// profile twice keeps both copies.
  Future<AudioProfile> importFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw const AudioProfileStoreError(
          code: 'audio-profile-import-missing',
          userMessage: AudioProfileStrings.importMissing,
        );
      }
      final bytes = await file.readAsBytes();
      final profile = AudioProfile.decodeBytes(bytes);
      return await _persist(profile);
    } on AppError {
      rethrow;
    } catch (e, st) {
      ErrorLogger.log(
        'Importing audio profile failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
      );
      throw AudioProfileStoreError(
        code: 'audio-profile-import-failed',
        userMessage: AudioProfileStrings.importFailed,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes the profile whose id is [id]. Missing files are treated as done.
  Future<void> delete(String id) async {
    try {
      if (!_safeId.hasMatch(id)) {
        throw const AudioProfileStoreError(
          code: 'audio-profile-invalid-id',
          userMessage: AudioProfileStrings.formatInvalidId,
        );
      }
      final directory = await _directory(create: false);
      final file = File(p.join(directory.path, '$id.json'));
      if (await file.exists()) await file.delete();
    } on AppError {
      rethrow;
    } catch (e, st) {
      ErrorLogger.log(
        'Deleting audio profile failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
        meta: <String, dynamic>{'profileId': id},
      );
      throw AudioProfileStoreError(
        code: 'audio-profile-delete-failed',
        userMessage: AudioProfileStrings.deleteFailed,
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Writes one preference value and reports whether the setter accepted it.
  ///
  /// Public so tests can subclass the service and reject a single key to drive
  /// the rollback path; production code only calls it from [apply].
  @visibleForTesting
  Future<bool> writeKeyValue(String key, Object? value) async {
    if (value is bool) return _prefs.setBool(key, value);
    if (value is int) return _prefs.setInt(key, value);
    if (value is double) return _prefs.setDouble(key, value);
    if (value is String) return _prefs.setString(key, value);
    if (value is List<String>) return _prefs.setStringList(key, value);
    return false;
  }

  Future<AudioProfile> _persist(AudioProfile profile) async {
    try {
      final directory = await _directory();
      var target = profile;
      var file = File(p.join(directory.path, '${target.id}.json'));
      if (await file.exists()) {
        target = profile.withId(_newId());
        file = File(p.join(directory.path, '${target.id}.json'));
      }
      await file.writeAsString(target.toJsonString(), flush: true);
      return target;
    } catch (e, st) {
      ErrorLogger.log(
        'Saving audio profile failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
        meta: <String, dynamic>{'profileId': profile.id},
      );
      throw AudioProfileStoreError(
        code: 'audio-profile-save-failed',
        userMessage: AudioProfileStrings.storeFailed,
        cause: e,
        stackTrace: st,
      );
    }
  }

  Future<AudioProfile> _readProfile(File file) async {
    final length = await file.length();
    if (length > AudioProfile.maxFileBytes) {
      throw const ProfileFormatError(
        code: 'audio-profile-too-large',
        userMessage: AudioProfileStrings.formatTooLarge,
      );
    }
    return AudioProfile.decodeBytes(await file.readAsBytes());
  }

  Future<bool> _restore(Map<String, Object?> snapshot) async {
    var restored = true;
    for (final entry in snapshot.entries) {
      final value = entry.value;
      try {
        final written = value == null
            ? await _prefs.remove(entry.key)
            : await writeKeyValue(entry.key, value);
        if (!written) restored = false;
      } catch (e, st) {
        restored = false;
        ErrorLogger.log(
          'Restoring an audio setting failed during rollback',
          error: e,
          stackTrace: st,
          category: 'AudioProfileService',
          meta: <String, dynamic>{'key': entry.key},
        );
      }
    }
    return restored;
  }

  Future<Directory> _directory({
    bool create = true,
    bool backups = false,
  }) async {
    final root = await _rootDirectory();
    var path = p.join(root.path, directoryName);
    if (backups) path = p.join(path, backupDirectoryName);
    final directory = Directory(path);
    if (create && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _newId() {
    final stamp = _clock().microsecondsSinceEpoch.toRadixString(36);
    final salt = _random.nextInt(0x7fffffff).toRadixString(36);
    return 'ap_${stamp}_$salt';
  }

  String _exportFileName(AudioProfile profile) {
    final slug = profile.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final trimmed = slug.length > 40 ? slug.substring(0, 40) : slug;
    final prefix = trimmed.isEmpty ? 'profile' : trimmed;
    return 'pulsr-$prefix-${profile.id}.json';
  }
}

/// Internal marker for "the preference setter refused this key".
class _WriteRejected implements Exception {
  const _WriteRejected(this.key);

  final String key;

  @override
  String toString() => 'Preference setter rejected "$key"';
}

/// Writes and prunes the automatic pre-apply snapshot files.
class _ProfileBackups {
  _ProfileBackups({required this.directory, required this.clock});

  final Future<Directory> Function() directory;
  final DateTime Function() clock;

  Future<bool> save(AudioProfile backup) async {
    try {
      final target = await directory();
      final stamp =
          clock().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File(p.join(target.path, 'pre_apply_$stamp.json'));
      await file.writeAsString(backup.toJsonString(), flush: true);
      await _prune(target);
      return true;
    } catch (e, st) {
      ErrorLogger.log(
        'Writing the pre-apply profile backup failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
      );
      return false;
    }
  }

  Future<void> _prune(Directory target) async {
    try {
      final files = <File>[];
      await for (final entity in target.list()) {
        if (entity is File && entity.path.endsWith('.json')) files.add(entity);
      }
      const limit = AudioProfileService.maxBackups;
      if (files.length <= limit) return;
      final dated = <MapEntry<DateTime, File>>[];
      for (final file in files) {
        dated.add(MapEntry(await file.lastModified(), file));
      }
      dated.sort((a, b) => a.key.compareTo(b.key));
      for (final entry in dated.take(dated.length - limit)) {
        await entry.value.delete();
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Pruning old profile backups failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
      );
    }
  }
}
