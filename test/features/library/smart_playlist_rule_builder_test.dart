// test/features/library/smart_playlist_rule_builder_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/library/presentation/widgets/smart_playlist_rule_builder.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/test_song_factory.dart';

void main() {
  group('SmartPlaylistRuleBuilder Tests', () {
    final mockSong1 = createTestSong(
      id: 1,
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      album: 'A Night at the Opera',
      genre: 'Rock',
      year: 1975,
      durationMs: 354000,
      path: '/music/queen/bohemian_rhapsody.flac',
      isFavorite: true,
    );

    final mockSong2 = createTestSong(
      id: 2,
      title: 'Hotel California',
      artist: 'Eagles',
      album: 'Hotel California',
      genre: 'Classic Rock',
      year: 1976,
      durationMs: 391000,
      path: '/music/eagles/hotel_california.mp3',
      isFavorite: false,
    );

    test('SmartRule evaluates contains and equals operators correctly', () {
      final ruleArtist = SmartRule(
        field: SmartRuleField.artist,
        operator: SmartRuleOperator.contains,
        value: 'que',
      );
      expect(ruleArtist.evaluate(mockSong1), isTrue);
      expect(ruleArtist.evaluate(mockSong2), isFalse);

      final ruleYear = SmartRule(
        field: SmartRuleField.year,
        operator: SmartRuleOperator.greaterThan,
        value: '1975',
      );
      expect(ruleYear.evaluate(mockSong1), isFalse);
      expect(ruleYear.evaluate(mockSong2), isTrue);
    });

    testWidgets('renders rules and updates count accurately', (tester) async {
      List<SmartRule>? updatedRules;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SmartPlaylistRuleBuilder(
                previewSongs: [mockSong1, mockSong2],
                initialRules: [
                  SmartRule(
                    field: SmartRuleField.genre,
                    operator: SmartRuleOperator.contains,
                    value: 'Rock',
                  ),
                ],
                onRulesChanged: (rules) {
                  updatedRules = rules;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SmartPlaylistRuleBuilder), findsOneWidget);
      expect(find.text('2 matches'), findsOneWidget);

      // Tap Add Rule button
      final addBtn = find.text('Add Rule');
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pump();

      expect(updatedRules, isNotNull);
      expect(updatedRules!.length, equals(2));
    });
  });
}
