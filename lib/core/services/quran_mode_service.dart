// lib/core/services/quran_mode_service.dart
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/quran_mode_profile.dart';
import '../../domain/models/quran_style_tuning.dart';

/// Persistence for Quran Mode. The live DSP state is owned by [PlayerCubit];
/// this service only remembers which style was selected and whether the mode
/// is on, so it can be restored on the next launch.
@singleton
class QuranModeService {
  static const String _keyEnabled = 'quran_mode_enabled';
  static const String _keyStyle = 'quran_reciter_style';
  static const String _keyStyleTunings = 'quran_reciter_style_tunings_v1';

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

  Future<QuranStyleTuning> getStyleTuning(QuranReciterStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyStyleTunings);
    if (raw == null || raw.isEmpty) return const QuranStyleTuning();
    try {
      final values = jsonDecode(raw);
      if (values is! Map) return const QuranStyleTuning();
      final tuning = values[style.name];
      return tuning is Map
          ? QuranStyleTuning.fromJson(Map<String, dynamic>.from(tuning))
          : const QuranStyleTuning();
    } on FormatException {
      return const QuranStyleTuning();
    }
  }

  Future<void> setStyleTuning(
      QuranReciterStyle style, QuranStyleTuning tuning) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyStyleTunings);
    final values = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) values.addAll(Map<String, dynamic>.from(decoded));
      } on FormatException {
        // Corrupt optional tuning must not block Quran Mode.
      }
    }
    if (tuning.isEmpty) {
      values.remove(style.name);
    } else {
      values[style.name] = tuning.toJson();
    }
    await prefs.setString(_keyStyleTunings, jsonEncode(values));
  }

  /// The saved profile, or null when Quran Mode was off at last exit.
  Future<QuranModeProfile?> loadActiveProfile() async {
    if (!await isEnabled()) return null;
    return QuranModeProfile.forStyle(await getStyle());
  }
}
