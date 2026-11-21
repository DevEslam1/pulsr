// lib/data/audio/eq_legacy_migration.dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/prefs_keys.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/eq_preset.dart';

/// One-time migration of persisted 5-band EQ data onto the 10-band plan.
///
/// Legacy 5-band gains are interpolated log-linearly from
/// [_legacyFrequencies] onto [EqPreset.centerFrequencies], exactly matching
/// the pre-10-band `EqPreset.interpolateGains` behavior. Already-migrated data
/// is left untouched, making [run] idempotent.
abstract class EqLegacyMigration {
  static const List<double> _legacyFrequencies = [60, 230, 910, 3600, 14000];

  /// Maps legacy 5-band [source] gains onto the 10 ISO centers.
  static List<double> to10Band(List<double> source) =>
      EqPreset.to10Band(source);

  /// Converts all persisted 5-band EQ data to 10 bands. Never throws; failures
  /// are logged via [ErrorLogger] so one corrupt key cannot block startup.
  static Future<void> run(SharedPreferences prefs) async {
    try {
      await _migrateEqGains(prefs);
      await _migrateCustomProfiles(prefs);
      await _migrateQuranSnapshot(prefs);
    } catch (e, st) {
      ErrorLogger.log('EQ legacy migration failed',
          error: e, stackTrace: st, category: 'EqLegacyMigration');
    }
  }

  static Future<void> _migrateEqGains(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString(PrefsKeys.eqGains);
      if (raw == null) return;
      final gains = _decodeLegacyGains(jsonDecode(raw));
      if (gains == null) return;
      await prefs.setString(PrefsKeys.eqGains, jsonEncode(to10Band(gains)));
    } catch (e, st) {
      ErrorLogger.log('Failed to migrate legacy 5-band EQ gains',
          error: e, stackTrace: st, category: 'EqLegacyMigration');
    }
  }

  static Future<void> _migrateCustomProfiles(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString(PrefsKeys.customEqProfiles);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      var changed = false;
      for (var i = 0; i < decoded.length; i++) {
        final item = decoded[i];
        if (item is! Map) continue;
        final profile = Map<String, dynamic>.from(item);
        // A profile that carries its own frequency table is a genuine
        // 5-band custom profile, not pre-10-band legacy data: leave it alone.
        if (profile['customFrequencies'] != null) continue;
        final gains = _decodeLegacyGains(profile['gains']);
        if (gains == null) continue;
        profile['gains'] = to10Band(gains);
        decoded[i] = profile;
        changed = true;
      }
      if (changed) {
        await prefs.setString(PrefsKeys.customEqProfiles, jsonEncode(decoded));
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to migrate legacy custom EQ profiles',
          error: e, stackTrace: st, category: 'EqLegacyMigration');
    }
  }

  static Future<void> _migrateQuranSnapshot(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString(PrefsKeys.quranRestoreSnapshot);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final snapshot = Map<String, dynamic>.from(decoded);
      final eqPreset = snapshot['eqPreset'];
      if (eqPreset is! Map) return;
      final eqMap = Map<String, dynamic>.from(eqPreset);
      final gains = _decodeLegacyGains(eqMap['gains']);
      if (gains == null) return;
      eqMap['gains'] = to10Band(gains);
      snapshot['eqPreset'] = eqMap;
      await prefs.setString(
          PrefsKeys.quranRestoreSnapshot, jsonEncode(snapshot));
    } catch (e, st) {
      ErrorLogger.log('Failed to migrate legacy Quran restore snapshot',
          error: e, stackTrace: st, category: 'EqLegacyMigration');
    }
  }

  static List<double>? _decodeLegacyGains(dynamic value) {
    if (value is! List || value.length != _legacyFrequencies.length) {
      return null;
    }
    final gains = <double>[];
    for (final e in value) {
      if (e is! num) return null;
      gains.add(e.toDouble());
    }
    return gains;
  }
}
