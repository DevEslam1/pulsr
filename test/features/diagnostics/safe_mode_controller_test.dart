// test/features/diagnostics/safe_mode_controller_test.dart
//
// State-machine contract: the third consecutive failure trips the fallback, the
// fallback switches the risky output path off, and a success or reset clears it.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/features/diagnostics/safe_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late SafeModeController controller;
  late List<SafeModeEvent> events;
  late StreamSubscription<SafeModeEvent> subscription;

  setUp(() async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrefsKeys.aaudioOutputEnabled: true,
      PrefsKeys.usbHardwareVolumeEnabled: true,
      PrefsKeys.dsdOutputMode: 'dop',
      PrefsKeys.strictBitPerfect: true,
    });
    prefs = await SharedPreferences.getInstance();
    controller = SafeModeController(
      prefs: prefs,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
    );
    events = <SafeModeEvent>[];
    subscription = controller.events.listen(events.add);
  });

  tearDown(() async {
    await subscription.cancel();
    await controller.dispose();
  });

  test('trips only on the third consecutive failure', () async {
    await controller.recordFailure('Pixel 8', 'sink underrun');
    await controller.recordFailure('Pixel 8', 'sink underrun');

    expect(controller.consecutiveFailures('Pixel 8'), 2);
    expect(controller.shouldFallback('Pixel 8'), isFalse);

    await controller.recordFailure('Pixel 8', 'sink underrun');
    await Future<void>.delayed(Duration.zero);

    expect(controller.shouldFallback('Pixel 8'), isTrue);
    expect(
      events.map((event) => event.type).toList(),
      <SafeModeEventType>[
        SafeModeEventType.failure,
        SafeModeEventType.failure,
        SafeModeEventType.thresholdReached,
      ],
    );
  });

  test('tracks each device separately and derives safe prefs keys', () async {
    for (var i = 0; i < 3; i++) {
      await controller.recordFailure('Pixel 8', 'sink underrun');
    }

    expect(controller.shouldFallback('Pixel 8'), isTrue);
    expect(controller.shouldFallback('WH-1000XM5'), isFalse);
    expect(
      SafeModeController.failuresKey('Pixel 8'),
      'safe_mode_failures_pixel_8',
    );
  });

  test('a success clears the consecutive counter', () async {
    await controller.recordFailure('Pixel 8', 'sink underrun');
    await controller.recordFailure('Pixel 8', 'sink underrun');

    await controller.recordSuccess('Pixel 8');

    expect(controller.consecutiveFailures('Pixel 8'), 0);
    expect(controller.shouldFallback('Pixel 8'), isFalse);
  });

  test('applyFallback turns off the risky output path', () async {
    for (var i = 0; i < 3; i++) {
      await controller.recordFailure('Pixel 8', 'sink underrun');
    }

    final description = await controller.applyFallback('Pixel 8');
    await Future<void>.delayed(Duration.zero);

    expect(prefs.getBool(PrefsKeys.aaudioOutputEnabled), isFalse);
    expect(prefs.getBool(PrefsKeys.usbHardwareVolumeEnabled), isFalse);
    expect(prefs.getString(PrefsKeys.dsdOutputMode), 'pcm');
    expect(prefs.getBool(PrefsKeys.strictBitPerfect), isFalse);
    expect(controller.isFallbackActive('Pixel 8'), isTrue);
    expect(description, contains('AAudio'));
    expect(description, contains('3 consecutive'));
    expect(
      events.last.type,
      SafeModeEventType.fallbackApplied,
    );
  });

  test('reset clears counters, the active flag and the reason', () async {
    for (var i = 0; i < 3; i++) {
      await controller.recordFailure('Pixel 8', 'sink underrun');
    }
    await controller.applyFallback('Pixel 8');

    await controller.reset('Pixel 8');
    await Future<void>.delayed(Duration.zero);

    expect(controller.consecutiveFailures('Pixel 8'), 0);
    expect(controller.shouldFallback('Pixel 8'), isFalse);
    expect(controller.isFallbackActive('Pixel 8'), isFalse);
    expect(controller.lastFailureReason('Pixel 8'), isNull);
    expect(
      prefs.containsKey(SafeModeController.reasonKey('Pixel 8')),
      isFalse,
    );
    expect(events.last.type, SafeModeEventType.reset);
  });

  test('keeps the last failure reason and truncates long ones', () async {
    await controller.recordFailure('Pixel 8', 'sink underrun -5');

    expect(controller.lastFailureReason('Pixel 8'), 'sink underrun -5');

    await controller.recordFailure('Pixel 8', 'x' * 400);

    expect(controller.lastFailureReason('Pixel 8')!.length, 200);
  });
}
