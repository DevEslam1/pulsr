// lib/domain/models/dsp_debug_report.dart
import 'dart:convert';

enum DspEngineType {
  androidAudioEffect,
  nativeCppDsp,
  bitPerfectBypass,
  none,
}

// Platform maps are untyped at runtime (older APKs, backup imports and test
// fixtures may send 1/0 instead of true/false or a numeric string). Parse
// tolerantly so one malformed field cannot discard the whole report.
int _asInt(Object? value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.trim().toLowerCase();
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
  }
  return fallback;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return const <String, dynamic>{};
}

class DspStageDebugInfo {
  final String name;
  final String category; // 'Android HAL', 'C++ Native', 'System'
  final bool isSupported;
  final bool isEnabled;
  final bool isBypassed;
  final bool isDegraded;
  final Map<String, dynamic> parameters;
  final String statusDescription;

  const DspStageDebugInfo({
    required this.name,
    required this.category,
    required this.isSupported,
    required this.isEnabled,
    this.isBypassed = false,
    this.isDegraded = false,
    this.parameters = const {},
    required this.statusDescription,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category,
        'isSupported': isSupported,
        'isEnabled': isEnabled,
        'isBypassed': isBypassed,
        'isDegraded': isDegraded,
        'parameters': parameters,
        'statusDescription': statusDescription,
      };

  factory DspStageDebugInfo.fromMap(Map<String, dynamic> map) {
    return DspStageDebugInfo(
      name: map['name']?.toString() ?? '',
      category: map['category']?.toString() ?? 'DSP',
      isSupported: _asBool(map['isSupported']),
      isEnabled: _asBool(map['isEnabled']),
      isBypassed: _asBool(map['isBypassed']),
      isDegraded: _asBool(map['isDegraded']),
      parameters: _asMap(map['parameters']),
      statusDescription: map['statusDescription']?.toString() ?? '',
    );
  }
}

class DspDebugReport {
  final int audioSessionId;
  final bool isSessionAttached;
  final String dspPreference; // 'native', 'oem', 'auto'
  final bool isBitPerfectBypassActive;
  final bool isNativeDspLoaded;
  final int activeDspStagesMask;
  final int autoDegradedStagesMask;
  final bool hasOemAudio;
  final List<String> detectedOemEngines;
  final List<DspStageDebugInfo> stages;
  final List<String> activeEffectNames;
  final DateTime timestamp;

  const DspDebugReport({
    required this.audioSessionId,
    required this.isSessionAttached,
    required this.dspPreference,
    required this.isBitPerfectBypassActive,
    required this.isNativeDspLoaded,
    required this.activeDspStagesMask,
    required this.autoDegradedStagesMask,
    required this.hasOemAudio,
    required this.detectedOemEngines,
    required this.stages,
    required this.activeEffectNames,
    required this.timestamp,
  });

  factory DspDebugReport.fromMap(Map<dynamic, dynamic> map) {
    final rawStages = map['stages'];
    final List<DspStageDebugInfo> parsedStages = [];
    if (rawStages is List) {
      for (final s in rawStages) {
        if (s is Map) {
          parsedStages
              .add(DspStageDebugInfo.fromMap(s.cast<String, dynamic>()));
        }
      }
    }

    final rawOem = map['detectedOemEngines'] ?? map['detectedEngines'];
    final List<String> parsedOem = [];
    if (rawOem is List) {
      for (final o in rawOem) {
        if (o != null) parsedOem.add(o.toString());
      }
    }

    final rawActiveNames = map['activeEffectNames'];
    final List<String> parsedActive = [];
    if (rawActiveNames is List) {
      for (final a in rawActiveNames) {
        if (a != null) parsedActive.add(a.toString());
      }
    }

    return DspDebugReport(
      audioSessionId: _asInt(map['audioSessionId']),
      isSessionAttached: _asBool(map['isSessionAttached']),
      dspPreference: map['dspPreference']?.toString() ?? 'native',
      isBitPerfectBypassActive: _asBool(map['isBitPerfectBypassActive']),
      isNativeDspLoaded: _asBool(map['isNativeDspLoaded']),
      activeDspStagesMask: _asInt(map['activeDspStagesMask']),
      autoDegradedStagesMask: _asInt(map['autoDegradedStagesMask']),
      hasOemAudio: _asBool(map['hasOemAudio']),
      detectedOemEngines: parsedOem,
      stages: parsedStages,
      activeEffectNames: parsedActive,
      timestamp: _parseTimestamp(map['timestamp']),
    );
  }

  /// Parses the report's persisted ISO-8601 timestamp, falling back to "now"
  /// only when the value is absent or unparseable. Dropping it (or always
  /// using now) made a re-read report claim to be freshly captured, so stale
  /// debug snapshots could not be told apart from live ones.
  static DateTime _parseTimestamp(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  Map<String, dynamic> toMap() => {
        'audioSessionId': audioSessionId,
        'isSessionAttached': isSessionAttached,
        'dspPreference': dspPreference,
        'isBitPerfectBypassActive': isBitPerfectBypassActive,
        'isNativeDspLoaded': isNativeDspLoaded,
        'activeDspStagesMask': activeDspStagesMask,
        'autoDegradedStagesMask': autoDegradedStagesMask,
        'hasOemAudio': hasOemAudio,
        'detectedOemEngines': detectedOemEngines,
        'activeEffectNames': activeEffectNames,
        'stages': stages.map((s) => s.toMap()).toList(),
        'timestamp': timestamp.toIso8601String(),
      };

  String toFormattedJson() =>
      const JsonEncoder.withIndent('  ').convert(toMap());
}
