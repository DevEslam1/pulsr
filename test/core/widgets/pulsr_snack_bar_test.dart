import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    testWidgets(
        'identical repeated error messages extend the visible toast instead of re-showing it',
        (tester) async {
      // A failure cascade (network drop, bot block) fires the same message once
      // per retry/skip. Each event used to re-insert the banner: a fresh slide
      // animation and another heavy haptic + error cue per event.
      final hapticCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') hapticCalls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      const message = 'No connection. Check your network.';
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PulsrToast.show(
                  context,
                  message: message,
                  isError: true,
                ),
                child: const Text('Show Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(message), findsOneWidget);
      expect(hapticCalls, hasLength(1));
      final firstElement = tester.element(find.text(message));

      // The identical error fires again while the banner is still up: the same
      // overlay widget must stay mounted and no feedback cue may replay.
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.tap(find.text('Show Error'));
      await tester.pump();
      expect(find.text(message), findsOneWidget);
      expect(
          identical(tester.element(find.text(message)), firstElement), isTrue);
      expect(hapticCalls, hasLength(1));

      // The refresh restarted the 2.2s countdown at ~1.5s, so the banner must
      // still be visible after the ORIGINAL expiry has passed...
      await tester.pump(const Duration(milliseconds: 1400));
      expect(find.text(message), findsOneWidget);

      // ...and it leaves once the extended window lapses.
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(message), findsNothing);
    });

    testWidgets('a different message still replaces the visible toast',
        (tester) async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  count++;
                  PulsrToast.show(context, message: 'Failure #$count');
                },
                child: const Text('Show Next'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Failure #1'), findsOneWidget);

      await tester.tap(find.text('Show Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Failure #1'), findsNothing);
      expect(find.text('Failure #2'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2500));
    });

    testWidgets('hide() is safe to call repeatedly and clears the toast',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PulsrSnackBar.show(context, message: 'Hide me twice');
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
      expect(find.text('Hide me twice'), findsOneWidget);

      // The old hide() could call OverlayEntry.remove() on an already-detached
      // entry; it must never throw and must clear both statics.
      PulsrToast.hide();
      PulsrToast.hide();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Hide me twice'), findsNothing);
    });

    testWidgets('toast content is announced as an accessibility live region',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PulsrSnackBar.show(context, message: 'Announced message');
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

      final liveRegion = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      );
      expect(liveRegion, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2500));
    });
  });
}
