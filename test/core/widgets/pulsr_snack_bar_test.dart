import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_dock_tracker.dart';
import 'package:pulsr/core/widgets/pulsr_toast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PulsrDockTracker.updateDock(height: 0.0, miniPlayer: false);
    PulsrDockTracker.setNowPlayingOpen(false);
  });

  group('PulsrSnackBar (PulsrToast redesign)', () {
    testWidgets('renders floating SnackBar with message, title, and icon badge',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PulsrSnackBar.show(
                    context,
                    title: 'Queue Updated',
                    message: 'Added 3 tracks to playback queue',
                    icon: Icons.queue_music_rounded,
                  );
                },
                child: const Text('Show SnackBar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show SnackBar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Queue Updated'), findsOneWidget);
      expect(find.text('Added 3 tracks to playback queue'), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Settle auto dismiss
      await tester.pump(const Duration(milliseconds: 2500));
    });

    testWidgets('supports action button and fires onActionPressed callback',
        (tester) async {
      bool actionFired = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PulsrSnackBar.show(
                    context,
                    message: 'Removed from playlist',
                    actionLabel: 'UNDO',
                    onActionPressed: () {
                      actionFired = true;
                    },
                  );
                },
                child: const Text('Trigger Action SnackBar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Action SnackBar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('UNDO'), findsOneWidget);
      await tester.tap(find.text('UNDO'));
      await tester.pump();
      expect(actionFired, isTrue);

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('tapping close icon dismisses the SnackBar immediately',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PulsrSnackBar.show(
                    context,
                    message: 'Test dismiss message',
                  );
                },
                child: const Text('Show SnackBar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show SnackBar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Test dismiss message'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Test dismiss message'), findsNothing);
    });

    testWidgets(
        'dynamically positions SnackBar above the bottom dock when dock height is tracked',
        (tester) async {
      PulsrDockTracker.updateDock(height: 158.0, miniPlayer: true);

      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PulsrSnackBar.show(
                    context,
                    message: 'Positioned above mini player',
                  );
                },
                child: const Text('Show SnackBar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show SnackBar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Positioned above mini player'), findsOneWidget);

      final animatedPadding = tester.widget<AnimatedPadding>(
        find.ancestor(
          of: find.text('Positioned above mini player'),
          matching: find.byType(AnimatedPadding),
        ),
      );

      // Bottom padding should include dockHeight (158.0) + 12.0 margin = 170.0
      final padding = animatedPadding.padding as EdgeInsetsDirectional;
      expect(padding.bottom, greaterThanOrEqualTo(170.0));

      await tester.pump(const Duration(milliseconds: 2500));
    });

    testWidgets('error variant applies error status icon and palette',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PulsrSnackBar.show(
                    context,
                    message: 'Playback failure occurred',
                    isError: true,
                  );
                },
                child: const Text('Show Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Playback failure occurred'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2500));
    });
  });
}
