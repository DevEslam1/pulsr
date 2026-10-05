// Accessibility regression: the platform "Reduce motion" flag (and the in-app
// toggle that overrides MediaQuery.disableAnimations) must collapse every
// PulsrMotion duration to zero while leaving normal motion untouched.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';

void main() {
  testWidgets('collapses durations when disableAnimations is set',
      (tester) async {
    var enabled = true;
    var resolved = const Duration(milliseconds: 400);
    Curve curve = Curves.easeOutCubic;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            enabled = context.motionEnabled;
            resolved = context.motion(const Duration(milliseconds: 400));
            curve = context.motionCurve(Curves.easeOutCubic);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(enabled, isFalse);
    expect(resolved, Duration.zero);
    expect(curve, Curves.linear);
  });

  testWidgets('keeps durations when motion is allowed', (tester) async {
    var enabled = false;
    var resolved = Duration.zero;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Builder(
          builder: (context) {
            enabled = context.motionEnabled;
            resolved = context.motion(const Duration(milliseconds: 400));
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(enabled, isTrue);
    expect(resolved, const Duration(milliseconds: 400));
  });
}
