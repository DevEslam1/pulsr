// test/features/home/home_quick_cards_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/pulsr_responsive_tokens.dart';
import 'package:pulsr/features/home/presentation/home_screen.dart';

void main() {
  Widget buildTestApp({required Size size, required Widget child}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: PulsrViewportScopeBuilder(
            builder: (context, vp) => Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  final testCards = [
    QuickCard(
      title: 'Favorites',
      subtitle: 'Liked tracks',
      icon: Icons.favorite_rounded,
      color: Colors.red,
      onTap: () {},
    ),
    QuickCard(
      title: 'Daily Drive',
      subtitle: 'Auto mix of favorites',
      icon: Icons.directions_car_rounded,
      color: Colors.blue,
      onTap: () {},
    ),
    QuickCard(
      title: 'Focus Flow',
      subtitle: 'Top played tracks and instruments',
      icon: Icons.headphones_rounded,
      color: Colors.green,
      onTap: () {},
    ),
  ];

  testWidgets(
      'QuickActionsRow in short height landscape (800x380) does not throw ParentDataWidget error',
      (tester) async {
    tester.view.physicalSize = const Size(800, 380);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestApp(
        size: const Size(800, 380),
        child: QuickActionsRow(cards: testCards),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Daily Drive'), findsOneWidget);
    expect(find.text('Focus Flow'), findsOneWidget);
  });

  testWidgets('QuickActionsRow in narrow portrait (320x600) does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestApp(
        size: const Size(320, 600),
        child: QuickActionsRow(cards: testCards),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Daily Drive'), findsOneWidget);
    expect(find.text('Focus Flow'), findsOneWidget);
  });

  testWidgets(
      'QuickActionsRow in standard portrait (390x844) does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestApp(
        size: const Size(390, 844),
        child: QuickActionsRow(cards: testCards),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Daily Drive'), findsOneWidget);
    expect(find.text('Focus Flow'), findsOneWidget);
  });
}
