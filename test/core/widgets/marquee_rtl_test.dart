import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/marquee_text.dart';

void main() {
  testWidgets('MarqueeText renders and scrolls Arabic in RTL and English in LTR',
      (tester) async {
    const arabicLong =
        'إذاعة الشيخ محمد صديق المنشاوي (تلاوات نادرة ومحافل خاشعة)';
    const englishLong =
        'Very Long English Radio Station Name That Exceeds Container';
    const arabicShort = 'إذاعة القرآن';
    const englishShort = 'BBC News';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 140,
                child: MarqueeText(
                  text: arabicLong,
                  textAlign: TextAlign.start,
                ),
              ),
              SizedBox(
                width: 140,
                child: MarqueeText(
                  text: englishLong,
                  textAlign: TextAlign.start,
                ),
              ),
              SizedBox(
                width: 250,
                child: MarqueeText(
                  text: arabicShort,
                  textAlign: TextAlign.start,
                ),
              ),
              SizedBox(
                width: 250,
                child: MarqueeText(
                  text: englishShort,
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // The two long texts overflow and render SingleChildScrollView marquees
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));

    // Verify Arabic long text scroller has RTL Directionality
    final arabicFinder = find.ancestor(
      of: find.text(arabicLong),
      matching: find.byType(Directionality),
    );
    expect(arabicFinder, findsWidgets);
    final arabicDirectionality =
        tester.widget<Directionality>(arabicFinder.first);
    expect(arabicDirectionality.textDirection, TextDirection.rtl);

    // Verify English long text scroller has LTR Directionality
    final englishFinder = find.ancestor(
      of: find.text(englishLong),
      matching: find.byType(Directionality),
    );
    expect(englishFinder, findsWidgets);
    final englishDirectionality =
        tester.widget<Directionality>(englishFinder.first);
    expect(englishDirectionality.textDirection, TextDirection.ltr);

    // Static short texts render without SingleChildScrollView
    expect(find.text(arabicShort), findsOneWidget);
    expect(find.text(englishShort), findsOneWidget);
  });
}
