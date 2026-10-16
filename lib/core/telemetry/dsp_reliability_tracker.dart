// lib/core/telemetry/dsp_reliability_tracker.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class DspReliabilityCounters {
  final int nativeSetterRejection;
  final int bridgeTimeoutFailure;
  final int routeResyncFailure;
  final int sessionReattachFailure;
  final int autoDegradeActivation;
  final int autoDegradeRecovery;
  final String? lastRedactedError;
  final DateTime? lastErrorTimestamp;

  const DspReliabilityCounters({
    this.nativeSetterRejection = 0,
    this.bridgeTimeoutFailure = 0,
    this.routeResyncFailure = 0,
    this.sessionReattachFailure = 0,
    this.autoDegradeActivation = 0,
    this.autoDegradeRecovery = 0,
    this.lastRedactedError,
    this.lastErrorTimestamp,
  });

  const DspReliabilityCounters.zero()
      : nativeSetterRejection = 0,
        bridgeTimeoutFailure = 0,
        routeResyncFailure = 0,
        sessionReattachFailure = 0,
        autoDegradeActivation = 0,
        autoDegradeRecovery = 0,
        lastRedactedError = null,
        lastErrorTimestamp = null;

  static const int maxCounterValue = 1000000;

  static int _clamp(int val) => val.clamp(0, maxCounterValue);

  DspReliabilityCounters copyWith({
    int? nativeSetterRejection,
    int? bridgeTimeoutFailure,
    int? routeResyncFailure,
    int? sessionReattachFailure,
    int? autoDegradeActivation,
    int? autoDegradeRecovery,
    String? lastRedactedError,
    DateTime? lastErrorTimestamp,
  }) {
    return DspReliabilityCounters(
      nativeSetterRejection:
          _clamp(nativeSetterRejection ?? this.nativeSetterRejection),
      bridgeTimeoutFailure:
          _clamp(bridgeTimeoutFailure ?? this.bridgeTimeoutFailure),
      routeResyncFailure: _clamp(routeResyncFailure ?? this.routeResyncFailure),
      sessionReattachFailure:
          _clamp(sessionReattachFailure ?? this.sessionReattachFailure),
      autoDegradeActivation:
          _clamp(autoDegradeActivation ?? this.autoDegradeActivation),
      autoDegradeRecovery:
          _clamp(autoDegradeRecovery ?? this.autoDegradeRecovery),
      lastRedactedError: lastRedactedError ?? this.lastRedactedError,
      lastErrorTimestamp: lastErrorTimestamp ?? this.lastErrorTimestamp,
    );
  }

  Map<String, dynamic> toMap() => {
        'nativeSetterRejection': nativeSetterRejection,
        'bridgeTimeoutFailure': bridgeTimeoutFailure,
        'routeResyncFailure': routeResyncFailure,
        'sessionReattachFailure': sessionReattachFailure,
        'autoDegradeActivation': autoDegradeActivation,
        'autoDegradeRecovery': autoDegradeRecovery,
        'lastRedactedError': lastRedactedError,
        'lastErrorTimestamp': lastErrorTimestamp?.toIso8601String(),
      };

  factory DspReliabilityCounters.fromMap(Map<String, dynamic> map) {
    int parseInt(dynamic val) {
      if (val is num) return _clamp(val.toInt());
      return 0;
    }

    DateTime? parseDate(dynamic val) {
      if (val is String && val.isNotEmpty) {
        return DateTime.tryParse(val);
      }
      return null;
    }

    return DspReliabilityCounters(
      nativeSetterRejection: parseInt(map['nativeSetterRejection']),
      bridgeTimeoutFailure: parseInt(map['bridgeTimeoutFailure']),
      routeResyncFailure: parseInt(map['routeResyncFailure']),
      sessionReattachFailure: parseInt(map['sessionReattachFailure']),
      autoDegradeActivation: parseInt(map['autoDegradeActivation']),
      autoDegradeRecovery: parseInt(map['autoDegradeRecovery']),
      lastRedactedError: map['lastRedactedError'] as String?,
      lastErrorTimestamp: parseDate(map['lastErrorTimestamp']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DspReliabilityCounters &&
          runtimeType == other.runtimeType &&
          nativeSetterRejection == other.nativeSetterRejection &&
          bridgeTimeoutFailure == other.bridgeTimeoutFailure &&
          routeResyncFailure == other.routeResyncFailure &&
          sessionReattachFailure == other.sessionReattachFailure &&
          autoDegradeActivation == other.autoDegradeActivation &&
          autoDegradeRecovery == other.autoDegradeRecovery &&
          lastRedactedError == other.lastRedactedError &&
          lastErrorTimestamp == other.lastErrorTimestamp;

  @override
  int get hashCode => Object.hash(
        nativeSetterRejection,
        bridgeTimeoutFailure,
        routeResyncFailure,
        sessionReattachFailure,
        autoDegradeActivation,
        autoDegradeRecovery,
        lastRedactedError,
        lastErrorTimestamp,
      );
}

/// Persistent, privacy-safe reliability tracker for DSP operations.
class DspReliabilityTracker {
  static const String prefsKey = 'dsp_reliability_counters_v1';

  static DspReliabilityTracker? _instance;
  static DspReliabilityTracker get instance =>
      _instance ??= DspReliabilityTracker._internal();

  DspReliabilityTracker._internal() {
    _loadFromPrefs();
  }

  @visibleForTesting
  static void resetInstanceForTesting() {
    _instance = null;
  }

  DspReliabilityCounters _counters = const DspReliabilityCounters.zero();
  final StreamController<DspReliabilityCounters> _streamController =
      StreamController<DspReliabilityCounters>.broadcast();

  DspReliabilityCounters get counters => _counters;
  Stream<DspReliabilityCounters> get stream => _streamController.stream;
  bool get isInitialized => _initialized;

  bool _initialized = false;
  Future<void>? _initFuture;

  Future<void> ensureInitialized() {
    return _initFuture ??= _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _counters = DspReliabilityCounters.fromMap(decoded);
        } else if (decoded is Map) {
          _counters = DspReliabilityCounters.fromMap(
              Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {
      // Corrupt preferences must fail safely to zero
      _counters = const DspReliabilityCounters.zero();
    } finally {
      _initialized = true;
      if (!_streamController.isClosed) {
        _streamController.add(_counters);
      }
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode(_counters.toMap()));
    } catch (_) {
      // Non-fatal persistence failure
    }
  }

  /// Sanitizes sensitive information (paths, credentials, tokens) from error strings.
  static String redactErrorMessage(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    return raw
        .replaceAll(
            RegExp(r'(/data/user/\d+/[^"\s\\]+)'), '[REDACTED_APP_PATH]')
        .replaceAll(RegExp(r'(/storage/emulated/\d+/[^"\s\\]+)'),
            '[REDACTED_STORAGE_PATH]')
        .replaceAll(RegExp(r'([A-Za-z]:\\[^"\s]+)'), '[REDACTED_LOCAL_PATH]')
        .replaceAll(RegExp(r'(/home/[^/\s]+/[^\s]+)'), '[REDACTED_USER_PATH]')
        .replaceAllMapped(
            RegExp(r'(key|token|secret|password|auth|bearer)=[^&\s]+',
                caseSensitive: false),
            (m) => '${m[1]}=[REDACTED]')
        .trim();
  }

  void recordNativeSetterRejection(String method, [dynamic error]) {
    final redacted = redactErrorMessage(
        'Native setter $method rejected${error != null ? ': $error' : ''}');
    _counters = _counters.copyWith(
      nativeSetterRejection: _counters.nativeSetterRejection + 1,
      lastRedactedError: redacted,
      lastErrorTimestamp: DateTime.now(),
    );
    _notifyAndSave();
  }

  void recordBridgeTimeoutFailure(String method, [dynamic error]) {
    final redacted = redactErrorMessage(
        'Bridge call $method failed${error != null ? ': $error' : ''}');
    _counters = _counters.copyWith(
      bridgeTimeoutFailure: _counters.bridgeTimeoutFailure + 1,
      lastRedactedError: redacted,
      lastErrorTimestamp: DateTime.now(),
    );
    _notifyAndSave();
  }

  void recordRouteResyncFailure([dynamic error]) {
    final redacted = redactErrorMessage(
        'Route resync failed${error != null ? ': $error' : ''}');
    _counters = _counters.copyWith(
      routeResyncFailure: _counters.routeResyncFailure + 1,
      lastRedactedError: redacted,
      lastErrorTimestamp: DateTime.now(),
    );
    _notifyAndSave();
  }

  void recordSessionReattachFailure([dynamic error]) {
    final redacted = redactErrorMessage(
        'Audio session reattach failed${error != null ? ': $error' : ''}');
    _counters = _counters.copyWith(
      sessionReattachFailure: _counters.sessionReattachFailure + 1,
      lastRedactedError: redacted,
      lastErrorTimestamp: DateTime.now(),
    );
    _notifyAndSave();
  }

  void recordAutoDegradeActivation([int? stagesMask]) {
    final redacted = redactErrorMessage(
        'DSP auto-degrade activated${stagesMask != null ? ' (mask: 0x${stagesMask.toRadixString(16)})' : ''}');
    _counters = _counters.copyWith(
      autoDegradeActivation: _counters.autoDegradeActivation + 1,
      lastRedactedError: redacted,
      lastErrorTimestamp: DateTime.now(),
    );
    _notifyAndSave();
  }

  void recordAutoDegradeRecovery() {
    _counters = _counters.copyWith(
      autoDegradeRecovery: _counters.autoDegradeRecovery + 1,
    );
    _notifyAndSave();
  }

  Future<void> resetCounters() async {
    _counters = const DspReliabilityCounters.zero();
    _notifyAndSave();
  }

  void _notifyAndSave() {
    if (!_streamController.isClosed) {
      _streamController.add(_counters);
    }
    unawaited(_saveToPrefs());
  }

  void dispose() {
    if (!_streamController.isClosed) {
      _streamController.close();
    }
  }
}
