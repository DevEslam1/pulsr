// test/features/library/smart_playlist_rule_builder_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart' as domain;
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

    test(
        'bidirectional mapping between SmartRule and domain SmartRule is lossless',
        () {
      for (final field in SmartRuleField.values) {
        final domainField = field.toDomain();
        expect(SmartRuleField.fromDomain(domainField), equals(field));
      }

      for (final op in SmartRuleOperator.values) {
        final domainOp = op.toDomain();
        expect(SmartRuleOperator.fromDomain(domainOp), equals(op));
      }

      final originalRule = SmartRule(
        id: 'test_rule_1',
        field: SmartRuleField.title,
        operator: SmartRuleOperator.startsWith,
        value: 'Bohemian',
      );

      final domainRule = originalRule.toDomain();
      expect(domainRule.field, equals(domain.SmartRuleField.title));
      expect(domainRule.operator, equals(domain.SmartOperator.startsWith));
      expect(domainRule.value, equals('Bohemian'));

      final roundtripped =
          SmartRule.fromDomain(domainRule, id: originalRule.id);
      expect(roundtripped.id, equals(originalRule.id));
      expect(roundtripped.field, equals(originalRule.field));
      expect(roundtripped.operator, equals(originalRule.operator));
      expect(roundtripped.value, equals(originalRule.value));
    });

    testWidgets('deleting a rule leaves the remaining rule state intact',
        (tester) async {
      List<SmartRule>? currentRules;

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
                    id: 'rule_1',
                    field: SmartRuleField.artist,
                    operator: SmartRuleOperator.equals,
                    value: 'Queen',
                  ),
                  SmartRule(
                    id: 'rule_2',
                    field: SmartRuleField.year,
                    operator: SmartRuleOperator.greaterThan,
                    value: '1970',
                  ),
                ],
                onRulesChanged: (rules) {
                  currentRules = rules;
                },
              ),
            ),
          ),
        ),
      );

      // Verify initial rendering
      expect(find.byKey(const ValueKey('rule_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('rule_2')), findsOneWidget);
      expect(find.text('Queen'), findsOneWidget);
      expect(find.text('1970'), findsOneWidget);

      // Delete rule 1
      final deleteButtons =
          find.byIcon(Icons.remove_circle_outline_rounded);
      expect(deleteButtons, findsNWidgets(2));
      await tester.tap(deleteButtons.first);
      await tester.pump();

      // Rule 1 should be gone, Rule 2 should remain with its exact value
      expect(find.byKey(const ValueKey('rule_1')), findsNothing);
      expect(find.byKey(const ValueKey('rule_2')), findsOneWidget);
      expect(find.text('Queen'), findsNothing);
      expect(find.text('1970'), findsOneWidget);

      expect(currentRules, isNotNull);
      expect(currentRules!.length, equals(1));
      expect(currentRules!.first.id, equals('rule_2'));
      expect(currentRules!.first.value, equals('1970'));
    });
  });
}
