// F10: Silence-skip sensitivity slider.
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';

/// Sensitivity 0..100. The native ExoPlayer skip-silence stage is boolean, so
/// the slider maps to: 0 = off, 1..100 = on. The exact threshold/run-length is
/// chosen by the media pipeline (ExoPlayer's SilenceSkippingAudioProcessor),
/// which exposes no app-facing tuning API on this platform.
class SilenceSkipController {
  static const String prefsEnabledKey = 'skip_silence_enabled';
  static const String prefsSensitivityKey = 'skip_silence_sensitivity_v1';

  bool enabled = false;
  int sensitivity = 50; // 1..100 when enabled

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
      final savedSensitivity = prefs.getInt(prefsSensitivityKey);
      if (savedSensitivity == null || (!enabled && savedSensitivity <= 0)) {
        // Legacy installs stored only the bool (or 0 when disabled); default mid sensitivity.
        sensitivity = 50;
      } else {
        sensitivity = savedSensitivity.clamp(0, 100);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to load silence skip settings',
          error: e, stackTrace: st, category: 'SilenceSkipController');
    }
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsEnabledKey, enabled);
      await prefs.setInt(prefsSensitivityKey, sensitivity);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist silence skip settings',
          error: e, stackTrace: st, category: 'SilenceSkipController');
    }
  }
}
