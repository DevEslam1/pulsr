// F11: Playback position bookmarking (per-podcast / per-audiobook).
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PlaybackBookmark {
  final String trackKey;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  const PlaybackBookmark({
    required this.trackKey,
    required this.positionMs,
    this.durationMs = 0,
    required this.updatedAt,
  });

  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  /// Consider finished when within [finishWindow] of the end.
  bool isFinished({Duration finishWindow = const Duration(seconds: 30)}) =>
      durationMs > 0 && (durationMs - positionMs) <= finishWindow.inMilliseconds;

  Map<String, dynamic> toMap() => {
        'pos': positionMs,
        'dur': durationMs,
        'at': updatedAt.millisecondsSinceEpoch,
      };

  static PlaybackBookmark? fromMap(String key, Map<String, dynamic> m) {
    try {
      return PlaybackBookmark(
        trackKey: key,
        positionMs: (m['pos'] as num).toInt(),
        durationMs: (m['dur'] as num?)?.toInt() ?? 0,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Decides which tracks deserve bookmarks: long-form audio
/// (duration ≥ 10 min) or podcast/audiobook-ish genre.
class PlaybackBookmarkStore {
  static const String prefsKey = 'playback_bookmarks_v1';
  static const int maxEntries = 200;
  static const int minDurationMs = 10 * 60 * 1000;

  final Map<String, PlaybackBookmark> _bookmarks = {};

  Map<String, PlaybackBookmark> snapshot() => Map.unmodifiable(_bookmarks);

  static bool shouldBookmark({
    required int durationMs,
    String? genre,
    String? album,
  }) {
    if (durationMs >= minDurationMs) return true;
    final haystack =
        '${genre ?? ''} ${album ?? ''}'.toLowerCase();
    return haystack.contains('podcast') ||
        haystack.contains('audiobook') ||
        haystack.contains('audio book') ||
        haystack.contains('talk') ||
        haystack.contains('lecture');
  }

  static String keyFor({int? songId, String? remoteId, String? path}) {
    if (remoteId != null && remoteId.isNotEmpty) return 'yt:$remoteId';
    if (songId != null) return 'id:$songId';
    return 'path:${path ?? ''}';
  }

  void save(String trackKey, int positionMs, {int durationMs = 0}) {
    if (positionMs < 5000) return; // ignore trivial head positions
    _bookmarks.remove(trackKey);
    _bookmarks[trackKey] = PlaybackBookmark(
      trackKey: trackKey,
      positionMs: positionMs,
      durationMs: durationMs,
      updatedAt: DateTime.now(),
    );
    while (_bookmarks.length > maxEntries) {
      _bookmarks.remove(_bookmarks.keys.first);
    }
  }

  PlaybackBookmark? recall(String trackKey) {
    final b = _bookmarks[trackKey];
    if (b == null) return null;
    if (b.isFinished()) {
      _bookmarks.remove(trackKey);
      return null;
    }
    return b;
  }

  void remove(String trackKey) => _bookmarks.remove(trackKey);
  void clear() => _bookmarks.clear();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _bookmarks.clear();
      decoded.forEach((k, v) {
        if (v is Map) {
          final b = PlaybackBookmark.fromMap(k, Map<String, dynamic>.from(v));
          if (b != null) _bookmarks[k] = b;
        }
      });
    } catch (_) {}
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey,
          jsonEncode(_bookmarks.map((k, v) => MapEntry(k, v.toMap()))));
    } catch (_) {}
  }
}
