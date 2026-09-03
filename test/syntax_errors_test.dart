import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/empty_state_widget.dart';
import 'package:pulsr/domain/services/duplicate_finder_service.dart';

void main() {
  group('Phase 0 Syntax Errors Regression Tests (B-26..B-30)', () {
    test('EmptyStateWidget compiles with isPrimaryLoading and valid button children', () {
      const widget = EmptyStateWidget(
        icon: Icons.music_note,
        title: 'Empty',
        subtitle: 'No items found',
        isPrimaryLoading: false,
        primaryActionLabel: 'Action',
      );
      expect(widget.isPrimaryLoading, isFalse);
      expect(widget.title, equals('Empty'));
      expect(widget.subtitle, equals('No items found'));
    });

    test('DuplicateGroup model can be instantiated cleanly', () {
      const group = DuplicateGroup(
        key: 'artist_title',
        songs: [],
        reason: 'Identical metadata',
      );
      expect(group.key, 'artist_title');
      expect(group.reason, 'Identical metadata');
      expect(group.songs, isEmpty);
    });
  });
}
