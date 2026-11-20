import 'package:injectable/injectable.dart';
// lib/data/audio/headphone_profiles_repository.dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/headphone_profile.dart';
import 'autoeq_fir_generator.dart';

@lazySingleton
class HeadphoneProfilesRepository {
  static final HeadphoneProfilesRepository _instance =
      HeadphoneProfilesRepository._internal();
  factory HeadphoneProfilesRepository() => _instance;
  HeadphoneProfilesRepository._internal();

  List<HeadphoneProfile> _profiles = [];
  bool _isLoaded = false;
  final Map<String, List<double>> _firCache = {};

  List<HeadphoneProfile> get profiles => List.unmodifiable(_profiles);
  bool get isLoaded => _isLoaded;

  /// Retrieves or synthesizes the FIR impulse response for [profile].
  List<double> getFirForProfile(
    HeadphoneProfile profile, {
    bool linearPhase = false,
    int taps = AutoEqFirGenerator.defaultTaps,
    double sampleRate = AutoEqFirGenerator.defaultSampleRate,
  }) {
    final key =
        '${profile.id}_${linearPhase ? 'lin' : 'min'}_${taps}_${sampleRate.round()}';
    final cached = _firCache[key];
    if (cached != null) return cached;

    final fir = profile.generateImpulseResponse(
      linearPhase: linearPhase,
      taps: taps,
      sampleRate: sampleRate,
    );
    final unmodifiable = List<double>.unmodifiable(fir);
    _firCache[key] = unmodifiable;
    return unmodifiable;
  }

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
    // A profile needs *some* correction data. Gain curves are validated as
    // before; parametric profiles legitimately carry no gains because their
    // filters are the authoritative correction (see AutoEqParametricParser
    // .toHeadphoneProfile), so they pass on a non-empty filter list.
    final hasGains = profile.gains.isNotEmpty;
    if (!hasGains && profile.filters.isEmpty) {
      ErrorLogger.log(
          'Rejected custom profile with neither gains nor filters: '
          '${profile.id}',
          category: 'HeadphoneProfilesRepository');
      return;
    }
    if (hasGains && profile.gains.any((g) => !g.isFinite || g.abs() > 15)) {
      ErrorLogger.log(
          'Rejected custom profile with invalid gains: ${profile.id}',
          category: 'HeadphoneProfilesRepository');
      return;
    }
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
    // Bundled profiles are read-only — only custom_* can be removed.
    if (!id.startsWith('custom_')) {
      ErrorLogger.log('Refused to remove bundled profile: $id',
          category: 'HeadphoneProfilesRepository');
      return;
    }
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
