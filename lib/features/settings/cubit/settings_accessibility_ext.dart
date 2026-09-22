// lib/features/settings/cubit/settings_accessibility_ext.dart
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/performance/gpu_budget.dart';
import 'settings_cubit.dart';

/// Accessibility-related settings mutations, split out of `SettingsCubit` so
/// that file stays under the fat-file ratchet. Mirrors the existing
/// `safeEmit` + SharedPreferences persistence pattern used by the inline
/// setters.
extension SettingsAccessibilityX on SettingsCubit {
  static const String _keyReduceMotion = 'setting_reduce_motion';

  Future<void> setReduceMotion(bool value) async {
    // FIX-H07: Track dirty field during async load
    markDirty('reduceMotion');
    safeEmit(state.copyWith(reduceMotion: value));
    // Reduced motion also opts out of expensive blur/shader passes.
    GpuBudget.setEnabled(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReduceMotion, value);
  }

  /// Rehydrates [GpuBudget] at startup so glass blur / visualizers respect
  /// the persisted toggle before first frame.
  static Future<void> restoreGpuBudget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      GpuBudget.setEnabled(prefs.getBool(_keyReduceMotion) ?? false);
    } catch (_) {}
  }
}
