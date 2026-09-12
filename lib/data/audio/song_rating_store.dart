// lib/data/audio/song_rating_store.dart
import 'dart:convert';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';

/// Persists user star ratings (1 to 5 stars, 0 = unrated) per song.
/// PowerAmp parity: allows rating songs and filtering/sorting by rating.
@singleton
class SongRatingStore {
  static const String prefsKey = 'song_ratings_v1';
  static const int maxEntries = 2000;

  final Map<String, int> _ratings = {};

  SongRatingStore() {
    load();
  }

  /// Returns rating 0..5 for [trackKey] (defaults to 0 / unrated).
  int getRating(String trackKey) => _ratings[trackKey] ?? 0;

  /// Sets star rating (0 to 5) for [trackKey]. Setting 0 removes rating.
  Future<void> setRating(String trackKey, int rating) async {
    final clamped = rating.clamp(0, 5);
    if (clamped == 0) {
      _ratings.remove(trackKey);
    } else {
      _ratings[trackKey] = clamped;
    }
    await persist();
  }

  void clearAll() {
    _ratings.clear();
    persist();
  }

  Map<String, int> snapshot() => Map.unmodifiable(_ratings);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _ratings.clear();
      decoded.forEach((k, v) {
        if (v is num) {
          final r = v.toInt().clamp(0, 5);
          if (r > 0) {
            _ratings[k] = r;
          }
        }
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to load song ratings',
          error: e, stackTrace: st, category: 'SongRatingStore');
    }
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_ratings.length > maxEntries) {
        final keysToRemove = _ratings.keys.take(_ratings.length - maxEntries).toList();
        for (final k in keysToRemove) {
          _ratings.remove(k);
        }
      }
      final encoded = jsonEncode(_ratings);
      await prefs.setString(prefsKey, encoded);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist song ratings',
          error: e, stackTrace: st, category: 'SongRatingStore');
    }
  }
}
