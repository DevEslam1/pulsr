// lib/features/settings/cubit/settings_state.dart

class SettingsState {
  final bool gaplessPlayback;
  final double crossfadeSeconds;
  final int minDurationSec;
  final bool dynamicThemingEnabled;
  final bool isScanning;
  final int? scanResultCount;
  final String? errorMessage;

  const SettingsState({
    this.gaplessPlayback = true,
    this.crossfadeSeconds = 0.0,
    this.minDurationSec = 30,
    this.dynamicThemingEnabled = true,
    this.isScanning = false,
    this.scanResultCount,
    this.errorMessage,
  });

  SettingsState copyWith({
    bool? gaplessPlayback,
    double? crossfadeSeconds,
    int? minDurationSec,
    bool? dynamicThemingEnabled,
    bool? isScanning,
    int? scanResultCount,
    String? errorMessage,
  }) {
    return SettingsState(
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      minDurationSec: minDurationSec ?? this.minDurationSec,
      dynamicThemingEnabled: dynamicThemingEnabled ?? this.dynamicThemingEnabled,
      isScanning: isScanning ?? this.isScanning,
      scanResultCount: scanResultCount,
      errorMessage: errorMessage,
    );
  }
}
