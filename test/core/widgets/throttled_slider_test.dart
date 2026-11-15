import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/throttled_slider.dart';

void main() {
  testWidgets(
      'keeps _previewValue across unrelated rebuilds until widget.value catches up or onChangeEnd',
      (tester) async {
    double? reportedChange;
    double? reportedEnd;
    double sliderValue = 0.0;
    int unrelatedTick = 0;
    late StateSetter rebuildParent;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuildParent = setState;
              return Column(
                children: [
                  Text('tick:$unrelatedTick'),
                  SizedBox(
                    width: 300,
                    child: ThrottledSlider(
                      value: sliderValue,
                      onChanged: (v) => reportedChange = v,
                      onChangeEnd: (v) => reportedEnd = v,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(Slider));
    final start = Offset(center.dx - 120, center.dy);
    final gesture = await tester.startGesture(start);
    await tester.pump();
    // Drag right without lifting the pointer (no onChangeEnd yet).
    await gesture.moveBy(const Offset(180, 0));
    await tester.pump();

    // Let the 60ms debounce fire so _debounceTimer becomes null.
    await tester.pump(const Duration(milliseconds: 80));
    final previewAfterDebounce =
        tester.widget<Slider>(find.byType(Slider)).value;
    expect(previewAfterDebounce, greaterThan(0.5));
    expect(reportedChange, closeTo(previewAfterDebounce, 1e-6));

    // Trigger an unrelated parent rebuild while widget.value is still 0.0.
    rebuildParent(() {
      unrelatedTick++;
    });
    await tester.pump();

    // Preview value must NOT snap back to 0.0.
    expect(
      tester.widget<Slider>(find.byType(Slider)).value,
      closeTo(previewAfterDebounce, 1e-6),
    );

    // Once widget.value catches up to _previewValue, _previewValue clears and
    // subsequent external updates are reflected normally.
    rebuildParent(() {
      sliderValue = previewAfterDebounce;
    });
    await tester.pump();
    rebuildParent(() {
      sliderValue = 0.25;
    });
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, closeTo(0.25, 1e-6));

    await gesture.up();
    await tester.pump();
    expect(reportedEnd, isNotNull);
  });
}
