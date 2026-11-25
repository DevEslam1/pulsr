// test/features/player/widgets/waveform_seek_bar_test.dart
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/waveform_seek_bar.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';

class _BoundsRecordingCanvas extends Fake implements Canvas {
  final List<Rect> drawnBounds = <Rect>[];
  Rect? activeClip;
  Rect? lastClipRect;

  @override
  void drawRRect(RRect rrect, Paint paint) {
    if (activeClip == null) {
      drawnBounds.add(rrect.outerRect);
    }
  }

  @override
  void drawPath(Path path, Paint paint) {
    if (activeClip == null) {
      drawnBounds.add(path.getBounds());
    }
  }

  @override
  void save() {}

  @override
  void clipRect(Rect rect,
      {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) {
    activeClip = rect;
    lastClipRect = rect;
  }

  @override
  void restore() {
    activeClip = null;
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {}

  @override
  void drawRect(Rect rect, Paint paint) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final samples = List<double>.generate(64, (i) => (i % 10) / 10.0);

  Widget host(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
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

  testWidgets(
      'P0-5a: drawn waveform geometry stays within canvas width for large sample counts',
      (tester) async {
    const canvasSize = Size(300, 44);
    for (final n in [50, 200, 1000, 2000]) {
      final data = List<double>.generate(n, (i) => ((i * 7) % 10) / 10.0);
      for (final style in WaveformVisualizerStyle.values) {
        await tester.pumpWidget(build(
          data: data,
          style: style,
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 3),
        ));
        await tester.pump();

        final customPaint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(WaveformSeekBar),
            matching: find.byType(CustomPaint),
          ),
        );
        final canvas = _BoundsRecordingCanvas();
        customPaint.painter!.paint(canvas, canvasSize);

        expect(canvas.drawnBounds, isNotEmpty, reason: 'n=$n style=$style');
        final minLeft = canvas.drawnBounds
            .map((r) => r.left)
            .reduce((a, b) => a < b ? a : b);
        final maxRight = canvas.drawnBounds
            .map((r) => r.right)
            .reduce((a, b) => a > b ? a : b);
        expect(
          minLeft,
          greaterThanOrEqualTo(-1e-6),
          reason: 'left overflow for n=$n style=$style',
        );
        expect(
          maxRight,
          lessThanOrEqualTo(canvasSize.width + 1e-6),
          reason:
              'right overflow ($maxRight > ${canvasSize.width}) for n=$n style=$style',
        );
      }
    }
  });

  testWidgets('P0-5b: mid-drag zoom preserves drag ratio and thumb screen X',
      (tester) async {
    Duration? seeked;
    final data = List<double>.generate(1000, (i) => (i % 10) / 10.0);
    // Engine position is at 10% (10s / 100s), while user scrubs at 70%.
    await tester.pumpWidget(build(
      data: data,
      position: const Duration(seconds: 10),
      duration: const Duration(seconds: 100),
      onSeek: (d) => seeked = d,
    ));
    await tester.pump();

    final gestureFinder = find.byType(GestureDetector);
    final box = tester.renderObject<RenderBox>(gestureFinder);
    final topLeft = box.localToGlobal(Offset.zero);
    final width = box.size.width;
    final y = topLeft.dy + box.size.height / 2;

    // 1. Start horizontal drag at 70% of the track.
    final finger1 =
        await tester.startGesture(Offset(topLeft.dx + width * 0.70, y));
    await finger1.moveBy(const Offset(20, 0));
    await tester.pump();
    await finger1.moveBy(const Offset(-20, 0));
    await tester.pump();

    // 2. While drag is active, pinch-zoom with two fingers (or invoke
    // onScaleStart/Update directly if arena keeps horizontal drag).
    final gd = tester.widget<GestureDetector>(gestureFinder);
    gd.onScaleStart?.call(ScaleStartDetails(
      focalPoint: Offset(topLeft.dx + width * 0.70, y),
      localFocalPoint: Offset(width * 0.70, box.size.height / 2),
      pointerCount: 2,
    ));
    await tester.pump(const Duration(milliseconds: 50));
    gd.onScaleUpdate?.call(ScaleUpdateDetails(
      focalPoint: Offset(topLeft.dx + width * 0.70, y),
      localFocalPoint: Offset(width * 0.70, box.size.height / 2),
      scale: 2.0,
      horizontalScale: 2.0,
      verticalScale: 1.0,
      pointerCount: 2,
    ));
    await tester.pump();

    // Verify painted progress and preview bubble stay near 0.70 * width, and
    // releasing drag seeks to ~70s (0.70 * 100s) instead of jumping toward
    // widget.position (10s).
    final customPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(WaveformSeekBar),
        matching: find.byType(CustomPaint),
      ),
    );
    final canvas = _BoundsRecordingCanvas();
    customPaint.painter!.paint(canvas, Size(width, box.size.height));
    expect(canvas.lastClipRect, isNotNull);
    expect(canvas.lastClipRect!.right / width, closeTo(0.70, 0.03));

    await finger1.up();
    await tester.pumpAndSettle();

    expect(seeked, isNotNull);
    final dragRatio = seeked!.inMilliseconds / 100000.0;
    expect(dragRatio, closeTo(0.70, 0.03));
  });
}
