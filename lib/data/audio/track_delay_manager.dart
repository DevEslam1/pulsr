// F2: Per-track audio delay (sync offset, e.g. video/BT lipsync).
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-track delay in milliseconds, range -2000..+2000.
/// Positive = delay audio (audio lags video / BT sink lags).
class TrackDelayManager {
  static const String prefsKey = 'per_track_audio_delay_v1';
  static const int minMs = -2000;
  static const int maxMs = 2000;

  final Map<String, int> _delays = {};

  int getDelayMs(String trackKey) => _delays[trackKey] ?? 0;

  Duration compensatedPosition(String? trackKey, Duration raw) {
    if (trackKey == null) return raw;
    final d = getDelayMs(trackKey);
    if (d == 0) return raw;
    return Duration(milliseconds: (raw.inMilliseconds - d).clamp(0, 1 << 31));
  }

  void setDelay(String trackKey, int ms) {
    final clamped = ms.clamp(minMs, maxMs);
    if (clamped == 0) {
      _delays.remove(trackKey);
    } else {
      _delays[trackKey] = clamped;
    }
  }

  void clearDelay(String trackKey) => _delays.remove(trackKey);
  void clearAll() => _delays.clear();
  Map<String, int> snapshot() => Map.unmodifiable(_delays);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _delays.clear();
      decoded.forEach((k, v) {
        if (v is int && v >= minMs && v <= maxMs && v != 0) {
          _delays[k] = v;
        } else if (v is num) {
          final iv = v.toInt().clamp(minMs, maxMs);
          if (iv != 0) _delays[k] = iv;
        }
      });
      if (_delays.length > 500) {
        final keys = _delays.keys.toList();
        for (var i = 0; i < keys.length - 500; i++) {
          _delays.remove(keys[i]);
        }
      }
    } catch (_) {}
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode(_delays));
    } catch (_) {}
  }

  static String keyFor({int? songId, String? remoteId, String? path}) {
    if (remoteId != null && remoteId.isNotEmpty) return 'yt:$remoteId';
    if (songId != null) return 'id:$songId';
    return 'path:${path ?? ''}';
  }
}
