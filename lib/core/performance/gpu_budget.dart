// lib/core/performance/gpu_budget.dart
import 'package:flutter/foundation.dart';

/// Global GPU-budget flag: when enabled (saving mode active), expensive
/// blur/shader/waveform passes fall back to cheap surfaces to conserve power.
/// Persisted by SettingsCubit via SharedPreferences; defaults to false (full fidelity).
class GpuBudget {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// When true, power/GPU-saving budget mode is active: expensive blurs,
  /// shaders, and continuous re-renders fall back to solid/cheap surfaces.
  static bool get isEnabled => enabled.value;

  /// Semantic alias for [isEnabled]: true when power/GPU-saving mode is active
  /// and expensive backdrop filters or shaders should be avoided.
  static bool get isGpuSaverActive => enabled.value;

  static void setEnabled(bool v) {
    if (enabled.value != v) enabled.value = v;
  }
}
