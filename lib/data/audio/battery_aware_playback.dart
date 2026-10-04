// lib/data/audio/battery_aware_playback.dart

/// Degradation policy applied based on battery level.
enum BatteryOptimizationLevel {
  normal,
  lowPower, // Battery < 15%: reduce heavy DSP, disable visualizer
  critical, // Battery < 5%: disable crossfade, minimal buffers, gapless only
}

/// Battery-aware playback controller that optimizes CPU load and DSP stages.
///
/// Uses hysteresis so a level hovering around a threshold (e.g. 14% <-> 15%)
/// does not repeatedly toggle DSP/crossfade: degradation starts below
/// 15% / 5% and is only lifted at 17% / 7%.
class BatteryAwarePlayback {
  static const int lowPowerEnter = 15;
  static const int lowPowerExit = 17;
  static const int criticalEnter = 5;
  static const int criticalExit = 7;

  BatteryOptimizationLevel _currentLevel = BatteryOptimizationLevel.normal;
  BatteryOptimizationLevel get currentLevel => _currentLevel;

  final void Function(
      {required bool disableVisualizer,
      required bool reduceDsp})? onLowPowerMode;
  final void Function(
      {required bool disableCrossfade,
      required bool minimalBuffer})? onCriticalMode;
  final void Function()? onRestoreNormal;

  /// Optional: lift ONLY the critical-level degradations (crossfade, buffers)
  /// while staying in low-power. If null, falls back to
  /// [onRestoreNormal] followed by [onLowPowerMode] (previous behaviour),
  /// which briefly re-enables the visualizer/DSP.
  final void Function()? onRestoreFromCritical;

  BatteryAwarePlayback({
    this.onLowPowerMode,
    this.onCriticalMode,
    this.onRestoreNormal,
    this.onRestoreFromCritical,
  });

  /// Handles battery level changes (0 to 100). While [isCharging] the device
  /// is treated as healthy, so degradations are lifted.
  void onBatteryLevelChanged(int batteryPercentage, {bool isCharging = false}) {
    final level = batteryPercentage.clamp(0, 100);
    _apply(_targetLevel(level, isCharging));
  }

  /// Forces the controller back to [BatteryOptimizationLevel.normal],
  /// notifying listeners if a degradation was active.
  void reset() => _apply(BatteryOptimizationLevel.normal);

  BatteryOptimizationLevel _targetLevel(int level, bool isCharging) {
    if (isCharging) return BatteryOptimizationLevel.normal;
    switch (_currentLevel) {
      case BatteryOptimizationLevel.normal:
        if (level < criticalEnter) return BatteryOptimizationLevel.critical;
        if (level < lowPowerEnter) return BatteryOptimizationLevel.lowPower;
        return BatteryOptimizationLevel.normal;
      case BatteryOptimizationLevel.lowPower:
        if (level < criticalEnter) return BatteryOptimizationLevel.critical;
        if (level >= lowPowerExit) return BatteryOptimizationLevel.normal;
        return BatteryOptimizationLevel.lowPower;
      case BatteryOptimizationLevel.critical:
        if (level >= lowPowerExit) return BatteryOptimizationLevel.normal;
        if (level >= criticalExit) return BatteryOptimizationLevel.lowPower;
        return BatteryOptimizationLevel.critical;
    }
  }

  void _apply(BatteryOptimizationLevel target) {
    final previous = _currentLevel;
    if (target == previous) return;
    _currentLevel = target;

    switch (target) {
      case BatteryOptimizationLevel.critical:
        onCriticalMode?.call(disableCrossfade: true, minimalBuffer: true);
        // Low-power degradations are already active when coming from lowPower.
        if (previous == BatteryOptimizationLevel.normal) {
          onLowPowerMode?.call(disableVisualizer: true, reduceDsp: true);
        }
        break;
      case BatteryOptimizationLevel.lowPower:
        if (previous == BatteryOptimizationLevel.critical) {
          // Critical-only degradations (crossfade, buffers) must be lifted
          // when the battery recovers (B-8), then low-power re-applied.
          if (onRestoreFromCritical != null) {
            onRestoreFromCritical!.call();
          } else {
            onRestoreNormal?.call();
            onLowPowerMode?.call(disableVisualizer: true, reduceDsp: true);
          }
        } else {
          onLowPowerMode?.call(disableVisualizer: true, reduceDsp: true);
        }
        break;
      case BatteryOptimizationLevel.normal:
        onRestoreNormal?.call();
        break;
    }
  }
}
