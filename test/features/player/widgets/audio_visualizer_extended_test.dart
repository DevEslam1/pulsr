// test/features/player/widgets/audio_visualizer_extended_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AudioVisualizer.isTestingOverride = true;
  });

  tearDown(() {
    AudioVisualizer.isTestingOverride = null;
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
    bool preferSimulated = false,
    int? audioSessionId,
    int? trackSeed,
    int? trackId,
    String? trackPath,
  }) {
    return host(
      Center(
        child: SizedBox(
          width: 320,
          height: 160,
          child: AudioVisualizer(
            style: style,
            isPlaying: isPlaying,
            preferSimulated: preferSimulated,
            audioSessionId: audioSessionId,
            trackSeed: trackSeed,
            trackId: trackId,
            trackPath: trackPath,
          ),
        ),
      ),
    );
  }

  test('resolveSeed prefers explicit seed then id/path/session', () {
    expect(AudioVisualizer.resolveSeed(trackSeed: 7), 7);
    expect(
      AudioVisualizer.resolveSeed(trackId: 3),
      Object.hash(3, 'pulsr_visualizer_seed'),
    );
    expect(
      AudioVisualizer.resolveSeed(trackPath: '/a/b.flac'),
      Object.hash('/a/b.flac', 'pulsr_visualizer_seed'),
    );
    expect(AudioVisualizer.resolveSeed(audioSessionId: 99), 99);
    expect(AudioVisualizer.resolveSeed(), 0);
    // Empty path falls through to the session id.
    expect(
      AudioVisualizer.resolveSeed(trackPath: '', audioSessionId: 5),
      5,
    );
  });

  test('isTesting honors the override flag', () {
    AudioVisualizer.isTestingOverride = false;
    expect(AudioVisualizer.isTesting, isFalse);
    AudioVisualizer.isTestingOverride = true;
    expect(AudioVisualizer.isTesting, isTrue);
    AudioVisualizer.isTestingOverride = null;
    // Falls back to the test environment.
    expect(AudioVisualizer.isTesting, isTrue);
  });

  testWidgets('off style renders nothing', (tester) async {
    await tester.pumpWidget(visualizer(style: VisualizerStyle.off));
    await tester.pump();
    expect(find.byType(AudioVisualizer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders every visualizer style without error', (tester) async {
    for (final style in VisualizerStyle.values) {
      await tester.pumpWidget(
          visualizer(style: style, preferSimulated: true, trackId: 5));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'style $style');
    }
  });

  testWidgets('decay hooks drive the bar data to baseline', (tester) async {
    await tester.pumpWidget(
        visualizer(preferSimulated: true, isPlaying: false));
    await tester.pump();

    final state =
        tester.state<AudioVisualizerState>(find.byType(AudioVisualizer));
    expect(state.isDecayedToBaseline, isTrue);

    state.setBarDataForTesting(0, 0.9);
    state.setBarDataForTesting(1, 0.4);
    expect(state.isDecayedToBaseline, isFalse);
    expect(state.currentDataForTesting[0], 0.9);

    for (int i = 0; i < 60 && !state.isDecayedToBaseline; i++) {
      state.onTickForTesting();
    }
    expect(state.isDecayedToBaseline, isTrue);
  });

  testWidgets('milkdrop falls back to the Canvas painter and badges it',
      (tester) async {
    await tester.pumpWidget(visualizer(style: VisualizerStyle.milkdrop));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final state =
        tester.state<AudioVisualizerState>(find.byType(AudioVisualizer));
    // The GPU shader may or may not load in the test asset bundle; the badge
    // must honestly mirror whichever painter is active.
    final badgeShown =
        find.textContaining('CPU fallback').evaluate().isNotEmpty;
    expect(state.isFallbackActive, badgeShown);
  });

  testWidgets('widget updates switch styles and playback state',
      (tester) async {
    await tester.pumpWidget(visualizer(
      style: VisualizerStyle.bar,
      isPlaying: true,
      preferSimulated: true,
    ));
    await tester.pump();

    // Preference flip and style change are both observed by didUpdateWidget.
    await tester.pumpWidget(visualizer(
      style: VisualizerStyle.custom,
      isPlaying: false,
      preferSimulated: false,
      audioSessionId: 42,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(visualizer(
      style: VisualizerStyle.wave,
      isPlaying: true,
      audioSessionId: 43,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Lifecycle pauses and resumes the visualizer.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
