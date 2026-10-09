import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/home/presentation/widgets/discovery_chip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(body: Center(child: child)),
      );

  group('DiscoveryChip', () {
    testWidgets('renders its icon and label', (tester) async {
      await tester.pumpWidget(
        app(
          DiscoveryChip(
            icon: Icons.person_rounded,
            label: 'Artists',
            iconColor: Colors.purple,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Artists'), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('fires onTap when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        app(
          DiscoveryChip(
            icon: Icons.album_rounded,
            label: 'Albums',
            iconColor: Colors.orange,
            onTap: () => taps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DiscoveryChip));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
