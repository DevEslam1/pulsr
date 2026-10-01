// test/features/library/duplicate_finder_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/library/presentation/widgets/duplicate_finder_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/test_song_factory.dart';

void main() {
  group('DuplicateFinderSheet Tests', () {
    final songFlac = createTestSong(
      id: 1,
      title: 'Comfortably Numb',
      artist: 'Pink Floyd',
      album: 'The Wall',
      durationMs: 382000,
      bitrateKbps: 950,
      path: '/storage/music/Comfortably Numb.flac',
      isFavorite: false,
    );

    final songMp3 = createTestSong(
      id: 2,
      title: 'comfortably numb',
      artist: 'Pink Floyd',
      album: 'The Wall',
      durationMs: 382000,
      bitrateKbps: 320,
      path: '/storage/music/Comfortably Numb.mp3',
      isFavorite: false,
    );

    final uniqueSong = createTestSong(
      id: 3,
      title: 'Time',
      artist: 'Pink Floyd',
      album: 'The Dark Side of the Moon',
      durationMs: 425000,
      bitrateKbps: 320,
      path: '/storage/music/Time.mp3',
      isFavorite: false,
    );

    testWidgets(
        'identifies duplicates and allows auto-selecting lower quality version',
        (tester) async {
      List<SongsTableData>? deletedItems;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DuplicateFinderSheet(
              allSongs: [songFlac, songMp3, uniqueSong],
              onDeleteSelected: (items) {
                deletedItems = items;
              },
            ),
          ),
        ),
      );

      expect(find.byType(DuplicateFinderSheet), findsOneWidget);
      expect(find.text('1 duplicate clusters found'), findsOneWidget);

      // Tap 'Keep this one' auto-selection button
      final keepBestBtn = find.text('Keep this one');
      expect(keepBestBtn, findsOneWidget);
      await tester.tap(keepBestBtn);
      await tester.pump();

      // Lower quality MP3 should be selected for removal
      final removeBtn = find.text('Remove Selected (1)');
      expect(removeBtn, findsOneWidget);

      await tester.tap(removeBtn);
      await tester.pump();

      expect(deletedItems, isNotNull);
      expect(deletedItems!.length, equals(1));
      expect(deletedItems!.first.id, equals(songMp3.id));
    });
  });
}
