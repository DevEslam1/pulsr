// lib/data/audio/headphone_profiles_repository.dart
import 'dart:convert';
import 'package:flutter/services.dart';
import '../../domain/models/headphone_profile.dart';

class HeadphoneProfilesRepository {
  static final HeadphoneProfilesRepository _instance = HeadphoneProfilesRepository._internal();
  factory HeadphoneProfilesRepository() => _instance;
  HeadphoneProfilesRepository._internal();

  List<HeadphoneProfile> _profiles = [];
  bool _isLoaded = false;

  List<HeadphoneProfile> get profiles => List.unmodifiable(_profiles);
  bool get isLoaded => _isLoaded;

  Future<List<HeadphoneProfile>> loadProfiles() async {
    if (_isLoaded) return _profiles;

    try {
      final jsonString = await rootBundle.loadString('assets/eq_profiles/headphone_profiles.json');
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      _profiles = jsonList
          .map((item) => HeadphoneProfile.fromJson(item as Map<String, dynamic>))
          .toList();
      _isLoaded = true;
    } catch (_) {
      _profiles = [];
    }
    return _profiles;
  }

  HeadphoneProfile? getProfileById(String id) {
    try {
      return _profiles.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  List<String> getCategories() {
    final categories = _profiles.map((p) => p.category).toSet().toList();
    categories.sort();
    return ['All', ...categories];
  }

  List<HeadphoneProfile> search(String query, {String? category}) {
    return _profiles.where((profile) {
      final matchesCategory = category == null || category == 'All' || profile.category == category;
      if (!matchesCategory) return false;

      if (query.trim().isEmpty) return true;
      final q = query.toLowerCase();
      return profile.name.toLowerCase().contains(q) ||
          profile.brand.toLowerCase().contains(q) ||
          profile.model.toLowerCase().contains(q);
    }).toList();
  }
}
