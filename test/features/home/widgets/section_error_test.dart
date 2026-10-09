import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/home/presentation/widgets/section_error.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupAppLocalizations(const Locale('en'));

  Widget app(Widget child) => MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      );

  group('SectionError', () {
    testWidgets('renders the error icon, message and retry action',
        (tester) async {
      await tester.pumpWidget(app(SectionError(onRetry: () {})));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text(l10n.libLoadFailed), findsOneWidget);
      expect(find.text(l10n.retry), findsOneWidget);
    });

    testWidgets('fires onRetry when the retry button is tapped',
        (tester) async {
      var retries = 0;
      await tester.pumpWidget(app(SectionError(onRetry: () => retries++)));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.retry));
      await tester.pump();

      expect(retries, 1);
    });
  });
}
