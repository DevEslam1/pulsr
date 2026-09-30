// lib/features/shell/presentation/widgets/dock_style_controller.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/prefs_keys.dart';
import 'stacked_bottom_dock.dart';

export 'stacked_bottom_dock.dart' show DockStackMode;

/// Single source of truth for the mini-player dock stacking style.
///
/// The shell renders from [mode]; Settings can change it through the same
/// picker, and both read/write the persisted preference here.
class DockStyleController {
  DockStyleController._();

  static final ValueNotifier<DockStackMode> mode =
      ValueNotifier<DockStackMode>(DockStackMode.defaultLayout);

  /// Restores the persisted dock style (call once at startup).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(PrefsKeys.dockStackMode);
      if (name == null) return;
      mode.value = DockStackMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => DockStackMode.defaultLayout,
      );
    } catch (_) {
      // Preference store unavailable — keep the default.
    }
  }

  static Future<void> set(DockStackMode next) async {
    if (next == mode.value) return;
    mode.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PrefsKeys.dockStackMode, next.name);
    } catch (_) {}
  }

  @visibleForTesting
  static void reset() => mode.value = DockStackMode.defaultLayout;
}
