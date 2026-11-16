// lib/features/diagnostics/safe_mode_controller.dart
//
// Consecutive output-failure tracking per device. The controller is a pure
// state machine over injected SharedPreferences: record failures, decide when a
// device should fall back, then disable the risky output path explicitly. It
// never touches the audio engine, so it can be unit-tested without a device.

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/prefs_keys.dart';
import '../../core/errors/app_error.dart';
import '../../core/utils/error_logger.dart';
import 'diagnostics_strings.dart';

/// Reloads the settings surfaces after safe mode changes persisted prefs.
typedef SafeModeSettingsReloader = Future<void> Function();

/// What happened to a device's consecutive-failure counter.
enum SafeModeEventType {
  /// A failure was recorded below the threshold.
  failure,

  /// A success cleared a non-zero counter.
  recovery,

  /// The failure count reached [SafeModeController.failureThreshold].
  thresholdReached,

  /// The fallback switched the risky output path off.
  fallbackApplied,

  /// The device's safe-mode state was cleared.
  reset,
}

/// One state transition of [SafeModeController].
class SafeModeEvent {
  const SafeModeEvent({
    required this.deviceKey,
    required this.type,
    required this.consecutiveFailures,
    this.reason,
    this.description,
  });

  /// Normalized device key the transition belongs to.
  final String deviceKey;

  /// Kind of transition.
  final SafeModeEventType type;

  /// Failure count after the transition.
  final int consecutiveFailures;

  /// Failure reason for [SafeModeEventType.failure] events.
  final String? reason;

  /// Human description for [SafeModeEventType.fallbackApplied] events.
  final String? description;

  @override
  String toString() =>
      'SafeModeEvent($deviceKey, ${type.name}, failures: $consecutiveFailures)';
}

/// Raised when the safe-mode state cannot be persisted.
class SafeModeError extends AppError {
  const SafeModeError({
    required super.code,
    required super.userMessage,
    super.cause,
    super.stackTrace,
  });
}

/// Tracks consecutive sink failures per device and applies a conservative
/// fallback once one device fails [failureThreshold] times in a row.
class SafeModeController {
  SafeModeController({
    required SharedPreferences prefs,
    DateTime Function()? clock,
    SafeModeSettingsReloader? reloadSettings,
  })  : _prefs = prefs,
        _clock = clock ?? DateTime.now,
        _reloadSettings = reloadSettings;

  /// Consecutive failures that trigger [shouldFallback] and the fallback prompt.
  static const int failureThreshold = 3;

  /// Prefix shared by every preference this controller owns.
  static const String keyPrefix = 'safe_mode_';

  /// App-wide reloader installed by the audio handler.
  ///
  /// Controllers constructed by a screen without their own reloader still
  /// refresh SettingsCubit after apply/reset, so the settings UI never shows a
  /// stale AAudio/USB/DSD value.
  static SafeModeSettingsReloader? defaultReloader;

  /// Global playback preferences [applyFallback] rewrites and [reset] restores.
  static const List<String> managedPreferenceKeys = <String>[
    PrefsKeys.aaudioOutputEnabled,
    PrefsKeys.usbHardwareVolumeEnabled,
    PrefsKeys.dsdOutputMode,
    PrefsKeys.strictBitPerfect,
  ];

  final SharedPreferences _prefs;
  final DateTime Function() _clock;
  final SafeModeSettingsReloader? _reloadSettings;
  final StreamController<SafeModeEvent> _events =
      StreamController<SafeModeEvent>.broadcast();

  /// Broadcast stream of state transitions.
  Stream<SafeModeEvent> get events => _events.stream;

  /// Normalizes a raw device label into a stable preference-key fragment.
  static String normalizeDeviceKey(String deviceKey) {
    final cleaned = deviceKey
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (cleaned.isEmpty) return 'default';
    return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  }

  /// Preference key holding the consecutive-failure count for [deviceKey].
  static String failuresKey(String deviceKey) =>
      '${keyPrefix}failures_${normalizeDeviceKey(deviceKey)}';

  /// Preference key marking that the fallback ran for [deviceKey].
  static String activeKey(String deviceKey) =>
      '${keyPrefix}active_${normalizeDeviceKey(deviceKey)}';

  /// Preference key holding the last failure reason for [deviceKey].
  static String reasonKey(String deviceKey) =>
      '${keyPrefix}reason_${normalizeDeviceKey(deviceKey)}';

  /// Preference key holding when [deviceKey] last changed state.
  static String updatedKey(String deviceKey) =>
      '${keyPrefix}updated_${normalizeDeviceKey(deviceKey)}';

  /// Preference key holding the pre-fallback values for [deviceKey].
  ///
  /// Kept as a JSON map so [reset] can put the user's AAudio / USB volume / DSD
  /// / bit-perfect choices back exactly as they were before the fallback.
  static String snapshotKey(String deviceKey) =>
      '${keyPrefix}snapshot_${normalizeDeviceKey(deviceKey)}';

  /// Consecutive failures recorded for [deviceKey].
  int consecutiveFailures(String deviceKey) =>
      _prefs.getInt(failuresKey(deviceKey)) ?? 0;

  /// Whether [deviceKey] has reached [failureThreshold] consecutive failures.
  bool shouldFallback(String deviceKey) =>
      consecutiveFailures(deviceKey) >= failureThreshold;

  /// Whether the fallback has already been applied for [deviceKey].
  bool isFallbackActive(String deviceKey) =>
      _prefs.getBool(activeKey(deviceKey)) ?? false;

  /// Reason stored by the most recent failure, if any.
  String? lastFailureReason(String deviceKey) {
    final reason = _prefs.getString(reasonKey(deviceKey));
    if (reason == null || reason.trim().isEmpty) return null;
    return reason;
  }

  /// Records one sink failure for [deviceKey] and emits the transition.
  Future<void> recordFailure(String deviceKey, String reason) async {
    final key = normalizeDeviceKey(deviceKey);
    final next = consecutiveFailures(key) + 1;
    final saved = await _writeState(
      key,
      failures: next,
      reason: _truncateReason(reason),
    );
    if (!saved) {
      throw const SafeModeError(
        code: 'safe-mode-record-failed',
        userMessage: DiagnosticsStrings.safeModePersistFailed,
      );
    }
    _emit(
      SafeModeEvent(
        deviceKey: key,
        type: next >= failureThreshold
            ? SafeModeEventType.thresholdReached
            : SafeModeEventType.failure,
        consecutiveFailures: next,
        reason: _truncateReason(reason),
      ),
    );
  }

  /// Clears the consecutive-failure counter after a healthy run.
  Future<void> recordSuccess(String deviceKey) async {
    final key = normalizeDeviceKey(deviceKey);
    final previous = consecutiveFailures(key);
    if (previous == 0) return;
    final removed = await _removeKeys(<String>[failuresKey(key)]);
    if (!removed) {
      throw const SafeModeError(
        code: 'safe-mode-record-success-failed',
        userMessage: DiagnosticsStrings.safeModePersistFailed,
      );
    }
    _emit(
      SafeModeEvent(
        deviceKey: key,
        type: SafeModeEventType.recovery,
        consecutiveFailures: 0,
      ),
    );
  }

  /// Disables the risky output path for [deviceKey] and returns a description
  /// of what changed.
  ///
  /// AAudio direct output, USB hardware volume and strict bit-perfect are
  /// turned off, and DSD output falls back to PCM. The values that were active
  /// before the first fallback are snapshotted so [reset] can restore them.
  /// Idempotent: running it twice leaves the same settings and never replaces
  /// the original snapshot.
  Future<String> applyFallback(String deviceKey) async {
    final key = normalizeDeviceKey(deviceKey);
    final label = deviceKey.trim().isEmpty ? key : deviceKey.trim();
    final failures = consecutiveFailures(key);
    final description =
        DiagnosticsStrings.safeModeFallbackDescription(label, failures);
    try {
      // Never change global settings without a snapshot: reset must always be
      // able to undo the fallback.
      final captured = await _captureSnapshotIfNeeded(key);
      if (!captured) {
        throw const SafeModeError(
          code: 'safe-mode-snapshot-failed',
          userMessage: DiagnosticsStrings.safeModePersistFailed,
        );
      }
      var saved = await _prefs.setBool(PrefsKeys.aaudioOutputEnabled, false);
      saved = await _prefs.setBool(PrefsKeys.usbHardwareVolumeEnabled, false) &&
          saved;
      saved = await _prefs.setString(PrefsKeys.dsdOutputMode, 'pcm') && saved;
      saved = await _prefs.setBool(PrefsKeys.strictBitPerfect, false) && saved;
      saved = await _prefs.setBool(activeKey(key), true) && saved;
      saved = await _prefs.setString(
            updatedKey(key),
            _clock().toUtc().toIso8601String(),
          ) &&
          saved;
      if (!saved) {
        throw const SafeModeError(
          code: 'safe-mode-write-rejected',
          userMessage: DiagnosticsStrings.safeModePersistFailed,
        );
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Applying the safe-mode fallback failed',
        error: e,
        stackTrace: st,
        category: 'SafeModeController',
        meta: <String, dynamic>{'device': key},
      );
      if (e is SafeModeError) rethrow;
      throw SafeModeError(
        code: 'safe-mode-apply-failed',
        userMessage: DiagnosticsStrings.safeModePersistFailed,
        cause: e,
        stackTrace: st,
      );
    }
    await _notifySettingsChanged();
    _emit(
      SafeModeEvent(
        deviceKey: key,
        type: SafeModeEventType.fallbackApplied,
        consecutiveFailures: failures,
        description: description,
      ),
    );
    return description;
  }

  /// Clears every safe-mode record for [deviceKey] and restores the pre-fallback
  /// values captured by [applyFallback].
  Future<void> reset(String deviceKey) async {
    final key = normalizeDeviceKey(deviceKey);
    var removed = await _restoreSnapshot(key);
    removed = await _removeKeys(<String>[
          failuresKey(key),
          activeKey(key),
          reasonKey(key),
          updatedKey(key),
          snapshotKey(key),
        ]) &&
        removed;
    if (!removed) {
      throw const SafeModeError(
        code: 'safe-mode-reset-failed',
        userMessage: DiagnosticsStrings.safeModePersistFailed,
      );
    }
    await _notifySettingsChanged();
    _emit(
      SafeModeEvent(
        deviceKey: key,
        type: SafeModeEventType.reset,
        consecutiveFailures: 0,
      ),
    );
  }

  /// Closes the event stream.
  Future<void> dispose() async {
    await _events.close();
  }

  Future<bool> _captureSnapshotIfNeeded(String key) async {
    if (_prefs.containsKey(snapshotKey(key))) return true;
    final snapshot = <String, Object?>{
      for (final prefKey in managedPreferenceKeys) prefKey: _prefs.get(prefKey),
    };
    try {
      return await _prefs.setString(snapshotKey(key), jsonEncode(snapshot));
    } catch (e, st) {
      ErrorLogger.log(
        'Snapshotting pre-fallback settings failed',
        error: e,
        stackTrace: st,
        category: 'SafeModeController',
        meta: <String, dynamic>{'device': key},
      );
      return false;
    }
  }

  /// Puts the snapshotted values back. Returns false when a write failed.
  ///
  /// A missing or corrupt snapshot is not an error: the controller still clears
  /// its own state, the user simply keeps the fallback values.
  Future<bool> _restoreSnapshot(String key) async {
    final raw = _stringValue(snapshotKey(key));
    if (raw == null) return true;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e, st) {
      ErrorLogger.log(
        'Safe-mode snapshot is corrupt; keeping the fallback values',
        error: e,
        stackTrace: st,
        category: 'SafeModeController',
        meta: <String, dynamic>{'device': key},
      );
      return true;
    }
    if (decoded is! Map) return true;
    var saved = true;
    for (final prefKey in managedPreferenceKeys) {
      if (!decoded.containsKey(prefKey)) continue;
      final value = decoded[prefKey];
      if (value == null) {
        saved = await _prefs.remove(prefKey) && saved;
      } else if (value is bool) {
        saved = await _prefs.setBool(prefKey, value) && saved;
      } else if (value is String) {
        saved = await _prefs.setString(prefKey, value) && saved;
      }
    }
    return saved;
  }

  String? _stringValue(String key) {
    final value = _prefs.get(key);
    return value is String ? _prefs.getString(key) : null;
  }

  Future<void> _notifySettingsChanged() async {
    final reloader = _reloadSettings ?? SafeModeController.defaultReloader;
    if (reloader == null) return;
    try {
      await reloader();
    } catch (e, st) {
      ErrorLogger.log(
        'Reloading settings after a safe-mode change failed',
        error: e,
        stackTrace: st,
        category: 'SafeModeController',
      );
    }
  }

  Future<bool> _writeState(
    String key, {
    required int failures,
    required String reason,
  }) async {
    final wroteFailures = await _prefs.setInt(failuresKey(key), failures);
    final wroteReason = await _prefs.setString(reasonKey(key), reason);
    final wroteStamp = await _prefs.setString(
      updatedKey(key),
      _clock().toUtc().toIso8601String(),
    );
    return wroteFailures && wroteReason && wroteStamp;
  }

  Future<bool> _removeKeys(List<String> keys) async {
    var removed = true;
    for (final key in keys) {
      try {
        removed = await _prefs.remove(key) && removed;
      } catch (e, st) {
        ErrorLogger.log(
          'Removing a safe-mode preference failed',
          error: e,
          stackTrace: st,
          category: 'SafeModeController',
          meta: <String, dynamic>{'key': key},
        );
        return false;
      }
    }
    return removed;
  }

  String _truncateReason(String reason) {
    final singleLine = reason.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.isEmpty) return 'unknown';
    return singleLine.length > 200 ? singleLine.substring(0, 200) : singleLine;
  }

  void _emit(SafeModeEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }
}
