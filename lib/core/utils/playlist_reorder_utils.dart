/// Applies a drag result where [newIndex] is the final index of the dragged
/// item after it is removed from the list (Flutter's `onReorderItem`).
///
/// When the dragged item is selected, every selected item moves together as a
/// block, preserving their relative order. Dropping a non-selected item moves
/// only that item.
List<T> applyPlaylistReorder<T>({
  required List<T> items,
  required int oldIndex,
  required int newIndex,
  required bool Function(T item) isSelected,
}) {
  if (oldIndex < 0 || oldIndex >= items.length) return items;
  if (items.length < 2) return items;

  final target = newIndex.clamp(0, items.length - 1);
  final draggedSelected = isSelected(items[oldIndex]);
  final movingIndices = <int>[];
  if (draggedSelected) {
    for (var i = 0; i < items.length; i++) {
      if (isSelected(items[i])) movingIndices.add(i);
    }
  } else {
    movingIndices.add(oldIndex);
  }
  final movingSet = movingIndices.toSet();
  final moving = [for (final index in movingIndices) items[index]];
  final remaining = <T>[
    for (var i = 0; i < items.length; i++)
      if (!movingSet.contains(i)) items[i],
  ];

  // `target` is expressed in a list where only the dragged item has been
  // removed. The other selected items are leaving too, so shift left for each
  // of them that sat before the drop point.
  var destination = target;
  for (final index in movingIndices) {
    if (index != oldIndex && index < target) destination--;
  }
  destination = destination.clamp(0, remaining.length);
  remaining.insertAll(destination, moving);
  return remaining;
}

/// Moves every selected item to the start or end of the list, preserving the
/// selection's internal order.
List<T> moveSelectedToEdge<T>({
  required List<T> items,
  required bool Function(T item) isSelected,
  required bool toTop,
}) {
  final selected = <T>[];
  final rest = <T>[];
  for (final item in items) {
    if (isSelected(item)) {
      selected.add(item);
    } else {
      rest.add(item);
    }
  }
  if (selected.isEmpty) return items;
  return toTop ? [...selected, ...rest] : [...rest, ...selected];
}

/// Moves every selected item to [targetIndex] (0-based) as a contiguous block,
/// preserving their relative order.
///
/// Clamps [targetIndex] between 0 and `remaining.length`.
List<T> moveSelectedToPosition<T>({
  required List<T> items,
  required bool Function(T item) isSelected,
  required int targetIndex,
}) {
  if (items.isEmpty) return items;
  final moving = <T>[];
  final remaining = <T>[];
  for (final item in items) {
    if (isSelected(item)) {
      moving.add(item);
    } else {
      remaining.add(item);
    }
  }
  if (moving.isEmpty) return items;
  final destination = targetIndex.clamp(0, remaining.length);
  remaining.insertAll(destination, moving);
  return remaining;
}
