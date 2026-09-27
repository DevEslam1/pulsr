// test/responsive/responsive_device_matrix_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/breakpoints.dart';
import 'package:pulsr/core/responsive/pulsr_responsive_tokens.dart';
import 'package:pulsr/core/responsive/pulsr_fluid_scale.dart';
import 'package:pulsr/core/responsive/adaptive_grid.dart';
import 'package:pulsr/core/responsive/pulsr_viewport_debug_overlay.dart';

void main() {
  group('Prompt 13 Device Validation Matrix', () {
    final matrix = [
      (name: 'Pixel 7 Portrait', size: const Size(412, 915), expectedSizeClass: PulsrBreakpoint.compact, isShort: false),
      (name: 'Pixel 7 Landscape', size: const Size(915, 412), expectedSizeClass: PulsrBreakpoint.expanded, isShort: true),
      (name: 'Pixel Fold Closed Portrait', size: const Size(600, 820), expectedSizeClass: PulsrBreakpoint.medium, isShort: false),
      (name: 'Pixel Fold Closed Landscape', size: const Size(820, 600), expectedSizeClass: PulsrBreakpoint.medium, isShort: false),
      (name: 'Pixel Fold Open Portrait', size: const Size(820, 820), expectedSizeClass: PulsrBreakpoint.medium, isShort: false),
      (name: 'Nexus 7 Portrait', size: const Size(600, 960), expectedSizeClass: PulsrBreakpoint.medium, isShort: false),
      (name: 'Nexus 7 Landscape', size: const Size(960, 600), expectedSizeClass: PulsrBreakpoint.expanded, isShort: false),
      (name: 'Pixel Tablet Portrait', size: const Size(800, 1280), expectedSizeClass: PulsrBreakpoint.medium, isShort: false),
      (name: 'Pixel Tablet Landscape', size: const Size(1280, 800), expectedSizeClass: PulsrBreakpoint.large, isShort: false),
      (name: 'Pixel C Landscape', size: const Size(1280, 853), expectedSizeClass: PulsrBreakpoint.large, isShort: false),
      (name: 'Pixel C Portrait', size: const Size(853, 1280), expectedSizeClass: PulsrBreakpoint.expanded, isShort: false),
    ];

    for (final device in matrix) {
      testWidgets('Validates metrics for ${device.name}', (tester) async {
        tester.view.physicalSize = device.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        late PulsrViewport vp;
        late PulsrFluidScale fluid;

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: device.size),
              child: PulsrViewportScopeBuilder(
                builder: (context, resolvedVp) {
                  vp = resolvedVp;
                  fluid = context.fluid;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        expect(vp.sizeClass, device.expectedSizeClass, reason: '${device.name} sizeClass mismatch');
        expect(vp.isShortHeight, device.isShort, reason: '${device.name} isShortHeight mismatch');

        // Verify touch targets and fluid scales are safe
        expect(fluid.controlBtn, greaterThanOrEqualTo(PulsrFluidScale.minTouchTarget));
        expect(vp.contentMaxWidth, greaterThan(0));
        expect(vp.pagePadding, greaterThan(0));

        // Verify grid columns are reasonable
        final cols = PulsrAdaptiveGrid.albumGrid(tester.element(find.byType(SizedBox)));
        expect(cols, inInclusiveRange(1, 8));
      });
    }

    testWidgets('PulsrViewportDebugOverlay toggles minimized mode cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(412, 915)),
            child: PulsrViewportDebugOverlay(
              enabled: true,
              child: Container(color: Colors.black),
            ),
          ),
        ),
      );

      expect(find.textContaining('📐 412x915'), findsOneWidget);

      await tester.tap(find.textContaining('📐 412x915'));
      await tester.pumpAndSettle();

      expect(find.textContaining('VIEWPORT: 412 x 915'), findsOneWidget);
    });
  });
}
