import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/breakpoints.dart';
import 'package:pulsr/core/responsive/detail_scaffold.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'package:pulsr/core/responsive/two_pane_scaffold.dart';
import 'package:pulsr/core/widgets/pulsr_search_field.dart';

void main() {
  group('PulsrLayoutMetrics Unit & Widget Tests', () {
    testWidgets('Resolves breakpoints correctly across tiers', (tester) async {
      late PulsrBreakpoint phonePortrait;
      late PulsrBreakpoint phoneLandscape;
      late PulsrBreakpoint tabletPortrait;
      late PulsrBreakpoint desktopLarge;

      // Phone portrait (390 x 844)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (ctx) {
              phonePortrait = PulsrBreakpoint.of(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      // Phone landscape (844 x 390)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(844, 390)),
          child: Builder(
            builder: (ctx) {
              phoneLandscape = PulsrBreakpoint.of(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      // Tablet portrait (768 x 1024)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(768, 1024)),
          child: Builder(
            builder: (ctx) {
              tabletPortrait = PulsrBreakpoint.of(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      // Large screen (1440 x 900)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1440, 900)),
          child: Builder(
            builder: (ctx) {
              desktopLarge = PulsrBreakpoint.of(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(phonePortrait, PulsrBreakpoint.compact);
      expect(phoneLandscape, PulsrBreakpoint.expanded);
      expect(tabletPortrait, PulsrBreakpoint.medium);
      expect(desktopLarge, PulsrBreakpoint.large);
    });

    testWidgets('contentMaxWidth scales appropriately per tier', (tester) async {
      late double phonePortraitMax;
      late double tabletPortraitMax;
      late double tabletLandscapeMax;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (ctx) {
              phonePortraitMax = PulsrLayoutMetrics.contentMaxWidth(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(768, 1024)),
          child: Builder(
            builder: (ctx) {
              tabletPortraitMax = PulsrLayoutMetrics.contentMaxWidth(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1200, 800)),
          child: Builder(
            builder: (ctx) {
              tabletLandscapeMax = PulsrLayoutMetrics.contentMaxWidth(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(phonePortraitMax, 640.0);
      expect(tabletPortraitMax, 720.0);
      expect(tabletLandscapeMax, 1000.0);
    });

    testWidgets('heroHeight scales with orientation and screen size', (tester) async {
      late double phonePortraitHero;
      late double phoneLandscapeHero;
      late double tabletPortraitHero;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Builder(
            builder: (ctx) {
              phonePortraitHero = PulsrLayoutMetrics.heroHeight(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 400)),
          child: Builder(
            builder: (ctx) {
              phoneLandscapeHero = PulsrLayoutMetrics.heroHeight(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 1200)),
          child: Builder(
            builder: (ctx) {
              tabletPortraitHero = PulsrLayoutMetrics.heroHeight(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(phonePortraitHero, inInclusiveRange(180.0, 300.0));
      expect(phoneLandscapeHero, inInclusiveRange(140.0, 220.0));
      expect(tabletPortraitHero, inInclusiveRange(220.0, 380.0));
    });

    testWidgets('isPlayerSplitMode cleanly distinguishes split vs single column', (tester) async {
      late bool phonePortraitSplit;
      late bool phoneLandscapeSplit;
      late bool tabletPortraitSplit;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (ctx) {
              phonePortraitSplit = PulsrLayoutMetrics.isPlayerSplitMode(
                ctx,
                const BoxConstraints(maxWidth: 390, maxHeight: 844),
              );
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(844, 390)),
          child: Builder(
            builder: (ctx) {
              phoneLandscapeSplit = PulsrLayoutMetrics.isPlayerSplitMode(
                ctx,
                const BoxConstraints(maxWidth: 844, maxHeight: 390),
              );
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(768, 1024)),
          child: Builder(
            builder: (ctx) {
              tabletPortraitSplit = PulsrLayoutMetrics.isPlayerSplitMode(
                ctx,
                const BoxConstraints(maxWidth: 768, maxHeight: 1024),
              );
              return const SizedBox();
            },
          ),
        ),
      );

      late bool tabletLandscapeSplit;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1024, 768)),
          child: Builder(
            builder: (ctx) {
              tabletLandscapeSplit = PulsrLayoutMetrics.isPlayerSplitMode(
                ctx,
                const BoxConstraints(maxWidth: 1024, maxHeight: 768),
              );
              return const SizedBox();
            },
          ),
        ),
      );

      expect(phonePortraitSplit, isFalse);
      expect(phoneLandscapeSplit, isTrue);
      expect(tabletPortraitSplit, isFalse);
      expect(tabletLandscapeSplit, isTrue);
    });

    testWidgets('shouldUseDialogForSheet routes properly', (tester) async {
      late bool phonePortraitSheet;
      late bool phoneLandscapeSheet;
      late bool tabletSheet;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (ctx) {
              phonePortraitSheet = PulsrLayoutMetrics.shouldUseDialogForSheet(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(844, 390)),
          child: Builder(
            builder: (ctx) {
              phoneLandscapeSheet = PulsrLayoutMetrics.shouldUseDialogForSheet(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(768, 1024)),
          child: Builder(
            builder: (ctx) {
              tabletSheet = PulsrLayoutMetrics.shouldUseDialogForSheet(ctx);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(phonePortraitSheet, isFalse); // Modal bottom sheet
      expect(phoneLandscapeSheet, isTrue); // Centered dialog
      expect(tabletSheet, isTrue); // Centered dialog
    });

    testWidgets('PulsrSearchField renders text field and clear button', (tester) async {
      final controller = TextEditingController(text: 'Queen');
      bool cleared = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulsrSearchField(
              controller: controller,
              hintText: 'Search songs...',
              onClear: () => cleared = true,
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Queen'), findsOneWidget);
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(cleared, isTrue);
    });

    testWidgets('DetailScaffold switches between single-pane and two-pane correctly', (tester) async {
      // Phone portrait: single column CustomScrollView
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: const DetailScaffold(
              hero: Text('Hero Header Widget'),
              body: Text('Body Item List'),
            ),
          ),
        ),
      );

      expect(find.text('Hero Header Widget'), findsOneWidget);
      expect(find.text('Body Item List'), findsOneWidget);
      expect(find.byType(Row), findsNothing);

      // Phone landscape: side-by-side Row split
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(844, 390)),
            child: const DetailScaffold(
              hero: Text('Hero Header Widget'),
              body: Text('Body Item List'),
            ),
          ),
        ),
      );

      expect(find.text('Hero Header Widget'), findsOneWidget);
      expect(find.text('Body Item List'), findsOneWidget);
      expect(find.byType(Row), findsOneWidget);
    });

    testWidgets('TwoPaneScaffold renders master and detail with hinge support', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1000, 800),
              displayFeatures: [
                DisplayFeature(
                  bounds: Rect.fromLTWH(490, 0, 20, 800),
                  type: DisplayFeatureType.hinge,
                  state: DisplayFeatureState.unknown,
                ),
              ],
            ),
            child: const Scaffold(
              body: TwoPaneScaffold(
                master: Text('Master List'),
                detail: Text('Detail View'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Master List'), findsOneWidget);
      expect(find.text('Detail View'), findsOneWidget);
      expect(find.byType(Row), findsOneWidget);
    });
  });
}
