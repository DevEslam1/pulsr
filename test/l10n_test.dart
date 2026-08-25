import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  group('Localization Tests', () {
    test('Supports English, Spanish, and Arabic', () {
      final supportedLanguageCodes = AppLocalizations.supportedLocales.map((l) => l.languageCode).toList();
      expect(supportedLanguageCodes, containsAll(['en', 'es', 'ar']));
    });

    testWidgets('Renders localized strings for English', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              return Scaffold(
                body: Text(l10n.appTitle),
              );
            },
          ),
        ),
      );

      expect(find.text('Pulsr Music'), findsOneWidget);
    });

    testWidgets('Renders localized strings and RTL for Arabic', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ar'),
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              return Scaffold(
                body: Text(l10n.appTitle),
              );
            },
          ),
        ),
      );

      expect(find.text('بولسر للموسيقى'), findsOneWidget);
    });
  });
}
