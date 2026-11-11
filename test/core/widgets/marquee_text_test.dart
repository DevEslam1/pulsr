import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/marquee_text.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) => MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Center(
            child: SizedBox(
              width: 120,
              height: 40,
              child: child,
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarqueeText Widget Tests', () {
    testWidgets('renders static text when text fits within bounds', (tester) async {
      await tester.pumpWidget(_wrap(
        const MarqueeText(text: 'Short'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Short'), findsOneWidget);
      // Fits within 120px, so no horizontal scroll view is instantiated
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('reduced-motion fallback displays static text with ellipsis without scrolling',
        (tester) async {
      const longTitle = 'Extremely Long Symphony Movement Opus 104 in D Minor With Extended Title';

      await tester.pumpWidget(_wrap(
        const MarqueeText(text: longTitle),
        disableAnimations: true, // Reduced motion
      ));
      await tester.pumpAndSettle();

      expect(find.text(longTitle), findsOneWidget);

      // Verify that no SingleChildScrollView is used for scrolling when animations are disabled
      expect(find.byType(SingleChildScrollView), findsNothing);

      // Verify static Text has ellipsis
      final textWidget = tester.widget<Text>(find.text(longTitle));
      expect(textWidget.overflow, equals(TextOverflow.ellipsis));
    });

    testWidgets('overflowing text renders marquee scroll layout when motion is enabled',
        (tester) async {
      const longTitle = 'Extremely Long Symphony Movement Opus 104 in D Minor With Extended Title';

      await tester.pumpWidget(_wrap(
        const MarqueeText(text: longTitle),
        disableAnimations: false,
      ));
      await tester.pump();

      expect(find.text(longTitle), findsOneWidget);
      // Overflowing text under normal motion instantiates SingleChildScrollView
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
