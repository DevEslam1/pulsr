import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/adaptive_grid.dart';

void main() {
  group('PulsrAdaptiveGrid', () {
    testWidgets('Calculates columns for album grid correctly across tiers',
        (tester) async {
      int? compactCols;
      int? mediumCols;
      int? expandedCols;
      int? largeCols;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              compactCols =
                  PulsrAdaptiveGrid.columns(context, type: GridType.albums);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(768, 1024)),
          child: Builder(
            builder: (context) {
              mediumCols =
                  PulsrAdaptiveGrid.columns(context, type: GridType.albums);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Expanded landscape (1024 x 768)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1024, 768)),
          child: Builder(
            builder: (context) {
              expandedCols =
                  PulsrAdaptiveGrid.columns(context, type: GridType.albums);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Large desktop (1440 x 900)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1440, 900)),
          child: Builder(
            builder: (context) {
              largeCols =
                  PulsrAdaptiveGrid.columns(context, type: GridType.albums);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(compactCols, 2);
      expect(mediumCols, 3);
      expect(expandedCols, 5); // 5 columns in landscape expanded
      expect(largeCols, 8);
    });

    testWidgets(
        'songColumns scales from 1 (compact) to 2 (medium/expanded) to 3 (large)',
        (tester) async {
      int? compactCols;
      int? mediumCols;
      int? largeCols;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              compactCols = PulsrAdaptiveGrid.songColumns(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(768, 1024)),
          child: Builder(
            builder: (context) {
              mediumCols = PulsrAdaptiveGrid.songColumns(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1440, 900)),
          child: Builder(
            builder: (context) {
              largeCols = PulsrAdaptiveGrid.songColumns(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(compactCols, 1);
      expect(mediumCols, 2);
      expect(largeCols, 3);
    });
  });
}
