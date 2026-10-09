import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/home/presentation/widgets/hero_mix_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: Center(child: SizedBox(width: 360, child: child)),
        ),
      );

  group('HeroMixCard', () {
    testWidgets('renders the uppercased overline, title and subtitle',
        (tester) async {
      await tester.pumpWidget(
        app(
          HeroMixCard(
            overline: 'Made for you',
            title: 'Daily Mix',
            subtitle: '12 songs',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MADE FOR YOU'), findsOneWidget);
      expect(find.text('Daily Mix'), findsOneWidget);
      expect(find.text('12 songs'), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    });

    testWidgets('uses the supplied icon when provided', (tester) async {
      await tester.pumpWidget(
        app(
          HeroMixCard(
            overline: 'Shuffle',
            title: 'All songs',
            subtitle: 'Everything',
            icon: Icons.shuffle_rounded,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
    });

    testWidgets('fires onTap when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        app(
          HeroMixCard(
            overline: 'Play',
            title: 'Hero',
            subtitle: 'Sub',
            onTap: () => taps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(HeroMixCard));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
