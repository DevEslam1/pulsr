// test/features/library/widgets/category_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/library/presentation/widgets/category_card.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: AuraTheme.darkTheme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('renders icon, title and subtitle with a chevron when unselected',
      (tester) async {
    await tester.pumpWidget(host(CategoryCard(
      icon: Icons.style_rounded,
      title: 'Rock',
      subtitle: '12 songs',
      color: Colors.red,
      onTap: () {},
    )));

    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('12 songs'), findsOneWidget);
    expect(find.byIcon(Icons.style_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });

  testWidgets('selected variant shows the check icon and selection semantics',
      (tester) async {
    await tester.pumpWidget(host(CategoryCard(
      icon: Icons.calendar_today_rounded,
      title: '2024',
      subtitle: '5 songs',
      color: Colors.blue,
      isSelected: true,
      onTap: () {},
    )));

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('tap invokes the onTap callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(CategoryCard(
      icon: Icons.style_rounded,
      title: 'Jazz',
      subtitle: '3 songs',
      color: Colors.green,
      onTap: () => taps++,
    )));

    await tester.tap(find.byType(CategoryCard));
    await tester.pump();

    expect(taps, 1);
  });
}
