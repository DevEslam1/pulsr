import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/utils/adaptive.dart';
import 'package:pulsr/features/shell/presentation/bottom_nav_bar.dart';
import 'package:pulsr/features/shell/presentation/nav_destinations.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  group('Adaptive Tablet & Responsive Engine Tests', () {
    testWidgets(
        'Phone Portrait (400x800) returns phone posture and single track col',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
            ),
            child: Builder(
              builder: (context) {
                expect(context.isTablet, isFalse);
                expect(context.isTabletPortrait, isFalse);
                expect(context.isTabletLandscape, isFalse);
                expect(context.isLargeTablet, isFalse);
                expect(context.trackGridColumns, equals(1));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets(
        'Tablet Portrait (768x1024) returns tablet portrait posture and 2 track cols',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(768, 1024),
            ),
            child: Builder(
              builder: (context) {
                expect(context.isTablet, isTrue);
                expect(context.isTabletPortrait, isTrue);
                expect(context.isTabletLandscape, isFalse);
                expect(context.trackGridColumns, equals(2));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets(
        'Tablet Landscape (1024x768) returns tablet landscape posture and 2 track cols',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1024, 768),
            ),
            child: Builder(
              builder: (context) {
                expect(context.isTablet, isTrue);
                expect(context.isTabletPortrait, isFalse);
                expect(context.isTabletLandscape, isTrue);
                expect(context.isLargeTablet, isTrue);
                expect(context.trackGridColumns, equals(2));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('Large Widescreen (1440x900) returns 3 track columns',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1440, 900),
            ),
            child: Builder(
              builder: (context) {
                expect(context.isTablet, isTrue);
                expect(context.isTabletLandscape, isTrue);
                expect(context.isLargeTablet, isTrue);
                expect(context.trackGridColumns, equals(3));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('Tablet Portrait vs Landscape Two-Pane layout rule',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 1280),
            ),
            child: Builder(
              builder: (context) {
                // In tablet portrait, isTwoPane must be false to avoid horizontal squishing and overflow
                expect(context.isTwoPane, isFalse);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1280, 800),
            ),
            child: Builder(
              builder: (context) {
                // In tablet landscape, isTwoPane must be true for dual-pane presentation
                expect(context.isTwoPane, isTrue);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets(
        'PulsrBottomNavBar renders 4 primary destinations while tablet rail includes Settings',
        (tester) async {
      int selectedIdx = 0;
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 1280),
            ),
            child: Builder(
              builder: (context) {
                capturedContext = context;
                return Scaffold(
                  bottomNavigationBar: PulsrBottomNavBar(
                    currentIndex: selectedIdx,
                    onTap: (idx) => selectedIdx = idx,
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Verify the 4 primary dock destinations (Home, Library, Search, Playlists).
      expect(find.byType(PulsrBottomNavBar), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.byIcon(Icons.library_music_outlined), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_outlined), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);

      // Settings remains directly reachable in the 5-destination tablet rail.
      final railDests = pulsrRailDestinations(capturedContext);
      expect(railDests.length, equals(5));
      expect(
        railDests.any((d) => d.icon == Icons.settings_outlined),
        isTrue,
      );

      // Verify bottom nav bar height is strictly bounded and does not swallow the screen
      final navBarSize = tester.getSize(find.byType(PulsrBottomNavBar));
      expect(navBarSize.height, lessThan(120.0));
      expect(navBarSize.height, greaterThan(50.0));
    });
  });
}
