// Additional coverage for the responsive math that the primary responsive
// suites do not exercise: player split-mode decision matrix, sheet/dialog
// decision, hero/field metrics, dock-aware scroll padding, the fluid scale
// token ladder, hinge gaps, viewport computed tokens and adaptive-grid maths.
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/adaptive_grid.dart';
import 'package:pulsr/core/responsive/breakpoints.dart';
import 'package:pulsr/core/responsive/pulsr_fluid_scale.dart';
import 'package:pulsr/core/responsive/pulsr_hinge_gap.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'package:pulsr/core/responsive/pulsr_responsive_tokens.dart';
import 'package:pulsr/core/responsive/responsive_values.dart';
import 'package:pulsr/core/widgets/pulsr_dock_tracker.dart';

Future<BuildContext> pumpContext(
  WidgetTester tester,
  MediaQueryData data, {
  Widget Function(BuildContext)? builder,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: data,
        child: Builder(
          builder: (context) {
            captured = context;
            return builder?.call(context) ?? const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  group('PulsrLayoutMetrics.isPlayerSplitMode', () {
    testWidgets('rejects panes narrower than 620dp', (tester) async {
      final context = await pumpContext(
        tester,
        const MediaQueryData(size: Size(1200, 800)),
      );
      expect(
        PulsrLayoutMetrics.isPlayerSplitMode(
            context, const BoxConstraints(maxWidth: 500, maxHeight: 800)),
        isFalse,
      );
    });

    testWidgets('rejects near-square panes (taller than wide)', (tester) async {
      final context = await pumpContext(
        tester,
        const MediaQueryData(size: Size(700, 1000)),
      );
      // 700 <= 1000 * 1.15, so the horizontal split would crush both panes.
      expect(PulsrLayoutMetrics.isPlayerSplitMode(context), isFalse);
    });

    testWidgets('splits a wide landscape viewport', (tester) async {
      final context = await pumpContext(
        tester,
        const MediaQueryData(size: Size(900, 400)),
      );
      expect(PulsrLayoutMetrics.isPlayerSplitMode(context), isTrue);
    });

    testWidgets('splits a wide tablet with explicit short constraints',
        (tester) async {
      // MediaQuery is portrait/tablet; the supplied constraints describe a
      // short wide pane. This drives the final tablet >= 720 branch.
      final context = await pumpContext(
        tester,
        const MediaQueryData(size: Size(820, 1180)),
      );
      expect(
        PulsrLayoutMetrics.isPlayerSplitMode(
            context, const BoxConstraints(maxWidth: 800, maxHeight: 600)),
        isTrue,
      );
    });
  });

  group('PulsrLayoutMetrics.shouldUseDialogForSheet', () {
    testWidgets('keeps a bottom sheet on a compact phone portrait',
        (tester) async {
      final context = await pumpContext(
        tester,
        const MediaQueryData(size: Size(390, 844)),
      );
      expect(PulsrLayoutMetrics.shouldUseDialogForSheet(context), isFalse);
    });

    testWidgets('uses a dialog on tablets', (tester) async {
      final context = await pumpContext(
        tester,
        const MediaQueryData(size: Size(800, 1000)),
      );
      expect(PulsrLayoutMetrics.shouldUseDialogForSheet(context), isTrue);
    });

    testWidgets('uses a dialog on a short landscape phone', (tester) async {
      final context = await pumpContext(
        tester,
        const MediaQueryData(size: Size(844, 400)),
      );
      expect(PulsrLayoutMetrics.shouldUseDialogForSheet(context), isTrue);
    });
  });

  group('PulsrLayoutMetrics height/field/dock metrics', () {
    testWidgets('hero height clamps in landscape and portrait', (tester) async {
      final shortLandscape = await pumpContext(
        tester,
        const MediaQueryData(size: Size(1000, 300)),
      );
      expect(PulsrLayoutMetrics.heroHeight(shortLandscape), 180.0);

      final tallLandscape = await pumpContext(
        tester,
        const MediaQueryData(size: Size(1400, 700)),
      );
      expect(PulsrLayoutMetrics.heroHeight(tallLandscape), closeTo(294.0, 0.01));

      final tinyPortrait = await pumpContext(
        tester,
        const MediaQueryData(size: Size(400, 500)),
      );
      expect(PulsrLayoutMetrics.heroHeight(tinyPortrait), 220.0);

      final portrait = await pumpContext(
        tester,
        const MediaQueryData(size: Size(390, 844)),
      );
      expect(PulsrLayoutMetrics.heroHeight(portrait), closeTo(303.84, 0.01));
    });

    testWidgets('field height grows with text scaling', (tester) async {
      final normal = await pumpContext(
        tester,
        const MediaQueryData(size: Size(390, 844)),
      );
      expect(PulsrLayoutMetrics.fieldHeight(normal), 48.0);

      final scaled = await pumpContext(
        tester,
        const MediaQueryData(
          size: Size(390, 844),
          textScaler: TextScaler.linear(2.0),
        ),
      );
      expect(PulsrLayoutMetrics.fieldHeight(scaled), 72.0);
    });

    testWidgets('nav bar metrics differ for tablet and phone', (tester) async {
      final phone = await pumpContext(
        tester,
        const MediaQueryData(size: Size(390, 844)),
      );
      expect(PulsrLayoutMetrics.navBarHeight(phone), 64.0);
      expect(PulsrLayoutMetrics.navBarPaddingVertical(phone), 10.0);
      expect(PulsrLayoutMetrics.navBarTotalHeight(phone), 74.0);

      final tablet = await pumpContext(
        tester,
        const MediaQueryData(size: Size(800, 1000)),
      );
      expect(PulsrLayoutMetrics.navBarHeight(tablet), 68.0);
      expect(PulsrLayoutMetrics.navBarPaddingVertical(tablet), 14.0);
    });

    testWidgets('scrollBottom adds dock + safe area + extra', (tester) async {
      late double value;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(bottom: 20),
            ),
            child: PulsrDockScope(
              height: 50,
              child: Builder(
                builder: (context) {
                  value = PulsrLayoutMetrics.scrollBottom(context, extra: 10);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      expect(value, 80.0);
    });

    testWidgets('context extension mirrors the static metrics',
        (tester) async {
      late double maxWidth;
      late double hero;
      late double field;
      late double scroll;
      late bool split;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1024, 768)),
            child: Builder(
              builder: (context) {
                maxWidth = context.contentMaxWidth;
                hero = context.heroHeight;
                field = context.fieldHeight;
                scroll = context.scrollBottomPadding;
                split = context.isPlayerSplit();
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(maxWidth, PulsrBreakpoint.expanded.contentMaxWidth);
      expect(hero, 300.0);
      expect(field, 48.0);
      expect(scroll, 24.0);
      expect(split, isTrue);
    });
  });

  group('PulsrFluidScale token ladder', () {
    Future<PulsrFluidScale> fluidAt(WidgetTester tester, Size size) async {
      late PulsrFluidScale scale;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Builder(
              builder: (context) {
                scale = context.fluid;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return scale;
    }

    testWidgets('compact short landscape scales down to 0.85', (tester) async {
      final scale = await fluidAt(tester, const Size(560, 400));
      expect(scale.scale, 0.85);
      expect(scale.iconBox, closeTo(34.0, 0.01));
      expect(scale.controlBtn, 48.0); // clamped to the WCAG minimum
    });

    testWidgets('compact portrait stays at 1.0', (tester) async {
      final scale = await fluidAt(tester, const Size(390, 844));
      expect(scale.scale, 1.0);
      expect(scale.artworkSm, 44.0);
      expect(scale.artworkMd, 120.0);
      expect(scale.artworkLg, 160.0);
      expect(scale.rowHeight, 56.0);
      expect(scale.cardPadding, 16.0);
      expect(scale.sectionGap, 24.0);
    });

    testWidgets('medium tier stays at 1.0', (tester) async {
      final scale = await fluidAt(tester, const Size(700, 1000));
      expect(scale.scale, 1.0);
    });

    testWidgets('expanded tier scales up to 1.1', (tester) async {
      final scale = await fluidAt(tester, const Size(900, 1000));
      expect(scale.scale, closeTo(1.1, 0.0001));
      expect(scale.iconBox, closeTo(44.0, 0.01));
    });

    testWidgets('large tier scales up to 1.2', (tester) async {
      final scale = await fluidAt(tester, const Size(1300, 900));
      expect(scale.scale, closeTo(1.2, 0.0001));
      expect(scale.artworkMd, closeTo(144.0, 0.01));
      expect(scale.controlBtn, closeTo(57.6, 0.01));
    });
  });

  group('PulsrHingeGap', () {
    const hinge = DisplayFeature(
      bounds: Rect.fromLTWH(490, 0, 24, 800),
      type: DisplayFeatureType.hinge,
      state: DisplayFeatureState.unknown,
    );

    testWidgets('collapses when there is no hinge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(390, 844)),
            child: Center(child: PulsrHingeGap()),
          ),
        ),
      );
      expect(tester.getSize(find.byType(PulsrHingeGap)), Size.zero);
    });

    testWidgets('sizes to the hinge width when horizontal', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(1000, 800),
              displayFeatures: [hinge],
            ),
            child: Center(child: PulsrHingeGap.horizontal()),
          ),
        ),
      );
      expect(tester.getSize(find.byType(PulsrHingeGap)), const Size(24, 0));
    });

    testWidgets('collapses a zero-width horizontal hinge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(1000, 800),
              displayFeatures: [
                DisplayFeature(
                  bounds: Rect.fromLTWH(490, 0, 0, 800),
                  type: DisplayFeatureType.hinge,
                  state: DisplayFeatureState.unknown,
                ),
              ],
            ),
            child: Center(child: PulsrHingeGap.horizontal()),
          ),
        ),
      );
      expect(tester.getSize(find.byType(PulsrHingeGap)), Size.zero);
    });

    testWidgets('sizes to the hinge height when vertical', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(1000, 800),
              displayFeatures: [
                DisplayFeature(
                  bounds: Rect.fromLTWH(0, 390, 1000, 20),
                  type: DisplayFeatureType.fold,
                  state: DisplayFeatureState.unknown,
                ),
              ],
            ),
            child: Center(child: PulsrHingeGap.vertical()),
          ),
        ),
      );
      expect(tester.getSize(find.byType(PulsrHingeGap)), const Size(0, 20));
    });
  });

  group('PulsrViewport computed tokens', () {
    Future<PulsrViewport> viewportFor(WidgetTester tester, Size size) async {
      late PulsrViewport vp;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Builder(
              builder: (context) {
                vp = PulsrViewport.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return vp;
    }

    testWidgets('classifies phones, tablets and desktops', (tester) async {
      final phone = await viewportFor(tester, const Size(390, 844));
      expect(phone.deviceClass, PulsrDeviceClass.phone);
      expect(phone.isPhone, isTrue);
      expect(phone.isTablet, isFalse);
      expect(phone.isPortrait, isTrue);
      expect(phone.gridColumns, 2);
      expect(phone.cardRadiusScale, 1.0);
      expect(phone.navMode, PulsrNavMode.bottomBar);
      expect(phone.playerMode, PulsrPlayerMode.fullScreen);

      final tablet = await viewportFor(tester, const Size(800, 1000));
      expect(tablet.deviceClass, PulsrDeviceClass.tablet);
      expect(tablet.isTablet, isTrue);
      expect(tablet.gridColumns, 3);
      expect(tablet.cardRadiusScale, 1.08);
      expect(tablet.navMode, PulsrNavMode.sideRail);
      expect(tablet.playerMode, PulsrPlayerMode.fullScreen);

      final desktop = await viewportFor(tester, const Size(1400, 900));
      expect(desktop.deviceClass, PulsrDeviceClass.desktop);
      expect(desktop.isUltraWide, isTrue);
      expect(desktop.gridColumns, 5);
      expect(desktop.cardRadiusScale, 1.25);
      expect(desktop.navMode, PulsrNavMode.sideRailExtended);
      expect(desktop.playerMode, PulsrPlayerMode.splitPane);
    });

    testWidgets('classifies a foldable and its short-landscape posture',
        (tester) async {
      final foldable = await viewportFor(tester, const Size(1000, 800));
      // No hinge in the plain MediaQuery, so it is a tablet.
      expect(foldable.deviceClass, PulsrDeviceClass.tablet);

      final shortLandscape = await viewportFor(tester, const Size(560, 400));
      expect(shortLandscape.isShortHeight, isTrue);
      expect(shortLandscape.pagePadding, 12.0);
      expect(shortLandscape.gridColumns, 3);
      expect(shortLandscape.navMode, PulsrNavMode.bottomBar);
    });

    testWidgets('tablet landscape splits the player and extends the rail',
        (tester) async {
      final vp = await viewportFor(tester, const Size(1024, 768));
      expect(vp.sizeClass, PulsrBreakpoint.expanded);
      expect(vp.navMode, PulsrNavMode.sideRailExtended);
      expect(vp.playerMode, PulsrPlayerMode.splitPane);
    });

    testWidgets('equality and hashing cover every field', (tester) async {
      final a = await viewportFor(tester, const Size(390, 844));
      final b = await viewportFor(tester, const Size(390, 844));
      final c = await viewportFor(tester, const Size(391, 844));
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    testWidgets('PulsrViewportScopeBuilder supplies a scoped viewport',
        (tester) async {
      late PulsrViewport viaScope;
      late PulsrViewport viaExtension;
      await tester.pumpWidget(
        MaterialApp(
          home: PulsrViewportScopeBuilder(
            builder: (context, viewport) {
              viaScope = PulsrViewport.of(context);
              viaExtension = context.viewport;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(viaScope.width, viaExtension.width);
    });
  });

  group('PulsrAdaptiveGrid maths', () {
    testWidgets('large albums scale with a custom minimum width',
        (tester) async {
      late int standard;
      late int custom;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1400, 900)),
            child: Builder(
              builder: (context) {
                standard = PulsrAdaptiveGrid.columns(context);
                custom = PulsrAdaptiveGrid.columns(context,
                    customMinItemWidth: 200);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      // 1400 / 160 = 8 (clamped 6..8); 1400 / 200 = 7.
      expect(standard, 8);
      expect(custom, 7);
    });

    testWidgets('columnsFor clamps to explicit maxColumns', (tester) async {
      late int cols;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1400, 900)),
            child: Builder(
              builder: (context) {
                cols = PulsrAdaptiveGrid.columnsFor(context,
                    minItemWidth: 100, spacing: 0, maxColumns: 4);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(cols, 4);
    });

    testWidgets('dynamicColumns clamps within min and max', (tester) async {
      late int cols;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 844)),
            child: Builder(
              builder: (context) {
                cols = PulsrAdaptiveGrid.dynamicColumns(context,
                    minItemWidth: 5000, minColumns: 1, maxColumns: 8);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(cols, 1);
    });

    testWidgets('songColumns collapses below 520dp usable width',
        (tester) async {
      late int narrow;
      late int wide;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(480, 844)),
            child: Builder(
              builder: (context) {
                narrow = PulsrAdaptiveGrid.songColumns(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(900, 700)),
            child: Builder(
              builder: (context) {
                wide = PulsrAdaptiveGrid.songColumns(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(narrow, 1);
      expect(wide, 2);
    });

    testWidgets('preset helpers return positive column counts', (tester) async {
      late int albums;
      late int artists;
      late int songs;
      late int categories;
      late int playlists;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1200, 900)),
            child: Builder(
              builder: (context) {
                albums = PulsrAdaptiveGrid.albumGrid(context);
                artists = PulsrAdaptiveGrid.artistGrid(context);
                songs = PulsrAdaptiveGrid.songGrid(context);
                categories = PulsrAdaptiveGrid.categoryGrid(context);
                playlists = PulsrAdaptiveGrid.playlistGrid(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(albums, greaterThan(0));
      expect(artists, greaterThan(0));
      expect(songs, greaterThan(0));
      expect(categories, greaterThan(0));
      expect(playlists, greaterThan(0));
    });
  });

  group('ResponsiveValues fallbacks', () {
    test('falls back down the tier ladder', () {
      const values = ResponsiveValues<int>(compact: 1, medium: 2);
      expect(values.resolve(PulsrBreakpoint.compact), 1);
      expect(values.resolve(PulsrBreakpoint.medium), 2);
      expect(values.resolve(PulsrBreakpoint.expanded), 2);
      expect(values.resolve(PulsrBreakpoint.large), 2);
    });

    test('large prefers large then expanded then medium then compact', () {
      const values = ResponsiveValues<int>(compact: 1);
      expect(values.resolve(PulsrBreakpoint.large), 1);
    });
  });
}

