// lib/features/player/cubit/queue_slot_codec.dart
import '../../../data/db/app_database.dart';

/// Read-only view of a queue slot for encoding. Lets the codec stay
/// independent of PlayerCubit's private slot type.
typedef SlotView = ({
  List<SongsTableData> songs,
  int currentIndex,
  Duration position,
  double speed,
});

/// Validated, decoded slot payload. Local song rows still need a repository
/// lookup by [songIds] (order-preserving); online-only rows are already
/// materialized in [onlineSongsById].
class DecodedSlot {
  final List<int> songIds;
  final Map<int, SongsTableData> onlineSongsById;
  final int currentIndex;
  final int positionMs;
  final double speed;

  const DecodedSlot({
    required this.songIds,
    required this.onlineSongsById,
    required this.currentIndex,
    required this.positionMs,
    required this.speed,
  });
}

/// Pure encode/decode/validation for the persisted queue slots (god-object
/// split): PlayerCubit keeps prefs/repository orchestration, abort guards and
/// state emission; all JSON mapping, validation and clamping lives here and is
/// unit tested. Semantics mirror the previous inline implementation exactly.
class QueueSlotCodec {
  static const int maxSlotIndex = 2;
  static const int maxDocumentKeys = 4; // three slots + activeSlot
  static const int maxPositionMs = 24 * 3600 * 1000;
  static const double minSpeed = 0.1;
  static const double maxSpeed = 8.0;

  static Map<String, dynamic> encodeDocument(
      Map<int, SlotView> slots, int activeSlot) {
    final data = <String, dynamic>{};
    for (final entry in slots.entries) {
      final songs = entry.value.songs;
      data['${entry.key}'] = {
        'songIds': songs.map((s) => s.id).toList(),
        'onlineSongs': songs
            .where((s) => s.source == SongSource.youtube || s.id < 0)
            .map((s) => {
                  'id': s.id,
                  'title': s.title,
                  'artist': s.artist,
                  'album': s.album,
                  'durationMs': s.durationMs,
                  'path': s.path,
                  'source': s.source,
                  'remoteId': s.remoteId,
                  'remoteArtworkUrl': s.remoteArtworkUrl,
                })
            .toList(),
        'currentIndex': entry.value.currentIndex,
        'positionMs': entry.value.position.inMilliseconds,
        'speed': entry.value.speed,
      };
    }
    // Which slot is active is part of the session: without it a restart
    // labels the restored queue as slot 0, and the next queue edit writes
    // over slot 0's saved contents.
    data['activeSlot'] = activeSlot;
    return data;
  }

  /// Validates the top-level document. Returns null when corrupt/oversized
  /// (DoS guard: three slots + activeSlot key).
  static Map<String, dynamic>? decodeDocument(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded.length > maxDocumentKeys) return null;
    return decoded;
  }

  /// Parses a restorable slot key ('0'..'2'); null for anything else.
  static int? slotIndexForKey(String key) {
    final i = int.tryParse(key);
    if (i == null || i < 0 || i > maxSlotIndex) return null;
    return i;
  }

  /// Validates one slot payload. Returns null when oversized, id-less or
  /// otherwise unusable — one corrupt slot must not abort the others.
  static DecodedSlot? decodeSlot(
      Map<String, dynamic> slotData, int maxQueueSize) {
    final rawIds = (slotData['songIds'] as List<dynamic>?) ?? [];
    if (rawIds.length > maxQueueSize) return null;
    final songIds = rawIds.whereType<int>().toList();
    if (songIds.isEmpty) return null;
    return DecodedSlot(
      songIds: songIds,
      onlineSongsById:
          decodeOnlineSongs((slotData['onlineSongs'] as List<dynamic>?) ?? []),
      currentIndex: (slotData['currentIndex'] as int?) ?? 0,
      positionMs: (slotData['positionMs'] as num?)?.toInt() ?? 0,
      speed: (slotData['speed'] as num?)?.toDouble() ?? 1.0,
    );
  }

  static Map<int, SongsTableData> decodeOnlineSongs(List<dynamic> raw) {
    final map = <int, SongsTableData>{};
    for (final item in raw) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        final id = m['id'] as int?;
        if (id != null) {
          map[id] = SongsTableData(
            id: id,
            title: m['title'] as String? ?? 'Unknown',
            artist: m['artist'] as String? ?? 'Unknown Artist',
            album: m['album'] as String? ?? '',
            durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
            path: m['path'] as String? ?? '',
            source: m['source'] as String? ?? SongSource.youtube,
            remoteId: m['remoteId'] as String?,
            remoteArtworkUrl: m['remoteArtworkUrl'] as String?,
            isFavorite: false,
            isMissing: false,
            isDownloaded: false,
            playCount: 0,
            lastPositionMs: 0,
          );
        }
      }
    }
    return map;
  }

  /// Re-maps repository rows to the persisted id order. `getSongsByIds`
  /// returns rows in unspecified (rowid) order; without this the restored slot
  /// would lose the real playback order (previous / current / next).
  static List<SongsTableData> mergeInPersistedOrder(
    List<int> ids,
    Map<int, SongsTableData> dbById,
    Map<int, SongsTableData> onlineById,
  ) {
    return [
      for (final id in ids)
        if (dbById[id] != null)
          dbById[id]!
        else if (onlineById[id] != null)
          onlineById[id]!,
    ];
  }

  static int clampCurrentIndex(int raw, int length) =>
      raw.clamp(0, length - 1);
  static Duration clampPosition(int ms) =>
      Duration(milliseconds: ms.clamp(0, maxPositionMs));
  static double clampSpeed(double v) =>
      v.isFinite ? v.clamp(minSpeed, maxSpeed) : 1.0;

  static int? activeSlotFrom(Object? raw) {
    if (raw is int && raw >= 0 && raw <= maxSlotIndex) return raw;
    return null;
  }
}
