// lib/data/audio/battery_aware_playback.dart

/// Degradation policy applied based on battery level.
enum BatteryOptimizationLevel {
  normal,
  lowPower, // Battery < 15%: reduce heavy DSP, disable visualizer
  critical, // Battery < 5%: disable crossfade, minimal buffers, gapless only
}

/// Battery-aware playback controller that optimizes CPU load and DSP stages.
class BatteryAwarePlayback {
  BatteryOptimizationLevel _currentLevel = BatteryOptimizationLevel.normal;
  BatteryOptimizationLevel get currentLevel => _currentLevel;

  final void Function({required bool disableVisualizer, required bool reduceDsp})?
      onLowPowerMode;
  final void Function({required bool disableCrossfade, required bool minimalBuffer})?
      onCriticalMode;
  final void Function()? onRestoreNormal;

  BatteryAwarePlayback({
    this.onLowPowerMode,
    this.onCriticalMode,
    this.onRestoreNormal,
  });

  /// Handles battery level changes (0 to 100).
  void onBatteryLevelChanged(int batteryPercentage) {
    if (batteryPercentage < 5) {
      if (_currentLevel != BatteryOptimizationLevel.critical) {
        _currentLevel = BatteryOptimizationLevel.critical;
        onCriticalMode?.call(disableCrossfade: true, minimalBuffer: true);
        onLowPowerMode?.call(disableVisualizer: true, reduceDsp: true);
      }
    } else if (batteryPercentage < 15) {
      if (_currentLevel != BatteryOptimizationLevel.lowPower) {
        _currentLevel = BatteryOptimizationLevel.lowPower;
        onLowPowerMode?.call(disableVisualizer: true, reduceDsp: true);
      }
    } else {
      if (_currentLevel != BatteryOptimizationLevel.normal) {
        _currentLevel = BatteryOptimizationLevel.normal;
        onRestoreNormal?.call();
      }
    }
  }
}
