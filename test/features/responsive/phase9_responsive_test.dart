// test/features/responsive/phase9_responsive_test.dart
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/adaptive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 9: Responsive & Platform Tests', () {
    testWidgets('Adaptive window classes and breakpoints', (tester) async {
      // 1. Compact (< 700dp)
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(Adaptive.windowOf(context), WindowClass.compact);
              expect(Adaptive.isTablet(context), isFalse);
              expect(context.isTwoPane, isFalse);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // 2. Medium / Tablet Portrait (768 x 1024)
      tester.view.physicalSize = const Size(768, 1024);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(Adaptive.windowOf(context), WindowClass.medium);
              expect(Adaptive.isTablet(context), isTrue);
              expect(context.isLandscape, isFalse);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // 3. Tablet Landscape / Two-Pane (1024 x 768)
      tester.view.physicalSize = const Size(1024, 768);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(Adaptive.windowOf(context), WindowClass.medium);
              expect(Adaptive.isTablet(context), isTrue);
              expect(context.isLandscape, isTrue);
              expect(context.isTwoPane, isTrue);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // 4. Expanded / Desktop (1440 x 900)
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(Adaptive.windowOf(context), WindowClass.expanded);
              expect(Adaptive.isTablet(context), isTrue);
              expect(context.isTwoPane, isTrue);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('Foldable hinge detection and layout adaptation', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const hingeFeature = DisplayFeature(
        bounds: Rect.fromLTWH(390, 0, 20, 600),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            displayFeatures: [hingeFeature],
          ),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                expect(context.hasHinge, isTrue);
                expect(context.hinge, isNotNull);
                expect(context.hinge!.bounds.width, 20.0);
                expect(context.hinge!.bounds.left, 390.0);

                // Build a hinge-aware two pane layout
                return Scaffold(
                  body: Row(
                    children: [
                      const SizedBox(
                        width: 390,
                        child: Text('Left Pane'),
                      ),
                      if (context.hasHinge)
                        SizedBox(
                          key: const Key('hinge-spacer'),
                          width: context.hinge!.bounds.width,
                        ),
                      const Expanded(
                        child: Text('Right Pane'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Left Pane'), findsOneWidget);
      expect(find.text('Right Pane'), findsOneWidget);
      expect(find.byKey(const Key('hinge-spacer')), findsOneWidget);
      final hingeSpacer = tester.getSize(find.byKey(const Key('hinge-spacer')));
      expect(hingeSpacer.width, 20.0);
    });
  });
}
