// lib/domain/services/auto_eq_service.dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import '../../core/utils/error_logger.dart';
import '../../data/audio/audio_effects_channel.dart';
import '../models/auto_eq_profile.dart';

@lazySingleton
class AutoEqService {
  final AudioEffectsChannel _channel;
  List<AutoEqProfile> _cachedProfiles = const [];
  AutoEqProfile? _activeProfile;

  AutoEqService([AudioEffectsChannel? channel])
      : _channel = channel ?? AudioEffectsChannel();

  AutoEqProfile? get activeProfile => _activeProfile;

  /// Loads headphone profiles from bundled assets.
  Future<List<AutoEqProfile>> loadProfiles() async {
    if (_cachedProfiles.isNotEmpty) return _cachedProfiles;

    try {
      final jsonStr = await rootBundle.loadString(
        'assets/eq_profiles/headphone_profiles.json',
      );
      final decoded = json.decode(jsonStr) as List<dynamic>;
      _cachedProfiles = decoded
          .map((e) => AutoEqProfile.fromJson(e as Map<String, dynamic>))
          .toList();
      return _cachedProfiles;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to load headphone profiles from assets',
        error: e,
        stackTrace: st,
        category: 'AutoEqService',
      );
      return const [];
    }
  }

  /// Searches loaded profiles by brand, model, or title.
  Future<List<AutoEqProfile>> search(String query) async {
    final profiles = await loadProfiles();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return profiles;

    return profiles.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.model.toLowerCase().contains(q);
    }).toList();
  }

  /// Autopilot: attempts to match an output device name (Bluetooth or USB)
  /// against known headphone profiles.
  Future<AutoEqProfile?> matchForDeviceName(String deviceName) async {
    final profiles = await loadProfiles();
    final clean = deviceName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.isEmpty) return null;

    for (final p in profiles) {
      final pModel = p.model.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final pName = p.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (clean.contains(pModel) || clean.contains(pName)) {
        return p;
      }
    }
    return null;
  }

  /// Applies the target AutoEQ profile via native EqualizerAPO arbitrary EQ.
  Future<bool> applyProfile(
    AutoEqProfile profile, {
    bool linearPhase = false,
  }) async {
    try {
      final graphicEqStr = profile.toGraphicEqString();
      final ok = await _channel.loadArbitraryEq(
        eqString: graphicEqStr,
        linearPhase: linearPhase,
      );
      if (ok) {
        await _channel.setArbitraryEqEnabled(true);
        _activeProfile = profile;
        return true;
      }
      return false;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to apply AutoEQ profile ${profile.id}',
        error: e,
        stackTrace: st,
        category: 'AutoEqService',
      );
      return false;
    }
  }

  /// Disables arbitrary EQ correction.
  Future<void> disableProfile() async {
    try {
      await _channel.setArbitraryEqEnabled(false);
      _activeProfile = null;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to disable AutoEQ profile',
        error: e,
        stackTrace: st,
        category: 'AutoEqService',
      );
    }
  }

  /// Exports custom and cached profiles to JSON for backup or sync.
  String exportProfilesJson(List<AutoEqProfile> profiles) {
    return json.encode(profiles.map((p) => p.toJson()).toList());
  }

  /// Imports profiles from JSON.
  List<AutoEqProfile> importProfilesJson(String jsonStr) {
    try {
      final decoded = json.decode(jsonStr) as List<dynamic>;
      return decoded
          .map((e) => AutoEqProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to parse imported AutoEQ JSON',
        error: e,
        stackTrace: st,
        category: 'AutoEqService',
      );
      return const [];
    }
  }
}
