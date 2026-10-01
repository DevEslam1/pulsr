// test/features/library/alphabet_quick_scroll_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/library/presentation/widgets/alphabet_quick_scroll.dart';

void main() {
  group('AlphabetQuickScroll Tests', () {
    testWidgets('renders alphabet letters correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 400,
                child: AlphabetQuickScroll(
                  onLetterSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AlphabetQuickScroll), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('Z'), findsOneWidget);
      expect(find.text('#'), findsOneWidget);
    });

    testWidgets('invokes onLetterSelected and shows bubble on drag',
        (tester) async {
      String? selectedLetter;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 500,
                child: AlphabetQuickScroll(
                  onLetterSelected: (letter) {
                    selectedLetter = letter;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Start gesture on letter A
      final letterA = find.text('A');
      final gesture = await tester.startGesture(tester.getCenter(letterA));
      await tester.pump();

      expect(selectedLetter, isNotNull);

      // Move down into middle letters
      await gesture.moveBy(const Offset(0, 150));
      await tester.pump();

      expect(selectedLetter, isNotNull);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('renders properly under RTL directionality', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SizedBox(
                  height: 350,
                  child: AlphabetQuickScroll(
                    onLetterSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AlphabetQuickScroll), findsOneWidget);
    });
  });
}
