// lib/domain/models/dsp_debug_report.dart
import 'dart:convert';

enum DspEngineType {
  androidAudioEffect,
  nativeCppDsp,
  bitPerfectBypass,
  none,
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
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? 'DSP',
      isSupported: map['isSupported'] as bool? ?? false,
      isEnabled: map['isEnabled'] as bool? ?? false,
      isBypassed: map['isBypassed'] as bool? ?? false,
      isDegraded: map['isDegraded'] as bool? ?? false,
      parameters: (map['parameters'] as Map?)?.cast<String, dynamic>() ?? {},
      statusDescription: map['statusDescription'] as String? ?? '',
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
          parsedStages.add(DspStageDebugInfo.fromMap(s.cast<String, dynamic>()));
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
      audioSessionId: (map['audioSessionId'] as num?)?.toInt() ?? 0,
      isSessionAttached: (map['isSessionAttached'] as bool?) ?? false,
      dspPreference: map['dspPreference'] as String? ?? 'native',
      isBitPerfectBypassActive: (map['isBitPerfectBypassActive'] as bool?) ?? false,
      isNativeDspLoaded: (map['isNativeDspLoaded'] as bool?) ?? false,
      activeDspStagesMask: (map['activeDspStagesMask'] as num?)?.toInt() ?? 0,
      autoDegradedStagesMask: (map['autoDegradedStagesMask'] as num?)?.toInt() ?? 0,
      hasOemAudio: (map['hasOemAudio'] as bool?) ?? false,
      detectedOemEngines: parsedOem,
      stages: parsedStages,
      activeEffectNames: parsedActive,
      timestamp: DateTime.now(),
    );
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
