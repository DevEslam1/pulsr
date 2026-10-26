import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/presentation/widgets/quran_mode_badge.dart';

void main() {
  testWidgets('QuranModeBadge renders text and book icon', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuranModeBadge(
            compact: true,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Quran Mode'), findsOneWidget);
    expect(find.byIcon(Icons.auto_stories_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

    await tester.tap(find.byType(QuranModeBadge));
    expect(tapped, isTrue);
  });
}
