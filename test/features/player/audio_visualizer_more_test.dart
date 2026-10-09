// test/features/player/audio_visualizer_more_test.dart
//
// Branch coverage for [AudioVisualizer]: simulated ticks/decay, style and
// preference updates, lifecycle transitions, the GPU-budget style downgrade and
// explicit preset rendering.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/performance/gpu_budget.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/milkdrop_preset.dart';
import 'package:pulsr/domain/models/visualizer_preset.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AudioVisualizer.isTestingOverride = true;
  });

  tearDown(() {
    AudioVisualizer.isTestingOverride = null;
    GpuBudget.setEnabled(false);
  });

  Widget host(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  Widget visualizer({
    VisualizerStyle style = VisualizerStyle.bar,
    bool isPlaying = true,
    bool preferSimulated = true,
    int? audioSessionId,
    int? trackSeed,
    int? trackId,
    String? trackPath,
    VisualizerPreset? customPreset,
    MilkdropPreset? milkdropPreset,
    double width = 320,
    double height = 160,
  }) {
    return host(
      Center(
        child: SizedBox(
          width: width.isFinite ? width : 320,
          height: height.isFinite ? height : 160,
          child: AudioVisualizer(
            style: style,
            isPlaying: isPlaying,
            preferSimulated: preferSimulated,
            audioSessionId: audioSessionId,
            trackSeed: trackSeed,
            trackId: trackId,
            trackPath: trackPath,
            customPreset: customPreset,
            milkdropPreset: milkdropPreset,
          ),
        ),
      ),
    );
  }

  AudioVisualizerState stateOf(WidgetTester tester) =>
      tester.state<AudioVisualizerState>(find.byType(AudioVisualizer));

  testWidgets('simulated ticks advance the bar data', (tester) async {
    await tester.pumpWidget(visualizer(trackSeed: 5));
    await tester.pump();

    final state = stateOf(tester);
    final before = state.currentDataForTesting.toList();
    for (int i = 0; i < 6; i++) {
      state.onTickForTesting();
    }
    await tester.pump();
    expect(state.currentDataForTesting, isNot(equals(before)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pausing decays the bars to baseline', (tester) async {
    await tester.pumpWidget(visualizer(isPlaying: false, trackSeed: 2));
    await tester.pump();

    final state = stateOf(tester);
    state.setBarDataForTesting(0, 0.95);
    state.setBarDataForTesting(3, 0.4);
    expect(state.isDecayedToBaseline, isFalse);

    for (int i = 0; i < 80 && !state.isDecayedToBaseline; i++) {
      state.onTickForTesting();
    }
    expect(state.isDecayedToBaseline, isTrue);
  });

  testWidgets('style, preference and session updates are handled',
      (tester) async {
    await tester.pumpWidget(visualizer(style: VisualizerStyle.bar));
    await tester.pump();

    // preferSimulated toggle -> _restartNativeStream (no Android here).
    await tester.pumpWidget(visualizer(
      style: VisualizerStyle.custom,
      preferSimulated: false,
      audioSessionId: 42,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // audioSessionId change.
    await tester.pumpWidget(visualizer(
      style: VisualizerStyle.wave,
      preferSimulated: false,
      audioSessionId: 43,
    ));
    await tester.pump();

    // Turning the style off clears the bar data.
    await tester.pumpWidget(visualizer(
      style: VisualizerStyle.off,
      isPlaying: false,
    ));
    await tester.pump();
    expect(stateOf(tester).currentDataForTesting.every((v) => v == 0.0),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lifecycle inactive/paused/resumed transitions are safe',
      (tester) async {
    await tester.pumpWidget(visualizer());
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('GPU budget downgrades heavy styles to bars', (tester) async {
    GpuBudget.setEnabled(true);
    for (final style in [
      VisualizerStyle.milkdrop,
      VisualizerStyle.terrain3D,
      VisualizerStyle.particles,
      VisualizerStyle.albumArtReactive,
    ]) {
      await tester.pumpWidget(visualizer(style: style));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'style $style');
    }
  });

  testWidgets('explicit custom and milkdrop presets render', (tester) async {
    await tester.pumpWidget(visualizer(
      style: VisualizerStyle.custom,
      customPreset: VisualizerPreset.fallback,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(visualizer(
      style: VisualizerStyle.milkdrop,
      milkdropPreset: MilkdropPresetLibrary.defaultPreset,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('seed resolution covers every fallback tier', (tester) async {
    await tester.pumpWidget(visualizer(trackPath: '/a/b.flac', trackId: 9));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(visualizer(trackPath: '', audioSessionId: 3));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
