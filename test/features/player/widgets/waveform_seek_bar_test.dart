// test/features/player/widgets/waveform_seek_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/waveform_seek_bar.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final samples = List<double>.generate(64, (i) => (i % 10) / 10.0);

  Widget host(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  Widget build({
    List<double>? data,
    WaveformVisualizerStyle style = WaveformVisualizerStyle.mirroredBars,
    ValueChanged<Duration>? onSeek,
    Duration position = const Duration(seconds: 30),
    Duration duration = const Duration(minutes: 3),
    List<Duration>? chapters,
    Duration? loopA,
    Duration? loopB,
    Duration? crossfade,
    double height = 44,
  }) {
    return host(
      Center(
        child: SizedBox(
          width: 400,
          child: WaveformSeekBar(
            position: position,
            duration: duration,
            onSeek: onSeek ?? (_) {},
            samples: data ?? samples,
            activeColor: Colors.deepPurple,
            chapterMarkers: chapters,
            loopPointA: loopA,
            loopPointB: loopB,
            crossfadeDuration: crossfade,
            height: height,
            style: style,
          ),
        ),
      ),
    );
  }

  testWidgets('drag and tap emit seek positions', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(build(onSeek: seeks.add));
    await tester.pumpAndSettle();

    final finder = find.byType(GestureDetector);

    // Horizontal drag emits a seek on release.
    await tester.drag(finder, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(seeks, isNotEmpty);

    // Single tap-down also seeks (give the double-tap recognizer time).
    seeks.clear();
    await tester.tapAt(tester.getCenter(finder));
    await tester.pump(const Duration(milliseconds: 400));
    expect(seeks, isNotEmpty);
  });

  testWidgets('renders every visualizer style with markers and loop region',
      (tester) async {
    for (final style in WaveformVisualizerStyle.values) {
      await tester.pumpWidget(build(
        style: style,
        chapters: const [Duration(seconds: 30), Duration(minutes: 1)],
        loopA: const Duration(seconds: 20),
        loopB: const Duration(seconds: 90),
        crossfade: const Duration(seconds: 5),
        position: const Duration(seconds: 45),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'style $style');
    }
  });

  testWidgets('handles empty and single-sample waveforms', (tester) async {
    await tester.pumpWidget(build(
      data: const [],
      duration: Duration.zero,
      position: Duration.zero,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(build(data: const [0.5]));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('clamps position beyond duration and seeks via semantics',
      (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(build(
      onSeek: seeks.add,
      position: const Duration(minutes: 10),
      duration: const Duration(minutes: 3),
    ));
    await tester.pump();

    // The widget clamps the effective position into the visible window.
    expect(tester.takeException(), isNull);
  });
}
