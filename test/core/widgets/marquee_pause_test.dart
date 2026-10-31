import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/marquee_text.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

/// WCAG 2.2.2 (Pause, Stop, Hide): an auto-scrolling title must be stoppable by
/// touch and by assistive technology, not only by mouse hover.
void main() {
  Widget harness(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: SizedBox(width: 120, child: child))),
      );

  const longText =
      'A very long track title that cannot possibly fit in one hundred pixels';

  testWidgets('overflowing marquee exposes a pause action and toggles',
      (tester) async {
    await tester.pumpWidget(harness(const MarqueeText(text: longText)));
    await tester.pump();

    final pause = find.byWidgetPredicate((w) =>
        w is Semantics && w.properties.hint == 'Pause scrolling title');
    expect(pause, findsOneWidget);
    expect(tester.widget<Semantics>(pause).properties.onTap, isNotNull);

    await tester.tap(pause);
    await tester.pump();

    final resume = find.byWidgetPredicate((w) =>
        w is Semantics && w.properties.hint == 'Resume scrolling title');
    expect(resume, findsOneWidget);
  });

  testWidgets('allowUserPause: false opts out of the action', (tester) async {
    await tester.pumpWidget(harness(
      const MarqueeText(text: longText, allowUserPause: false),
    ));
    await tester.pump();

    final anyPauseHint = find.byWidgetPredicate((w) =>
        w is Semantics &&
        (w.properties.hint == 'Pause scrolling title' ||
            w.properties.hint == 'Resume scrolling title'));
    expect(anyPauseHint, findsNothing);
  });
}
