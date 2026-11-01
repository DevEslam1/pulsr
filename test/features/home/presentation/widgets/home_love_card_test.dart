import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/home/presentation/widgets/home_love_card.dart';

void main() {
  Widget buildTestWidget() {
    return MaterialApp(
      theme: AuraTheme.darkTheme,
      home: const Scaffold(
        body: SingleChildScrollView(
          child: HomeLoveCard(),
        ),
      ),
    );
  }

  testWidgets('HomeLoveCard renders dedication header and quote',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.byType(HomeLoveCard), findsOneWidget);
    expect(find.text('Dr. Basbosa 💕'), findsOneWidget);
    expect(find.text('— Eng. Eslam ✨'), findsOneWidget);
    expect(find.text('Tap for wave of love 💌'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('HomeLoveCard cycles quote on tap without error',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Tap on the card to cycle quote and trigger wave
    await tester.tap(find.byType(HomeLoveCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(HomeLoveCard), findsOneWidget);
    expect(find.text('Dr. Basbosa 💕'), findsOneWidget);
  });
}

