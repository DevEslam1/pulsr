// lib/features/player/cubit/controllers/queue_slot_data.dart
import '../../../../data/db/app_database.dart';
import '../player_state.dart';

export '../../../../core/utils/playlist_reorder_utils.dart'
    show calculateReorderedIndex, calculateRemovedIndex;

/// Upper bound on the slot lookup cache.
const int maxSlotLookupCacheEntries = 4096;

/// Caches [songs] for slot hydration, marking each as the most recently written
/// entry (LRU-ish) and evicting the oldest unpinned entries beyond
/// [maxSlotLookupCacheEntries]. Songs in [pinnedSongIds] (for inactive slots Q2/Q3)
/// are pinned and skipped during LRU eviction so switching back never drops
/// tracks from another slot.
void cacheSlotSongs(
  Map<int, SongsTableData> cache,
  List<SongsTableData> songs, {
  Set<int> pinnedSongIds = const <int>{},
}) {
  for (final s in songs) {
    cache.remove(s.id);
    cache[s.id] = s;
  }
  var excess = cache.length - maxSlotLookupCacheEntries;
  if (excess <= 0) return;
  final keys = cache.keys.toList(growable: false);
  for (final key in keys) {
    if (excess <= 0) break;
    if (pinnedSongIds.contains(key)) continue;
    cache.remove(key);
    excess--;
  }
}

/// In-memory representation of a saved playback queue slot. The player keeps
/// 3 slots, indexed 0–2 (see QueueSlotCodec.maxSlotIndex).
class QueueSlotData {
  /// Ordered list of song database identifiers in the slot.
  final List<int> songIds;

  /// Current playback index within [songIds].
  final int currentIndex;

  /// Saved playback position duration.
  final Duration position;

  /// Saved playback rate / speed multiplier.
  final double speed;

  /// Queue tiers per track id.
  final Map<int, QueueTier> trackTiers;

  const QueueSlotData({
    required this.songIds,
    required this.currentIndex,
    required this.position,
    this.speed = 1.0,
    this.trackTiers = const {},
  });

  /// Hydrates [SongsTableData] model objects using the provided [lookup] map.
  List<SongsTableData> songsFrom(Map<int, SongsTableData> lookup) {
    return songIds.map((id) => lookup[id]).whereType<SongsTableData>().toList();
  }
}
