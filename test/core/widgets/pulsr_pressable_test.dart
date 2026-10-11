// test/core/widgets/pulsr_pressable_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/pulsr_pressable.dart';

double _scaleOf(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find
        .descendant(
          of: find.byType(PulsrPressable),
          matching: find.byType(Transform),
        )
        .first,
  );
  // X-axis entry: getMaxScaleOnAxis() includes the untouched Z axis (1.0).
  return transform.transform.entry(0, 0);
}

Widget _host({VoidCallback? onTap, VoidCallback? onLongPress}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: PulsrPressable(
            onTap: onTap,
            onLongPress: onLongPress,
            child: const SizedBox(width: 120, height: 120),
          ),
        ),
      ),
    );

void main() {
  testWidgets('releases the pressed scale on tap-up when only onLongPress set',
      (tester) async {
    var longPressed = false;
    await tester.pumpWidget(_host(onLongPress: () => longPressed = true));

    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(PulsrPressable)));
    // kPressTimeout (100ms) fires onTapDown and schedules the scale-in; the
    // ticker only advances on the next frame.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 60));
    expect(_scaleOf(tester), lessThan(1.0));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(_scaleOf(tester), closeTo(1.0, 0.001));
    expect(longPressed, isFalse);
  });

  testWidgets('releases the pressed scale after a long press completes',
      (tester) async {
    var longPressed = false;
    await tester.pumpWidget(_host(onLongPress: () => longPressed = true));

    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(PulsrPressable)));
    await tester.pump(const Duration(milliseconds: 700));
    expect(longPressed, isTrue);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(_scaleOf(tester), closeTo(1.0, 0.001));
  });

  testWidgets('tap still fires and releases when onTap is set', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(onTap: () => tapped = true));

    await tester.tap(find.byType(PulsrPressable));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
    expect(_scaleOf(tester), closeTo(1.0, 0.001));
  });
}
