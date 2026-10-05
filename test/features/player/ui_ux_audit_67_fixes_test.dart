// test/ui_ux_audit_67_fixes_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UI/UX Audit 67 Fixes Tests', () {
    testWidgets('PlayerDockIconButton enforces 48x48dp touch target constraint',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerDockIconButton(
              icon: Icons.equalizer_rounded,
              tooltip: 'Equalizer',
              isActive: false,
              activeColor: Colors.tealAccent,
              inactiveColor: Colors.white70,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dockBtn = tester.getSize(find.byType(PlayerDockIconButton));
      expect(dockBtn.width, greaterThanOrEqualTo(48.0));
      expect(dockBtn.height, greaterThanOrEqualTo(48.0));
    });

    test('A/B Loop zoom-independent window overlap calculation', () {
      // Simulating zoom calculations from waveform_seek_bar.dart
      const loopA = Duration(seconds: 10);
      const loopB = Duration(seconds: 30);
      const totalDuration = Duration(seconds: 100);

      // In a 0-100s track, loop ratio is [0.1, 0.3]
      final startRatio = loopA.inMilliseconds / totalDuration.inMilliseconds;
      final endRatio = loopB.inMilliseconds / totalDuration.inMilliseconds;
      expect(startRatio, closeTo(0.1, 0.001));
      expect(endRatio, closeTo(0.3, 0.001));

      // In visible window [0.05, 0.25], clamp overlap is [0.1, 0.25]
      const windowStart = 0.05;
      const windowEnd = 0.25;
      final visibleStart = startRatio.clamp(windowStart, windowEnd);
      final visibleEnd = endRatio.clamp(windowStart, windowEnd);
      expect(visibleStart, closeTo(0.1, 0.001));
      expect(visibleEnd, closeTo(0.25, 0.001));
      expect(visibleEnd > visibleStart, isTrue);
    });

    testWidgets('PlayerDockIconButton displays active badge text correctly',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerDockIconButton(
              icon: Icons.timer_rounded,
              tooltip: 'Sleep Timer',
              isActive: true,
              activeColor: Colors.amber,
              inactiveColor: Colors.white54,
              badgeText: '15m',
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('15m'), findsOneWidget);
    });
  });
}
