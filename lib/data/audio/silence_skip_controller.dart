// F10: Silence-skip sensitivity slider.
import 'package:shared_preferences/shared_preferences.dart';

/// Sensitivity 0..100. The native ExoPlayer skip-silence is boolean, so the
/// slider maps to: 0 = off, 1..100 = on with an advertised threshold that
/// software trims / future native thresholds can consume.
class SilenceSkipController {
  static const String prefsEnabledKey = 'skip_silence_enabled';
  static const String prefsSensitivityKey = 'skip_silence_sensitivity_v1';

  bool enabled = false;
  int sensitivity = 50; // 1..100 when enabled

  int get clampedSensitivity => sensitivity.clamp(1, 100);

  /// Advertised silence threshold in dB for UI/native use.
  /// Maps 1..100 → -50dB..-20dB (more sensitive = quieter passages skipped).
  double get thresholdDb {
    final s = enabled ? clampedSensitivity : 0;
    if (s <= 0) return -60.0;
    return -50.0 + (s / 100.0) * 30.0;
  }

  /// Minimum silence run to skip, 200ms..2000ms (less sensitive = longer run).
  Duration get minSilenceDuration {
    if (!enabled) return Duration.zero;
    final ms = 2000 - ((clampedSensitivity / 100.0) * 1800).round();
    return Duration(milliseconds: ms.clamp(200, 2000));
  }

  void setEnabled(bool v) => enabled = v;
  void setSensitivity(int v) {
    sensitivity = v.clamp(0, 100);
    if (sensitivity > 0) enabled = true;
    if (sensitivity == 0) enabled = false;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(prefsEnabledKey) ?? false;
      sensitivity =
          (prefs.getInt(prefsSensitivityKey) ?? (enabled ? 50 : 0)).clamp(0, 100);
      if (!enabled && sensitivity > 0) {
        // Legacy installs stored only the bool; default mid sensitivity.
        sensitivity = 50;
      }
    } catch (_) {}
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsEnabledKey, enabled);
      await prefs.setInt(prefsSensitivityKey, sensitivity);
    } catch (_) {}
  }
}
