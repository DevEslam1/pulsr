// F7: Audio ducking control (navigation voice vs music).
import 'package:shared_preferences/shared_preferences.dart';

enum DuckingMode { duck, pause, ignore }

/// User-controllable ducking: how much to lower music when a transient
/// focus loss (navigation prompt, assistant) arrives.
class DuckingController {
  static const String prefsModeKey = 'audio_ducking_mode_v1';
  static const String prefsLevelKey = 'audio_ducking_level_v1';

  DuckingMode mode;
  double level; // 0.0..1.0 fraction of pre-duck volume to keep

  DuckingController({this.mode = DuckingMode.duck, this.level = 0.3});

  double get duckFactor => level.clamp(0.05, 1.0);

  double duckedVolume(double currentVolume) =>
      (currentVolume * duckFactor).clamp(0.0, 1.0);

  bool get shouldPause => mode == DuckingMode.pause;
  bool get shouldIgnore => mode == DuckingMode.ignore;
  bool get shouldDuck => mode == DuckingMode.duck;

  void setMode(DuckingMode m) => mode = m;
  void setLevel(double v) => level = v.clamp(0.05, 1.0);

  static DuckingMode parseMode(String? raw) => DuckingMode.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => DuckingMode.duck);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mode = parseMode(prefs.getString(prefsModeKey));
      final v = prefs.getDouble(prefsLevelKey);
      if (v != null && v.isFinite) level = v.clamp(0.05, 1.0);
    } catch (_) {}
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsModeKey, mode.name);
      await prefs.setDouble(prefsLevelKey, level);
    } catch (_) {}
  }
}
