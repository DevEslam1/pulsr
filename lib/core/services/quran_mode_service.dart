// lib/core/services/quran_mode_service.dart
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/quran_mode_profile.dart';

/// Persistence for Quran Mode. The live DSP state is owned by [PlayerCubit];
/// this service only remembers which style was selected and whether the mode
/// is on, so it can be restored on the next launch.
@singleton
class QuranModeService {
  static const String _keyEnabled = 'quran_mode_enabled';
  static const String _keyStyle = 'quran_reciter_style';

  QuranModeService();

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
  }

  Future<QuranReciterStyle> getStyle() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyStyle);
    return QuranReciterStyle.values.firstWhere(
      (s) => s.name == name,
      orElse: () => QuranReciterStyle.murattal,
    );
  }

  Future<void> setStyle(QuranReciterStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStyle, style.name);
  }

  /// The saved profile, or null when Quran Mode was off at last exit.
  Future<QuranModeProfile?> loadActiveProfile() async {
    if (!await isEnabled()) return null;
    return QuranModeProfile.forStyle(await getStyle());
  }
}
