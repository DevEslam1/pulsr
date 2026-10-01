// lib/features/player/cubit/controllers/queue_slot_data.dart
import '../../../../data/db/app_database.dart';

/// In-memory representation of a saved playback queue slot (slots 1–9).
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

/// Computes the new active track index after a queue item reorder from [oldIndex] to [newIndex].
int calculateReorderedIndex(int oldIndex, int newIndex, int currentIndex) {
  if (currentIndex == oldIndex) return newIndex;
  if (oldIndex < currentIndex && newIndex >= currentIndex) return currentIndex - 1;
  if (oldIndex > currentIndex && newIndex <= currentIndex) return currentIndex + 1;
  return currentIndex;
}

/// Computes the new active track index after removing an item at [removedIndex].
int calculateRemovedIndex(int removedIndex, int currentIndex, int newQueueLength) {
  if (newQueueLength == 0) return 0;
  if (removedIndex < currentIndex) return currentIndex - 1;
  if (removedIndex == currentIndex) return currentIndex.clamp(0, newQueueLength - 1);
  return currentIndex;
}
