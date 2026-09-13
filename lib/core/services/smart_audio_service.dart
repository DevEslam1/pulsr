// lib/core/services/smart_audio_service.dart
//
// Persistence + policy access for Smart Audio. Stores the user's Auto/Manual
// preference and the per-device AutoEQ matches the coordinator discovers, so a
// headset is corrected instantly (and identically) on every reconnect without
// re-running fuzzy matching.
//
// Decision logic itself lives in the pure `smart_audio_plan.dart`; this service
// only reads/writes state.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/services/smart_audio_plan.dart';
import '../constants/prefs_keys.dart';
import '../utils/error_logger.dart';

/// A remembered "output device -> AutoEQ profile" association.
class SmartAudioEqLink {
  final String deviceKey;
  final String deviceLabel;
  final String profileId;

  /// Confidence of the match that created this link (1.0 for a manual choice).
  final double score;

  const SmartAudioEqLink({
    required this.deviceKey,
    required this.deviceLabel,
    required this.profileId,
    this.score = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'deviceKey': deviceKey,
        'deviceLabel': deviceLabel,
        'profileId': profileId,
        'score': score,
      };

  factory SmartAudioEqLink.fromJson(Map<String, dynamic> json) =>
      SmartAudioEqLink(
        deviceKey: json['deviceKey'] as String? ?? '',
        deviceLabel: json['deviceLabel'] as String? ?? '',
        profileId: json['profileId'] as String? ?? '',
        score: (json['score'] as num?)?.toDouble() ?? 1.0,
      );
}

class SmartAudioService {
  Future<SmartAudioMode> getMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return SmartAudioMode.fromName(prefs.getString(PrefsKeys.smartAudioMode));
    } catch (e, st) {
      ErrorLogger.log('Failed to read smart audio mode',
          error: e, stackTrace: st, category: 'SmartAudioService');
      return SmartAudioMode.auto;
    }
  }

  Future<void> setMode(SmartAudioMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.smartAudioMode, mode.name);
  }

  /// True when automatic adaptation is enabled.
  Future<bool> isEnabled() async => (await getMode()) == SmartAudioMode.auto;

  Future<Map<String, SmartAudioEqLink>> getAutoEqLinks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefsKeys.smartAudioAutoEqLinks);
      if (raw == null || raw.isEmpty) return {};
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) =>
          MapEntry(k, SmartAudioEqLink.fromJson(v as Map<String, dynamic>)));
    } catch (e, st) {
      ErrorLogger.log('Failed to load smart audio AutoEQ links',
          error: e, stackTrace: st, category: 'SmartAudioService');
      return {};
    }
  }

  Future<SmartAudioEqLink?> linkForDeviceKey(String deviceKey) async {
    final links = await getAutoEqLinks();
    return links[deviceKey];
  }

  Future<void> rememberAutoEqLink({
    required String deviceKey,
    required String deviceLabel,
    required String profileId,
    double score = 1.0,
  }) async {
    final links = await getAutoEqLinks();
    links[deviceKey] = SmartAudioEqLink(
      deviceKey: deviceKey,
      deviceLabel: deviceLabel,
      profileId: profileId,
      score: score,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PrefsKeys.smartAudioAutoEqLinks,
      json.encode(links.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  Future<void> forgetAutoEqLink(String deviceKey) async {
    final links = await getAutoEqLinks();
    if (links.remove(deviceKey) == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PrefsKeys.smartAudioAutoEqLinks,
      json.encode(links.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }
}
