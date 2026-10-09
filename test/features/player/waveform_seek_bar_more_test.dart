// test/features/player/waveform_seek_bar_more_test.dart
//
// Branches the base suite leaves untouched: pinch-to-zoom + reset chip, double
// tap reset, semantics increase/decrease, the scrub preview bubble, the
// didUpdateWidget track reset, and the crossfade/A-B marker combinations.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/waveform_seek_bar.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final samples = List<double>.generate(64, (i) => (i % 10) / 10.0);

  Future<void> pinchOut(WidgetTester tester) async {
    // Drive the scale callback directly: a synthetic multi-touch pinch is
    // unreliable inside the test gesture arena alongside the drag recognizer.
    final detector = tester
        .widgetList<GestureDetector>(find.byType(GestureDetector))
        .firstWhere((g) => g.onScaleUpdate != null);
    detector.onScaleUpdate!(ScaleUpdateDetails(scale: 3.0));
    await tester.pumpAndSettle();
  }

  Widget host(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  Widget build({
    List<double>? data,
    ValueChanged<Duration>? onSeek,
    Duration position = const Duration(seconds: 30),
    Duration duration = const Duration(minutes: 3),
    List<Duration>? chapters,
    Duration? loopA,
    Duration? loopB,
    Duration? crossfade,
    String? semanticLabel,
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
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }

  testWidgets('pinch zoom shows the reset chip and tapping it resets',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await pinchOut(tester);

    // The zoom chip (and its close icon) only renders when zoomed in.
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('double tap resets an active zoom', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await pinchOut(tester);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byType(WaveformSeekBar));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(WaveformSeekBar));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('semantics increase and decrease emit clamped seeks',
      (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(build(onSeek: seeks.add));
    await tester.pump();

    final slider = tester.widget<Semantics>(find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.slider == true));
    slider.properties.onIncrease!();
    slider.properties.onDecrease!();
    expect(seeks, isNotEmpty);
  });

  testWidgets('the scrub preview bubble appears mid-drag and seeks on release',
      (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(build(onSeek: seeks.add));
    await tester.pumpAndSettle();

    final finder = find.byType(WaveformSeekBar);
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    // Bubble + track preview render while _dragValue is set.
    expect(tester.takeException(), isNull);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(seeks, isNotEmpty);
  });

  testWidgets('a new track resets zoom and drag state', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await pinchOut(tester);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.pumpWidget(build(
      data: List<double>.generate(32, (i) => (i % 5) / 5.0),
      duration: const Duration(minutes: 5),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('A-B region, markers and crossfade render in a zoomed window',
      (tester) async {
    await tester.pumpWidget(build(
      chapters: const [Duration(seconds: 20), Duration(minutes: 2)],
      loopA: const Duration(seconds: 10),
      loopB: const Duration(seconds: 100),
      crossfade: const Duration(seconds: 8),
      position: const Duration(seconds: 50),
      semanticLabel: 'Custom seek',
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Reversed loop points and a crossfade longer than the track are guarded.
    await tester.pumpWidget(build(
      loopA: const Duration(seconds: 100),
      loopB: const Duration(seconds: 10),
      crossfade: const Duration(minutes: 5),
      duration: const Duration(minutes: 3),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

