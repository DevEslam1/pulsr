// lib/data/audio/headphone_profiles_repository.dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/headphone_profile.dart';

class HeadphoneProfilesRepository {
  static final HeadphoneProfilesRepository _instance =
      HeadphoneProfilesRepository._internal();
  factory HeadphoneProfilesRepository() => _instance;
  HeadphoneProfilesRepository._internal();

  List<HeadphoneProfile> _profiles = [];
  bool _isLoaded = false;

  List<HeadphoneProfile> get profiles => List.unmodifiable(_profiles);
  bool get isLoaded => _isLoaded;

  Future<List<HeadphoneProfile>> loadProfiles() async {
    if (_isLoaded) return _profiles;

    try {
      final jsonString = await rootBundle
          .loadString('assets/eq_profiles/headphone_profiles.json');
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      final bundled = jsonList
          .map(
              (item) => HeadphoneProfile.fromJson(item as Map<String, dynamic>))
          .toList();

      // Load custom user profiles from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final customJson = prefs.getString(PrefsKeys.customEqProfiles);
      final List<HeadphoneProfile> customProfiles = [];
      if (customJson != null) {
        try {
          final List<dynamic> customList =
              json.decode(customJson) as List<dynamic>;
          for (final item in customList) {
            customProfiles
                .add(HeadphoneProfile.fromJson(item as Map<String, dynamic>));
          }
        } catch (e, st) {
          ErrorLogger.log('Failed to decode custom EQ profiles',
              error: e,
              stackTrace: st,
              category: 'HeadphoneProfilesRepository');
        }
      }

      _profiles = [...customProfiles, ...bundled];
      _isLoaded = true;
    } catch (e, st) {
      ErrorLogger.log('Failed to load headphone profiles from assets',
          error: e, stackTrace: st, category: 'HeadphoneProfilesRepository');
      _profiles = [];
    }
    return _profiles;
  }

  Future<void> addCustomProfile(HeadphoneProfile profile) async {
    // Replace if existing ID matches, else prepend
    final existingIndex = _profiles.indexWhere((p) => p.id == profile.id);
    if (existingIndex >= 0) {
      _profiles[existingIndex] = profile;
    } else {
      _profiles = [profile, ..._profiles];
    }
    await _saveCustomProfiles();
  }

  Future<void> removeProfile(String id) async {
    _profiles = _profiles.where((p) => p.id != id).toList();
    await _saveCustomProfiles();
  }

  Future<void> _saveCustomProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _profiles
          .where((p) => p.id.startsWith('custom_'))
          .map((p) => p.toJson())
          .toList();
      await prefs.setString(PrefsKeys.customEqProfiles, jsonEncode(jsonList));
    } catch (e, st) {
      ErrorLogger.log('Failed to save custom EQ profiles',
          error: e, stackTrace: st, category: 'HeadphoneProfilesRepository');
    }
  }

  HeadphoneProfile? getProfileById(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<String> getCategories() {
    final categories = _profiles.map((p) => p.category).toSet().toList();
    categories.sort();
    return ['All', ...categories];
  }

  List<HeadphoneProfile> search(String query, {String? category}) {
    return _profiles.where((profile) {
      final matchesCategory =
          category == null || category == 'All' || profile.category == category;
      if (!matchesCategory) return false;

      if (query.trim().isEmpty) return true;
      final q = query.toLowerCase();
      final tokens = q.split(RegExp(r'\s+'));
      final searchable =
          '${profile.name} ${profile.brand} ${profile.model} ${profile.category}'
              .toLowerCase();
      return tokens.every((token) => searchable.contains(token));
    }).toList();
  }
}
