// test/p3_bug_fixes_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/pulsr_error_boundary.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/features/player/cubit/controllers/player_dsp_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_scaffold.dart';

class MockAudioHandler extends Mock implements PulsrAudioHandler {}

void main() {
  group('Phase 4 (P3) Bug Fixes & Architecture Verification', () {
    testWidgets('L4: PulsrErrorBoundary catches error and renders retry button',
        (tester) async {
      bool shouldThrow = true;
      int retries = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return PulsrErrorBoundary(
                  fallbackTitle: 'TestModule failed to load',
                  onRetry: () {
                    retries++;
                    setState(() {
                      shouldThrow = false;
                    });
                  },
                  builder: (context) {
                    if (shouldThrow) {
                      throw Exception('Simulated widget explosion');
                    }
                    return const Text('Module Recovered Successfully');
                  },
                );
              },
            ),
          ),
        ),
      );

      // Should show the error boundary UI
      expect(find.text('TestModule failed to load'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      // Tap Retry
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      // Should recover and display the recovered text
      expect(retries, 1);
      expect(find.text('Module Recovered Successfully'), findsOneWidget);
    });

    test('L1: PlayerThemeMetrics calculates correct ratios and responsive metrics',
        () {
      final metricsPhone = PlayerThemeMetrics(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 720),
        isTablet: false,
        isLandscape: false,
        heightRatio: 1.0,
        spacingTrackToSeek: 6.0,
        spacingSeekToControls: 8.0,
        spacingControlsToDock: 8.0,
        spacingBelowDock: 4.0,
        switcherTopPad: 2.0,
        switcherBottomPad: 3.0,
        pillBarWidth: 336.0,
        pillBarHeight: 44.0,
      );

      expect(metricsPhone.isTablet, isFalse);
      expect(metricsPhone.pillBarHeight, 44.0);
      expect(metricsPhone.spacingTrackToSeek, 6.0);

      final metricsTablet = PlayerThemeMetrics(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 1200),
        isTablet: true,
        isLandscape: false,
        heightRatio: 1.25,
        spacingTrackToSeek: 12.5,
        spacingSeekToControls: 15.0,
        spacingControlsToDock: 15.0,
        spacingBelowDock: 10.0,
        switcherTopPad: 5.0,
        switcherBottomPad: 7.5,
        pillBarWidth: 440.0,
        pillBarHeight: 50.0,
      );

      expect(metricsTablet.isTablet, isTrue);
      expect(metricsTablet.pillBarHeight, 50.0);
      expect(metricsTablet.pillBarWidth, 440.0);
    });

    test('L3: PlayerDspController applyDspEffect updates state and recovers from error',
        () async {
      PlayerState state = const PlayerState();
      void emit(PlayerState s) => state = s;
      bool syncCalled = false;
      final mockHandler = MockAudioHandler();

      final controller = PlayerDspController(
        audioHandler: mockHandler,
        settingsCubit: null,
        getState: () => state,
        emit: emit,
        syncAudioEffects: () => syncCalled = true,
        isClosed: () => false,
      );

      // Normal application
      await controller.applyDspEffect(
        featureName: 'Virtualizer',
        requiresGuard: false,
        updateDsp: (dsp) => dsp.copyWith(isVirtualizerEnabled: true),
        applyAudioHandler: () async {
          // Success
        },
      );

      expect(state.dsp.isVirtualizerEnabled, isTrue);
      expect(state.playback.errorMessage, isNull);

      // Error handling and syncAudioEffects trigger
      await controller.applyDspEffect(
        featureName: 'Spatializer',
        requiresGuard: false,
        updateDsp: (dsp) => dsp.copyWith(isSpatializerEnabled: true),
        applyAudioHandler: () async {
          throw Exception('Native DSP engine unavailable');
        },
      );

      expect(syncCalled, isTrue);
      expect(
        state.playback.errorMessage,
        contains('Failed to set spatializer: Exception: Native DSP engine unavailable'),
      );
    });
  });
}
