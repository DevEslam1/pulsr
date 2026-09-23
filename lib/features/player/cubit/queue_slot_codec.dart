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
  static const int currentSchemaVersion = 1;
  static const int maxSlotIndex = 2;
  static const int maxDocumentKeys = (maxSlotIndex + 1) + 2; // slots + activeSlot + schemaVersion
  // FIX-L06: 7 days to support audiobooks and long podcasts
  static const int maxPositionMs = 7 * 24 * 3600 * 1000;
  static const double minSpeed = 0.1;
  static const double maxSpeed = 8.0;

  static Map<String, dynamic> encodeDocument(
      Map<int, SlotView> slots, int activeSlot) {
    final data = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
    };
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
                  // FIX-C05: Preserve favorite state across queue restore
                  'isFavorite': s.isFavorite,
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
  /// (DoS guard: three slots + activeSlot + schemaVersion key).
  static Map<String, dynamic>? decodeDocument(Object? decoded) {
    if (decoded is! Map) return null;
    if (decoded.length > maxDocumentKeys) return null;
    final map = Map<String, dynamic>.from(decoded);
    final version = map['schemaVersion'];
    if (version != null && (version is! int || version > currentSchemaVersion || version < 1)) {
      return null;
    }
    return map;
  }

  /// Parses a restorable slot key ('0'..'2'); null for anything else.
  static int? slotIndexForKey(String key) {
    if (key == 'schemaVersion' || key == 'activeSlot') return null;
    final i = int.tryParse(key);
    if (i == null || i < 0 || i > maxSlotIndex) return null;
    return i;
  }

  /// Validates one slot payload. Returns null when oversized, id-less or
  /// otherwise unusable — one corrupt slot must not abort the others.
  static DecodedSlot? decodeSlot(
      Map<String, dynamic> slotData, int maxQueueSize) {
    final rawIds = slotData['songIds'];
    if (rawIds is! List) return null;
    if (rawIds.length > maxQueueSize) return null;
    final songIds = rawIds.whereType<int>().toList();
    if (songIds.isEmpty) return null;

    final rawOnline = slotData['onlineSongs'];
    final onlineSongsById = rawOnline is List
        ? decodeOnlineSongs(rawOnline)
        : const <int, SongsTableData>{};

    final rawIndex = slotData['currentIndex'];
    final currentIndex = rawIndex is int ? rawIndex : 0;

    final rawPos = slotData['positionMs'];
    final positionMs =
        (rawPos is num) ? rawPos.toInt().clamp(0, maxPositionMs) : 0;

    final rawSpeed = slotData['speed'];
    final speed =
        (rawSpeed is num) ? rawSpeed.toDouble().clamp(minSpeed, maxSpeed) : 1.0;

    return DecodedSlot(
      songIds: songIds,
      onlineSongsById: onlineSongsById,
      currentIndex: currentIndex,
      positionMs: positionMs,
      speed: speed,
    );
  }

  static Map<int, SongsTableData> decodeOnlineSongs(List<dynamic> raw) {
    final map = <int, SongsTableData>{};
    for (final item in raw) {
      if (item is Map) {
        final id = item['id'];
        if (id is int) {
          map[id] = SongsTableData(
            id: id,
            title: item['title']?.toString() ?? 'Unknown',
            artist: item['artist']?.toString() ?? 'Unknown Artist',
            album: item['album']?.toString() ?? '',
            durationMs: (item['durationMs'] is num)
                ? (item['durationMs'] as num).toInt()
                : 0,
            path: item['path']?.toString() ?? '',
            source: item['source']?.toString() ?? SongSource.youtube,
            remoteId: item['remoteId']?.toString(),
            remoteArtworkUrl: item['remoteArtworkUrl']?.toString(),
            isFavorite: item['isFavorite'] == true,
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
