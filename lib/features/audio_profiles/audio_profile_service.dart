// lib/features/audio_profiles/audio_profile_service.dart
//
// File-backed store for shareable audio profiles plus the only code path that
// writes a profile into the live audio settings. Each apply takes a snapshot
// first, keeps a durable backup of it, and restores the snapshot when any key
// fails to write. A successful apply, rollback or import refreshes the live
// settings (SettingsCubit) and re-pushes the DSP effect state so the UI and the
// audio engine see the new values without an app restart.

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mutex/mutex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/di/injection.dart';
import '../../core/errors/app_error.dart';
import '../../core/utils/error_logger.dart';
import '../../data/audio/equalizer_manager.dart';
import '../settings/cubit/settings_cubit.dart';
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

/// Per-key outcome of [AudioProfileService.apply].
enum AudioProfileApplyStatus { applied, skipped, failed }

/// Raised when [AudioProfileService.apply] could not write every setting.
///
/// [rolledBack] reports whether the pre-apply snapshot was restored and
/// [results] carries the per-key outcome, so the caller can show exactly which
/// settings failed instead of a single aggregate count.
class AudioProfileApplyError extends AppError {
  const AudioProfileApplyError({
    required super.code,
    required super.userMessage,
    this.rolledBack = false,
    this.results = const <String, AudioProfileApplyStatus>{},
    this.liveStateRefreshed = false,
    super.cause,
    super.stackTrace,
  });

  /// Whether the previous settings were restored.
  final bool rolledBack;

  /// Outcome of every key the profile carried.
  final Map<String, AudioProfileApplyStatus> results;

  /// Whether the live settings/effects were refreshed after the rollback.
  final bool liveStateRefreshed;

  /// Keys written before the snapshot was restored (see [rolledBack]).
  List<String> get appliedKeys => _keysWith(AudioProfileApplyStatus.applied);

  /// Keys the preference setter refused.
  List<String> get failedKeys => _keysWith(AudioProfileApplyStatus.failed);

  /// Keys outside [AudioProfileKeys.whitelist].
  List<String> get skippedKeys => _keysWith(AudioProfileApplyStatus.skipped);

  /// Status recorded for [key], or `null` when the profile did not carry it.
  AudioProfileApplyStatus? statusOf(String key) => results[key];

  List<String> _keysWith(AudioProfileApplyStatus status) =>
      List<String>.unmodifiable(
        results.entries
            .where((entry) => entry.value == status)
            .map((entry) => entry.key),
      );
}

/// Outcome of a successful [AudioProfileService.apply].
class AudioProfileApplyReport {
  AudioProfileApplyReport({
    required Map<String, AudioProfileApplyStatus> results,
    required this.backupSaved,
    this.liveStateRefreshed = true,
  }) : results = Map<String, AudioProfileApplyStatus>.unmodifiable(results);

  /// Outcome of every key the profile carried.
  final Map<String, AudioProfileApplyStatus> results;

  /// Whether the durable pre-apply backup was written.
  final bool backupSaved;

  /// Whether the live settings and effect state were refreshed.
  final bool liveStateRefreshed;

  /// Number of settings written to shared preferences.
  int get appliedCount => appliedKeys.length;

  /// Keys written to shared preferences.
  List<String> get appliedKeys => _keysWith(AudioProfileApplyStatus.applied);

  /// Profile keys that are outside [AudioProfileKeys.whitelist].
  List<String> get skippedKeys => _keysWith(AudioProfileApplyStatus.skipped);

  /// Keys the preference setter refused.
  List<String> get failedKeys => _keysWith(AudioProfileApplyStatus.failed);

  /// Status recorded for [key], or `null` when the profile did not carry it.
  AudioProfileApplyStatus? statusOf(String key) => results[key];

  List<String> _keysWith(AudioProfileApplyStatus status) =>
      List<String>.unmodifiable(
        results.entries
            .where((entry) => entry.value == status)
            .map((entry) => entry.key),
      );
}

/// Captures, stores, exports and applies [AudioProfile]s.
class AudioProfileService {
  AudioProfileService({
    required SharedPreferences prefs,
    Future<Directory> Function()? rootDirectory,
    String Function()? appVersion,
    DateTime Function()? clock,
    Future<void> Function()? reloadSettings,
    Future<void> Function()? resyncEffects,
  })  : _prefs = prefs,
        _rootDirectory = rootDirectory ?? getApplicationSupportDirectory,
        _appVersion = appVersion ?? (() => AppConfig.appVersion),
        _clock = clock ?? DateTime.now,
        _reloadSettings = reloadSettings ?? _defaultReloadSettings,
        _resyncEffects = resyncEffects ?? _defaultResyncEffects;

  /// Folder under the app support directory that holds the profile files.
  static const String directoryName = 'audio_profiles';

  /// Sub-folder that holds the automatic pre-apply backups.
  static const String backupDirectoryName = 'backups';

  /// Preference key holding the id of the profile marked as the default.
  ///
  /// This is scheduler metadata, not a profile setting, so it is deliberately
  /// kept outside [AudioProfileKeys.whitelist].
  static const String defaultProfileKey = 'audio_profile_default_id';

  /// How many pre-apply backups are kept; older ones are pruned.
  static const int maxBackups = 10;

  /// Preference key remembering the last automatic default-profile
  /// application as `<profileId>@<deviceKey>`.
  ///
  /// Scheduler metadata like [defaultProfileKey], deliberately not a profile
  /// setting: it exists so a settings refresh or a repeated device event cannot
  /// re-apply the same profile forever.
  static const String lastAppliedProfileKey = 'audio_profile_last_applied';

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,80}$');
  static final Random _random = Random();

  final SharedPreferences _prefs;
  final Future<Directory> Function() _rootDirectory;
  final String Function() _appVersion;
  final DateTime Function() _clock;
  final Future<void> Function() _reloadSettings;
  final Future<void> Function() _resyncEffects;

  /// Temporary export folders created by [export] and not cleaned up yet.
  final Set<String> _pendingExports = <String>{};
  final Mutex _mutex = Mutex();

  late final _ProfileBackups _backups = _ProfileBackups(
    directory: () => _directory(backups: true),
    clock: _clock,
  );

  /// Default live-state hooks: every guard is optional because tests and early
  /// navigation can run without the app-level singletons.
  static Future<void> _defaultReloadSettings() async {
    if (!getIt.isRegistered<SettingsCubit>()) return;
    await getIt<SettingsCubit>().reloadSettings();
  }

  static Future<void> _defaultResyncEffects() async {
    if (!getIt.isRegistered<EqualizerManager>()) return;
    await getIt<EqualizerManager>().reloadFromPreferences();
  }

  /// Id of the profile marked as the device default, if any.
  String? get defaultProfileId {
    final id = _prefs.getString(defaultProfileKey);
    return id != null && _safeId.hasMatch(id) ? id : null;
  }

  /// Marks [profileId] as the default profile; `null` clears the selection.
  ///
  /// Returns `false` when [profileId] is not a saved profile (the preference is
  /// left untouched), and throws [AudioProfileStoreError] for an unsafe id.
  Future<bool> setGlobalDefaults(String? profileId) =>
      _mutex.protect(() => _setGlobalDefaultsUnlocked(profileId));

  Future<bool> _setGlobalDefaultsUnlocked(String? profileId) async {
    if (profileId == null) {
      // Changing the default frees the scheduler marker so the next matching
      // event (startup or attach) can act on the new selection immediately.
      await clearLastAppliedMarker();
      return _prefs.remove(defaultProfileKey);
    }
    if (!_safeId.hasMatch(profileId)) {
      throw AudioProfileStoreError(
        code: 'audio-profile-invalid-id',
        userMessage: AudioProfileStrings.formatInvalidId,
      );
    }
    final directory = await _directory(create: false);
    final file = File(p.join(directory.path, '$profileId.json'));
    if (!await file.exists()) return false;
    final saved = await _prefs.setString(defaultProfileKey, profileId);
    if (saved) await clearLastAppliedMarker();
    return saved;
  }

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
  }) =>
      _mutex.protect(() => _captureCurrentUnlocked(
            name,
            deviceVid: deviceVid,
            devicePid: devicePid,
            deviceName: deviceName,
          ));

  Future<AudioProfile> _captureCurrentUnlocked(
    String name, {
    int? deviceVid,
    int? devicePid,
    String? deviceName,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw AudioProfileStoreError(
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
  ///
  /// The returned file lives in a private temp folder that is tracked by this
  /// service; call [cleanupExport] once sharing finishes. User-chosen files
  /// (imports/backups) are never touched by that cleanup.
  Future<File> export(AudioProfile profile) async {
    Directory? directory;
    try {
      directory = await Directory.systemTemp.createTemp('pulsr_audio_profile_');
      _pendingExports.add(p.canonicalize(directory.path));
      final file = File(p.join(directory.path, _exportFileName(profile)));
      await file.writeAsString(profile.toJsonString(), flush: true);
      return file;
    } catch (e, st) {
      if (directory != null) {
        _pendingExports.remove(p.canonicalize(directory.path));
        try {
          await directory.delete(recursive: true);
        } catch (_) {
          // Best effort: the temp folder may already be gone.
        }
      }
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

  /// Deletes the temporary folder that [export] created for [file].
  ///
  /// Returns `true` when a tracked export folder was removed. Anything that was
  /// not produced by [export] (for example a user-selected import or backup
  /// file) is left untouched.
  Future<bool> cleanupExport(File file) async {
    final key = p.canonicalize(file.parent.path);
    if (!_pendingExports.remove(key)) return false;
    try {
      if (await file.parent.exists()) {
        await file.parent.delete(recursive: true);
      }
      return true;
    } catch (e, st) {
      ErrorLogger.log(
        'Cleaning up an exported audio profile failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
        meta: <String, dynamic>{'file': p.basename(file.path)},
      );
      return false;
    }
  }

  /// Applies [profile] to the live settings.
  ///
  /// Only keys inside [AudioProfileKeys.whitelist] are written; anything else
  /// is reported as [AudioProfileApplyStatus.skipped]. The current values are
  /// snapshotted (and backed up as a file) before the first write. Every key is
  /// attempted and its individual outcome is reported; if any write fails the
  /// snapshot is restored and [AudioProfileApplyError.results] carries the
  /// per-key status.
  Future<AudioProfileApplyReport> apply(AudioProfile profile) =>
      _mutex.protect(() => _applyUnlocked(profile));

  Future<AudioProfileApplyReport> _applyUnlocked(AudioProfile profile) async {
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

    final results = <String, AudioProfileApplyStatus>{};
    Object? firstFailure;
    StackTrace? firstStackTrace;
    for (final entry in profile.values.entries) {
      if (!AudioProfileKeys.isWhitelisted(entry.key)) {
        results[entry.key] = AudioProfileApplyStatus.skipped;
        continue;
      }
      try {
        final written = await writeKeyValue(entry.key, entry.value);
        results[entry.key] = written
            ? AudioProfileApplyStatus.applied
            : AudioProfileApplyStatus.failed;
        if (!written) {
          firstFailure ??= _WriteRejected(entry.key);
        }
      } catch (e, st) {
        results[entry.key] = AudioProfileApplyStatus.failed;
        firstFailure ??= e;
        firstStackTrace ??= st;
        ErrorLogger.log(
          'Writing an audio setting failed',
          error: e,
          stackTrace: st,
          category: 'AudioProfileService',
          meta: <String, dynamic>{'key': entry.key},
        );
      }
    }

    final applied = results.values
        .where((status) => status == AudioProfileApplyStatus.applied)
        .length;
    final failed = results.values
        .where((status) => status == AudioProfileApplyStatus.failed)
        .length;

    if (failed > 0) {
      final rolledBack = await _restore(snapshot);
      final refreshed = await _refreshLiveState();
      ErrorLogger.log(
        'Applying audio profile failed${rolledBack ? ' (rolled back)' : ' (rollback incomplete)'}',
        error: firstFailure,
        stackTrace: firstStackTrace,
        category: 'AudioProfileService',
        meta: <String, dynamic>{
          'profileId': profile.id,
          'appliedKeys': applied,
          'failedKeys': failed,
        },
      );
      throw AudioProfileApplyError(
        code: firstFailure is _WriteRejected
            ? 'audio-profile-write-rejected'
            : 'audio-profile-apply-failed',
        userMessage: rolledBack
            ? AudioProfileStrings.applyFailedRolledBack(failed)
            : AudioProfileStrings.applyFailedRollbackIncomplete(failed),
        rolledBack: rolledBack,
        results: Map<String, AudioProfileApplyStatus>.unmodifiable(results),
        liveStateRefreshed: refreshed,
        cause: firstFailure,
        stackTrace: firstStackTrace,
      );
    }

    final refreshed = await _refreshLiveState();
    return AudioProfileApplyReport(
      results: results,
      backupSaved: backupSaved,
      liveStateRefreshed: refreshed,
    );
  }

  /// Reads a profile from the file at [path] and stores it as a new profile.
  ///
  /// A file that already uses a taken id is re-keyed, so importing the same
  /// profile twice keeps both copies. Settings that are not whitelisted or
  /// carry corrupt values are dropped (see [AudioProfile.ignoredKeys]); the
  /// live settings are refreshed after a successful import.
  Future<AudioProfile> importFromFile(String path) =>
      _mutex.protect(() => _importFromFileUnlocked(path));

  Future<AudioProfile> _importFromFileUnlocked(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw AudioProfileStoreError(
          code: 'audio-profile-import-missing',
          userMessage: AudioProfileStrings.importMissing,
        );
      }
      final profile = await _readProfile(file);
      final stored = await _persist(profile);
      await _refreshLiveState();
      return stored;
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

  /// Reads a saved profile from its file, or `null` when the file is gone.
  ///
  /// Unlike [list] this addresses one id directly, so the startup scheduler
  /// does not have to enumerate every profile to find its default.
  Future<AudioProfile?> profileById(String id) async {
    if (!_safeId.hasMatch(id)) return null;
    final directory = await _directory(create: false);
    final file = File(p.join(directory.path, '$id.json'));
    if (!await file.exists()) return null;
    try {
      return await _readProfile(file);
    } catch (e, st) {
      ErrorLogger.log(
        'Reading the default audio profile failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
        meta: <String, dynamic>{'profileId': id},
      );
      return null;
    }
  }

  /// Whether [profile] targets the device described by [deviceVid]/[devicePid].
  ///
  /// A profile without a device pin applies everywhere. A pinned profile needs
  /// a device to compare against and must match every id it pins.
  static bool profileMatchesDevice(
    AudioProfile profile, {
    int? deviceVid,
    int? devicePid,
  }) {
    final pinnedVid = profile.deviceVid;
    final pinnedPid = profile.devicePid;
    if (pinnedVid == null && pinnedPid == null) return true;
    if (deviceVid == null && devicePid == null) return false;
    if (pinnedVid != null && pinnedVid != deviceVid) return false;
    if (pinnedPid != null && pinnedPid != devicePid) return false;
    return true;
  }

  /// Applies the profile marked with [setGlobalDefaults] when the device fits.
  ///
  /// Called once at startup ([startup] true) and again when a USB DAC is
  /// attached. The last application is remembered in
  /// [lastAppliedProfileKey] keyed by profile + device, so a settings reload or
  /// a duplicate attach event is a no-op instead of an apply loop. Returns the
  /// report, or `null` when there was nothing to do.
  Future<AudioProfileApplyReport?> applyDefaultProfile({
    bool startup = false,
    int? deviceVid,
    int? devicePid,
    String? deviceKey,
  }) =>
      _mutex.protect(() => _applyDefaultProfileUnlocked(
            startup: startup,
            deviceVid: deviceVid,
            devicePid: devicePid,
            deviceKey: deviceKey,
          ));

  Future<AudioProfileApplyReport?> _applyDefaultProfileUnlocked({
    bool startup = false,
    int? deviceVid,
    int? devicePid,
    String? deviceKey,
  }) async {
    final id = defaultProfileId;
    if (id == null) return null;
    final resolvedDeviceKey = deviceKey ?? (startup ? 'startup' : 'device');
    final marker = '$id@$resolvedDeviceKey';
    if (_prefs.getString(lastAppliedProfileKey) == marker) return null;

    final profile = await profileById(id);
    if (profile == null) {
      ErrorLogger.log(
        'Default audio profile is missing; nothing applied',
        category: 'AudioProfileService',
        meta: <String, dynamic>{'profileId': id},
      );
      return null;
    }
    if (!profileMatchesDevice(
      profile,
      deviceVid: deviceVid,
      devicePid: devicePid,
    )) {
      ErrorLogger.addBreadcrumb(
        'Default audio profile skipped: attached device does not match',
        category: 'audio_profiles',
      );
      return null;
    }

    final report = await _applyUnlocked(profile);
    // Only a completed apply marks the marker: a rolled-back apply must be
    // retried on the next event instead of being treated as done.
    await _prefs.setString(lastAppliedProfileKey, marker);
    return report;
  }

  /// Clears the automatic-apply marker so the next matching event applies the
  /// default profile again (used when the user changes which profile is the
  /// default, or detaches the device).
  Future<void> clearLastAppliedMarker() =>
      _prefs.remove(lastAppliedProfileKey);

  /// Deletes the profile whose id is [id]. Missing files are treated as done.
  ///
  /// Deleting the profile that is currently marked as the default also clears
  /// the default selection so it can never point at a missing file.
  Future<void> delete(String id) =>
      _mutex.protect(() => _deleteUnlocked(id));

  Future<void> _deleteUnlocked(String id) async {
    try {
      if (!_safeId.hasMatch(id)) {
        throw AudioProfileStoreError(
          code: 'audio-profile-invalid-id',
          userMessage: AudioProfileStrings.formatInvalidId,
        );
      }
      final directory = await _directory(create: false);
      final file = File(p.join(directory.path, '$id.json'));
      if (await file.exists()) await file.delete();
      if (defaultProfileId == id) {
        await _prefs.remove(defaultProfileKey);
      }
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

  /// Reloads the settings state and re-pushes the effect state to the live
  /// audio session. Both hooks are best-effort: a failure is logged and
  /// reported through the returned flag, never through the profile write.
  Future<bool> _refreshLiveState() async {
    var refreshed = true;
    try {
      await _resyncEffects();
    } catch (e, st) {
      refreshed = false;
      ErrorLogger.log(
        'Resyncing audio effects after an audio profile change failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
      );
    }
    try {
      await _reloadSettings();
    } catch (e, st) {
      refreshed = false;
      ErrorLogger.log(
        'Reloading settings after an audio profile change failed',
        error: e,
        stackTrace: st,
        category: 'AudioProfileService',
      );
    }
    return refreshed;
  }

  Future<AudioProfile> _persist(AudioProfile profile) async {
    try {
      final directory = await _directory();
      var target = profile;
      if (!AudioProfile.isValidId(target.id)) {
        target = profile.withId(_newId());
      }
      var file = File(p.join(directory.path, '${target.id}.json'));
      if (await file.exists()) {
        target = target.withId(_newId());
        file = File(p.join(directory.path, '${target.id}.json'));
      }
      final tempFile = File(p.join(directory.path, '${target.id}.json.tmp'));
      await tempFile.writeAsString(target.toJsonString(), flush: true);
      try {
        await tempFile.rename(file.path);
      } on FileSystemException {
        if (await file.exists()) {
          await file.delete();
        }
        await tempFile.rename(file.path);
      }
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
      throw ProfileFormatError(
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
