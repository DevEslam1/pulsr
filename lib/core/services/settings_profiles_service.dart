// lib/core/services/settings_profiles_service.dart
import 'dart:convert';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_logger.dart';

enum ProfileType { home, car, gym, sleep, custom }

class SettingsProfile {
  final String id;
  final String name;
  final ProfileType type;
  final String eqPresetName;
  final double volumeBoost;
  final bool crossfadeEnabled;
  final double crossfadeSeconds;
  final bool bitPerfectEnabled;
  final String playerTheme;

  const SettingsProfile({
    required this.id,
    required this.name,
    required this.type,
    this.eqPresetName = 'Flat',
    this.volumeBoost = 0.0,
    this.crossfadeEnabled = false,
    this.crossfadeSeconds = 0.0,
    this.bitPerfectEnabled = false,
    this.playerTheme = 'classic',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'eqPresetName': eqPresetName,
        'volumeBoost': volumeBoost,
        'crossfadeEnabled': crossfadeEnabled,
        'crossfadeSeconds': crossfadeSeconds,
        'bitPerfectEnabled': bitPerfectEnabled,
        'playerTheme': playerTheme,
      };

  factory SettingsProfile.fromJson(Map<String, dynamic> json) =>
      SettingsProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        type: ProfileType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ProfileType.custom,
        ),
        eqPresetName: json['eqPresetName'] as String? ?? 'Flat',
        volumeBoost: (json['volumeBoost'] as num?)?.toDouble() ?? 0.0,
        crossfadeEnabled: json['crossfadeEnabled'] as bool? ?? false,
        crossfadeSeconds: (json['crossfadeSeconds'] as num?)?.toDouble() ?? 0.0,
        bitPerfectEnabled: json['bitPerfectEnabled'] as bool? ?? false,
        playerTheme: json['playerTheme'] as String? ?? 'classic',
      );

  static const List<SettingsProfile> defaultProfiles = [
    SettingsProfile(
      id: 'profile_home',
      name: 'Home Audiophile',
      type: ProfileType.home,
      eqPresetName: 'Flat',
      bitPerfectEnabled: true,
      playerTheme: 'vinyl',
    ),
    SettingsProfile(
      id: 'profile_car',
      name: 'Car Commute',
      type: ProfileType.car,
      eqPresetName: 'Bass Boost',
      volumeBoost: 0.3,
      crossfadeEnabled: true,
      crossfadeSeconds: 4.0,
      playerTheme: 'minimal',
    ),
    SettingsProfile(
      id: 'profile_gym',
      name: 'Gym Workout',
      type: ProfileType.gym,
      eqPresetName: 'Electronic',
      volumeBoost: 0.2,
      crossfadeEnabled: true,
      crossfadeSeconds: 6.0,
      playerTheme: 'waveform',
    ),
    SettingsProfile(
      id: 'profile_sleep',
      name: 'Sleep / Bedtime',
      type: ProfileType.sleep,
      eqPresetName: 'Vocal Boost',
      crossfadeEnabled: true,
      crossfadeSeconds: 8.0,
      playerTheme: 'minimal',
    ),
  ];
}

@singleton
class SettingsProfilesService {
  static const String _keyProfiles = 'setting_custom_profiles';

  Future<List<SettingsProfile>> getProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_keyProfiles);
      if (jsonStr != null) {
        final list = json.decode(jsonStr) as List<dynamic>;
        return list
            .map((e) => SettingsProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to load settings profiles',
          error: e, stackTrace: st, category: 'SettingsProfilesService');
    }
    return SettingsProfile.defaultProfiles;
  }

  Future<void> saveProfile(SettingsProfile profile) async {
    final list = await getProfiles();
    final updated = List<SettingsProfile>.from(list);
    final idx = updated.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      updated[idx] = profile;
    } else {
      updated.add(profile);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyProfiles, json.encode(updated.map((p) => p.toJson()).toList()));
  }

  Future<void> deleteProfile(String profileId) async {
    final list = await getProfiles();
    final updated = List<SettingsProfile>.from(list);
    updated.removeWhere((p) => p.id == profileId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyProfiles, json.encode(updated.map((p) => p.toJson()).toList()));
  }
}
