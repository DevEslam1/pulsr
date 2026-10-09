import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/home/presentation/widgets/quick_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: Center(child: SizedBox(width: 320, child: child)),
        ),
      );

  group('QuickTile', () {
    testWidgets('renders title, subtitle and icon', (tester) async {
      await tester.pumpWidget(
        app(
          QuickTile(
            title: 'Daily Drive',
            subtitle: 'Auto mix of favorites',
            icon: Icons.directions_car_rounded,
            color: Colors.blue,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Daily Drive'), findsOneWidget);
      expect(find.text('Auto mix of favorites'), findsOneWidget);
      expect(find.byIcon(Icons.directions_car_rounded), findsOneWidget);
    });

    testWidgets('fires onTap when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        app(
          QuickTile(
            title: 'Focus Flow',
            subtitle: 'Top played tracks',
            icon: Icons.headphones_rounded,
            color: Colors.green,
            onTap: () => taps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(QuickTile));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
