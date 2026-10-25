import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/playlist_reorder_utils.dart';

void main() {
  // Flutter's onReorderItem reports the dragged item's final index after it
  // has been removed from the list.
  List<String> move(
    List<String> items,
    int oldIndex,
    int newIndex, {
    Set<String> selected = const {},
  }) {
    return applyPlaylistReorder(
      items: items,
      oldIndex: oldIndex,
      newIndex: newIndex,
      isSelected: selected.contains,
    );
  }

  group('applyPlaylistReorder', () {
    test('moves a single item down', () {
      expect(move(['A', 'B', 'C', 'D', 'E'], 1, 3), ['A', 'C', 'D', 'B', 'E']);
    });

    test('moves a single item up', () {
      expect(move(['A', 'B', 'C', 'D', 'E'], 3, 1), ['A', 'D', 'B', 'C', 'E']);
    });

    test('does nothing for an unchanged index', () {
      expect(move(['A', 'B', 'C'], 1, 1), ['A', 'B', 'C']);
    });

    test('moves the whole selection when the dragged item is selected', () {
      expect(
        move(['A', 'B', 'C', 'D', 'E'], 1, 3, selected: {'B', 'C'}),
        ['A', 'D', 'B', 'C', 'E'],
      );
    });

    test('group move up preserves the selection order', () {
      expect(
        move(['A', 'B', 'C', 'D', 'E'], 3, 1, selected: {'B', 'D'}),
        ['A', 'B', 'D', 'C', 'E'],
      );
    });

    test('dragging an unselected item moves only that item', () {
      expect(
        move(['A', 'B', 'C', 'D'], 2, 0, selected: {'D'}),
        ['C', 'A', 'B', 'D'],
      );
    });

    test('clamps a drop past the end', () {
      expect(move(['A', 'B', 'C'], 0, 10), ['B', 'C', 'A']);
    });
  });

  group('moveSelectedToEdge', () {
    test('moves selected items to the top in their existing order', () {
      expect(
        moveSelectedToEdge(
          items: ['A', 'B', 'C', 'D'],
          isSelected: (item) => item == 'B' || item == 'D',
          toTop: true,
        ),
        ['B', 'D', 'A', 'C'],
      );
    });

    test('moves selected items to the bottom in their existing order', () {
      expect(
        moveSelectedToEdge(
          items: ['A', 'B', 'C', 'D'],
          isSelected: (item) => item == 'B' || item == 'D',
          toTop: false,
        ),
        ['A', 'C', 'B', 'D'],
      );
    });

    test('returns the original list when nothing is selected', () {
      final items = ['A', 'B'];
      expect(
        moveSelectedToEdge(
          items: items,
          isSelected: (_) => false,
          toTop: true,
        ),
        same(items),
      );
    });
  });

  group('moveSelectedToPosition', () {
    test('moves single item to position 0 (#1)', () {
      expect(
        moveSelectedToPosition(
          items: ['A', 'B', 'C', 'D', 'E'],
          isSelected: (item) => item == 'C',
          targetIndex: 0,
        ),
        ['C', 'A', 'B', 'D', 'E'],
      );
    });

    test('moves single item to position 4 (#5)', () {
      expect(
        moveSelectedToPosition(
          items: ['A', 'B', 'C', 'D', 'E'],
          isSelected: (item) => item == 'B',
          targetIndex: 4,
        ),
        ['A', 'C', 'D', 'E', 'B'],
      );
    });

    test('moves multiple selected items as a block to target position', () {
      expect(
        moveSelectedToPosition(
          items: ['A', 'B', 'C', 'D', 'E'],
          isSelected: (item) => item == 'A' || item == 'D',
          targetIndex: 2,
        ),
        ['B', 'C', 'A', 'D', 'E'],
      );
    });

    test('clamps targetIndex to list bounds', () {
      expect(
        moveSelectedToPosition(
          items: ['A', 'B', 'C'],
          isSelected: (item) => item == 'A',
          targetIndex: 99,
        ),
        ['B', 'C', 'A'],
      );
      expect(
        moveSelectedToPosition(
          items: ['A', 'B', 'C'],
          isSelected: (item) => item == 'C',
          targetIndex: -5,
        ),
        ['C', 'A', 'B'],
      );
    });
  });
}
