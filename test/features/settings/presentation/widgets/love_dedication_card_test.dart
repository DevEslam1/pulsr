import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/settings/presentation/widgets/love_dedication_card.dart';

void main() {
  Widget buildTestWidget() {
    return MaterialApp(
      theme: AuraTheme.darkTheme,
      home: const Scaffold(
        body: SingleChildScrollView(
          child: LoveDedicationCard(),
        ),
      ),
    );
  }

  testWidgets('LoveDedicationCard renders dedication elements',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.byType(LoveDedicationCard), findsOneWidget);
    expect(find.text('✨ SPECIAL DEDICATION'), findsOneWidget);
    expect(find.text('For Dr. Basbosa ❤️'), findsOneWidget);
    expect(find.text('Eng. Eslam ✨'), findsOneWidget);
    expect(find.text('Open Letter 💌'), findsOneWidget);
  });

  testWidgets('LoveDedicationCard opens love letter modal sheet on tap',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Letter 💌'));
    await tester.pumpAndSettle();

    expect(find.text('A Message for Dr. Basbosa ❤️'), findsOneWidget);
    expect(find.text('Tap to Send Love 💕'), findsOneWidget);

    // Tap to send love button
    await tester.tap(find.text('Tap to Send Love 💕'));
    await tester.pumpAndSettle();

    expect(find.text('Sent 1 Love Moments 💕'), findsOneWidget);
  });
}
