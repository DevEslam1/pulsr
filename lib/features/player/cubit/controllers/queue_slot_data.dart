// lib/features/player/cubit/controllers/queue_slot_data.dart
export '../../../../core/utils/playlist_reorder_utils.dart'
    show calculateReorderedIndex, calculateRemovedIndex;

import '../../../../data/db/app_database.dart';

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

  const QueueSlotData({
    required this.songIds,
    required this.currentIndex,
    required this.position,
    this.speed = 1.0,
  });

  /// Hydrates [SongsTableData] model objects using the provided [lookup] map.
  List<SongsTableData> songsFrom(Map<int, SongsTableData> lookup) {
    return songIds.map((id) => lookup[id]).whereType<SongsTableData>().toList();
  }
}
