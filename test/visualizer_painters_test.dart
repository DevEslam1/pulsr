import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/milkdrop_preset.dart';
import 'package:pulsr/domain/models/visualizer_preset.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final style in VisualizerStyle.values) {
    testWidgets('AudioVisualizer renders $style without throwing',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AudioVisualizer(style: style, isPlaying: false, height: 100),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 25));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('milkdrop renders with an explicit preset', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AudioVisualizer(
          style: VisualizerStyle.milkdrop,
          isPlaying: false,
          height: 100,
          milkdropPreset: MilkdropPresetLibrary.presets[1],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 25));
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom JSON renders a lissajous preset', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AudioVisualizer(
          style: VisualizerStyle.custom,
          isPlaying: false,
          height: 100,
          customPreset: const VisualizerPreset(
            name: 'Test',
            shape: VisualizerShape.lissajous,
            mirror: true,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 25));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'AudioVisualizer renders playing state without requesting microphone permission',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AudioVisualizer(
          style: VisualizerStyle.bar,
          isPlaying: true,
          audioSessionId: null, // Simulated fallback
          height: 100,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.byType(AudioVisualizer), findsOneWidget);
  });
}
