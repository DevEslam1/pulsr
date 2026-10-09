// QuickCard and QuickActionsRow have no dedicated suite. This covers the card
// tap, the compact-width styling branch, and the three QuickActionsRow layouts
// (short-height horizontal strip, narrow 3-card two-row stack, and the
// standard equal-width row).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/home/presentation/widgets/quick_actions_row.dart';
import 'package:pulsr/features/home/presentation/widgets/quick_card.dart';

Widget _wrap(Widget child, {Size size = const Size(390, 844)}) => MaterialApp(
      theme: AuraTheme.darkTheme,
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: true),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('QuickCard renders its content and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(QuickCard(
      title: 'New Releases',
      subtitle: 'Fresh this week',
      icon: Icons.fiber_new_rounded,
      color: Colors.amber,
      onTap: () => taps++,
    )));

    expect(find.text('New Releases'), findsOneWidget);
    expect(find.text('Fresh this week'), findsOneWidget);

    await tester.tap(find.byType(QuickCard));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('QuickCard uses the compact styling below 380dp',
      (tester) async {
    await tester.pumpWidget(_wrap(
      QuickCard(
        title: 'Chill',
        subtitle: 'Lo-Fi',
        icon: Icons.spa_rounded,
        color: Colors.purple,
        onTap: () {},
      ),
      size: const Size(360, 800),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Chill'), findsOneWidget);
  });

  testWidgets('QuickActionsRow lays three cards in an equal-width row',
      (tester) async {
    await tester.pumpWidget(_wrap(QuickActionsRow(cards: [
      for (var i = 0; i < 3; i++) Text('Card $i'),
    ])));

    expect(find.byType(Expanded), findsNWidgets(3));
    expect(find.text('Card 2'), findsOneWidget);
  });

  testWidgets('QuickActionsRow stacks a narrow 3-card set into two rows',
      (tester) async {
    await tester.pumpWidget(_wrap(
      QuickActionsRow(cards: [for (var i = 0; i < 3; i++) Text('Card $i')]),
      size: const Size(340, 800),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Two cards in the first row, one card plus a trailing spacer in the second.
    expect(find.byType(Expanded), findsNWidgets(4));
    expect(find.text('Card 2'), findsOneWidget);
  });

  testWidgets('QuickActionsRow scrolls horizontally in a short landscape',
      (tester) async {
    await tester.pumpWidget(_wrap(
      QuickActionsRow(cards: [for (var i = 0; i < 3; i++) Text('Card $i')]),
      size: const Size(700, 400),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(Expanded), findsNothing);
  });
}
