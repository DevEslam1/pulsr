import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildWidget({required bool isPlaying}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AudioVisualizer(
          isPlaying: isPlaying,
          style: VisualizerStyle.bar,
          width: 300,
          height: 100,
        ),
      ),
    );
  }

  testWidgets(
      'H-09: audio visualizer tick loop decays to baseline and short-circuits on pause',
      (tester) async {
    await tester.pumpWidget(buildWidget(isPlaying: false));
    await tester.pumpAndSettle();

    final state =
        tester.state<AudioVisualizerState>(find.byType(AudioVisualizer));

    // Initially at baseline
    expect(state.isDecayedToBaseline, isTrue);

    // Calling onTick while already at baseline should short-circuit immediately
    state.onTickForTesting();
    expect(state.isDecayedToBaseline, isTrue);
    for (final val in state.currentDataForTesting) {
      expect(val, equals(0.0));
    }

    // Simulate active bars during playback before pause
    state.setBarDataForTesting(0, 0.8);
    state.setBarDataForTesting(1, 0.5);
    expect(state.isDecayedToBaseline, isFalse);

    // Call onTick while paused: it should decay towards baseline
    for (int i = 0; i < 40; i++) {
      state.onTickForTesting();
      if (state.isDecayedToBaseline) break;
    }

    // It must reach baseline
    expect(state.isDecayedToBaseline, isTrue);
    expect(state.currentDataForTesting[0], equals(0.0));
    expect(state.currentDataForTesting[1], equals(0.0));

    // Subsequent tick should short-circuit
    state.onTickForTesting();
    expect(state.isDecayedToBaseline, isTrue);
  });
}
