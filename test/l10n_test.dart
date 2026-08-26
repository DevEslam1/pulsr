import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/l10n_extensions.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  group('Localization Tests', () {
    test('Supports English, Spanish, and Arabic', () {
      final supportedLanguageCodes = AppLocalizations.supportedLocales.map((l) => l.languageCode).toList();
      expect(supportedLanguageCodes, containsAll(['en', 'es', 'ar']));
    });

    testWidgets('Renders localized strings and LTR for English', (tester) async {
      TextDirection? direction;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              direction = Directionality.of(context);
              return Scaffold(
                body: Column(
                  children: [
                    Text(context.l10n.appTitle),
                    Text(context.l10n.settings),
                    Text(context.l10n.songs),
                    Text(context.l10n.scanResult(5)),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(direction, equals(TextDirection.ltr));
      expect(find.text('Pulsr Music'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Found 5 songs'), findsOneWidget);
    });

    testWidgets('Renders localized strings and RTL for Arabic', (tester) async {
      TextDirection? direction;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ar'),
          home: Builder(
            builder: (context) {
              direction = Directionality.of(context);
              return Scaffold(
                body: Column(
                  children: [
                    Text(context.l10n.appTitle),
                    Text(context.l10n.settings),
                    Text(context.l10n.songs),
                    Text(context.l10n.scanResult(5)),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(direction, equals(TextDirection.rtl));
      expect(find.text('بولسر للموسيقى'), findsOneWidget);
      expect(find.text('الإعدادات'), findsOneWidget);
      expect(find.text('الأغاني'), findsOneWidget);
      expect(find.text('تم العثور على 5 أغنية'), findsOneWidget);
    });

    testWidgets('Renders localized strings and LTR for Spanish', (tester) async {
      TextDirection? direction;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('es'),
          home: Builder(
            builder: (context) {
              direction = Directionality.of(context);
              return Scaffold(
                body: Column(
                  children: [
                    Text(context.l10n.appTitle),
                    Text(context.l10n.settings),
                    Text(context.l10n.songs),
                    Text(context.l10n.scanResult(12)),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(direction, equals(TextDirection.ltr));
      expect(find.text('Pulsr Música'), findsOneWidget);
      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.text('Canciones'), findsOneWidget);
      expect(find.text('Se encontraron 12 canciones'), findsOneWidget);
    });
  });
}
