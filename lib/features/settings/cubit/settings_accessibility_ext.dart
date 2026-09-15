// lib/features/settings/cubit/settings_accessibility_ext.dart
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_cubit.dart';

/// Accessibility-related settings mutations, split out of `SettingsCubit` so
/// that file stays under the fat-file ratchet. Mirrors the existing
/// `safeEmit` + SharedPreferences persistence pattern used by the inline
/// setters.
extension SettingsAccessibilityX on SettingsCubit {
  static const String _keyReduceMotion = 'setting_reduce_motion';

  Future<void> setReduceMotion(bool value) async {
    safeEmit(state.copyWith(reduceMotion: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReduceMotion, value);
  }
}
