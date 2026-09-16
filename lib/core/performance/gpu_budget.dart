// lib/core/performance/gpu_budget.dart
import 'package:flutter/foundation.dart';

/// Global GPU-budget flag: when enabled, expensive blur/shader/waveform
/// passes fall back to cheap surfaces. Persisted by SettingsCubit via
/// SharedPreferences; defaults to false (full fidelity).
class GpuBudget {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static bool get isEnabled => enabled.value;
  static void setEnabled(bool v) {
    if (enabled.value != v) enabled.value = v;
  }
}
