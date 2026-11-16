// Locks the single modal-presentation policy shared by every sheet helper.
// Before this, PulsrSheetHelper kept bottom sheets on tablets while
// PulsrAdaptiveSheet/PulsrResponsiveSheet opened centered dialogs, and the
// readable content rail differed by up to 160dp between screens.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/detail_scaffold.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/utils/adaptive.dart';
import 'package:pulsr/core/widgets/pulsr_bottom_sheet.dart';

Widget _probe({
  required Size size,
  required void Function(BuildContext context) onBuild,
}) {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Builder(
        builder: (context) {
          onBuild(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
}

void main() {
  group('PulsrSheetMetrics presentation policy', () {
    testWidgets('phone portrait stays a bottom sheet', (tester) async {
      late PulsrViewportMetricsProbe probe;
      await tester.pumpWidget(_probe(
        size: const Size(390, 844),
        onBuild: (context) => probe = PulsrViewportMetricsProbe(context),
      ));

      expect(probe.presentAsDialog, isFalse);
      expect(probe.dialogWidth, 420);
      expect(probe.sheetWidth, double.infinity);
    });

    testWidgets('medium tablet portrait keeps the clamped bottom sheet',
        (tester) async {
      late PulsrViewportMetricsProbe probe;
      await tester.pumpWidget(_probe(
        size: const Size(768, 1024),
        onBuild: (context) => probe = PulsrViewportMetricsProbe(context),
      ));

      expect(probe.presentAsDialog, isFalse);
      expect(probe.dialogWidth, 520);
      expect(probe.sheetWidth, PulsrSheetMetrics.tabletSheetWidth);
    });

    testWidgets('expanded tablet portrait presents a centered dialog',
        (tester) async {
      late PulsrViewportMetricsProbe probe;
      await tester.pumpWidget(_probe(
        size: const Size(840, 1200),
        onBuild: (context) => probe = PulsrViewportMetricsProbe(context),
      ));

      expect(probe.presentAsDialog, isTrue);
      expect(probe.dialogWidth, 600);
    });

    testWidgets('just under tablet width stays a bottom sheet', (tester) async {
      late PulsrViewportMetricsProbe probe;
      await tester.pumpWidget(_probe(
        size: const Size(599, 960),
        onBuild: (context) => probe = PulsrViewportMetricsProbe(context),
      ));

      expect(probe.presentAsDialog, isFalse);
    });

    testWidgets('tablet landscape presents a centered dialog', (tester) async {
      late PulsrViewportMetricsProbe probe;
      await tester.pumpWidget(_probe(
        size: const Size(1024, 768),
        onBuild: (context) => probe = PulsrViewportMetricsProbe(context),
      ));

      expect(probe.presentAsDialog, isTrue);
      expect(probe.dialogWidth, 600);
      expect(probe.sheetWidth, PulsrSheetMetrics.tabletSheetWidth);
    });

    testWidgets('desktop and short landscape use dialogs', (tester) async {
      late PulsrViewportMetricsProbe desktop;
      await tester.pumpWidget(_probe(
        size: const Size(1440, 900),
        onBuild: (context) => desktop = PulsrViewportMetricsProbe(context),
      ));
      expect(desktop.presentAsDialog, isTrue);
      expect(desktop.dialogWidth, 640);

      late PulsrViewportMetricsProbe shortLandscape;
      await tester.pumpWidget(_probe(
        size: const Size(844, 390),
        onBuild: (context) =>
            shortLandscape = PulsrViewportMetricsProbe(context),
      ));
      expect(shortLandscape.presentAsDialog, isTrue);
      expect(shortLandscape.dialogWidth,
          PulsrSheetMetrics.shortLandscapeDialogWidth);
      expect(shortLandscape.dialogHeight, closeTo(390 * 0.88, 0.01));
    });
  });

  group('canonical readable content rail', () {
    testWidgets('Adaptive.contentConstraints matches breakpoint widths',
        (tester) async {
      late double phoneWidth;
      await tester.pumpWidget(_probe(
        size: const Size(390, 844),
        onBuild: (context) =>
            phoneWidth = Adaptive.contentConstraints(context).maxWidth,
      ));
      expect(phoneWidth, 640);

      late double tabletPortraitWidth;
      await tester.pumpWidget(_probe(
        size: const Size(768, 1024),
        onBuild: (context) =>
            tabletPortraitWidth = Adaptive.contentConstraints(context).maxWidth,
      ));
      expect(tabletPortraitWidth, 720);

      late double desktopWidth;
      await tester.pumpWidget(_probe(
        size: const Size(1440, 900),
        onBuild: (context) =>
            desktopWidth = Adaptive.contentConstraints(context).maxWidth,
      ));
      expect(desktopWidth, 1000);

      late double shortLandscapeWidth;
      await tester.pumpWidget(_probe(
        size: const Size(994, 456),
        onBuild: (context) =>
            shortLandscapeWidth = Adaptive.contentConstraints(context).maxWidth,
      ));
      // Short landscape keeps the full width so camera cutouts and the wide
      // dock are not double-padded by a centered rail.
      expect(shortLandscapeWidth, 994);
    });
  });

  group('modal entry points', () {
    testWidgets('PulsrSheetHelper uses a real dialog on tablet landscape',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => PulsrSheetHelper.showPulsrSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(
                    height: 160,
                    child: Center(child: Text('Tablet modal')),
                  ),
                ),
                child: const Text('Open modal'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open modal'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Tablet modal'), findsOneWidget);

      // Untitled custom sheets still get an explicit dismiss affordance.
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Tablet modal'), findsNothing);
    });

    testWidgets('DetailScaffold keeps tablet portrait single-pane',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AuraTheme.darkTheme,
        home: const MediaQuery(
          data: MediaQueryData(size: Size(800, 1280)),
          child: DetailScaffold(
            hero: Text('Hero Header Widget'),
            body: Text('Body Item List'),
          ),
        ),
      ));

      expect(find.text('Hero Header Widget'), findsOneWidget);
      expect(find.text('Body Item List'), findsOneWidget);
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('full-bleed custom sheets keep their own chrome on tablet',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => PulsrSheetHelper.showPulsrSheet<void>(
                  context: context,
                  wrapWithContainer: false,
                  builder: (_) => const Material(
                    child: SizedBox(
                      height: 200,
                      child: Center(child: Text('Full-bleed sheet')),
                    ),
                  ),
                ),
                child: const Text('Open custom sheet'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open custom sheet'));
      await tester.pumpAndSettle();

      // No dialog wrapper: the builder owns the surface and drag handle.
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Full-bleed sheet'), findsOneWidget);

      Navigator.of(tester.element(find.text('Full-bleed sheet'))).pop();
      await tester.pumpAndSettle();
    });
  });
}

class PulsrViewportMetricsProbe {
  final bool presentAsDialog;
  final double dialogWidth;
  final double dialogHeight;
  final double sheetWidth;

  PulsrViewportMetricsProbe(BuildContext context)
      : presentAsDialog = PulsrSheetMetrics.shouldPresentAsDialog(context),
        dialogWidth = PulsrSheetMetrics.dialogMaxWidth(context),
        dialogHeight = PulsrSheetMetrics.dialogMaxHeight(context),
        sheetWidth = PulsrSheetMetrics.sheetMaxWidth(context);
}
