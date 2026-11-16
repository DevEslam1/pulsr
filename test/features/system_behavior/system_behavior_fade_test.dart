// test/features/system_behavior/system_behavior_fade_test.dart
//
// Fade-out is timing-sensitive, so it is tested twice: the ramp arithmetic as a
// pure value object, and the service ramp under fake time (no real sleeps).

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/system_behavior/system_behavior_policy.dart';
import 'package:pulsr/features/system_behavior/system_behavior_service.dart';
import 'package:pulsr/features/system_behavior/system_behavior_settings.dart';

import 'system_behavior_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FadeRamp', () {
    test('walks from the start volume to exactly zero in the requested time',
        () {
      const FadeRamp ramp = FadeRamp(
        startVolume: 0.8,
        total: Duration(milliseconds: 640),
      );
      expect(ramp.steps, 16);
      expect(ramp.stepInterval, const Duration(milliseconds: 40));
      expect(ramp.elapsedAtStep, const Duration(milliseconds: 640));
      expect(ramp.elapsedAtStep <= ramp.total, isTrue);
      expect(ramp.volumeAtStep(0), 0.8);
      expect(ramp.volumeAtStep(1), closeTo(0.75, 1e-12));
      expect(ramp.volumeAtStep(8), closeTo(0.4, 1e-12));
      expect(ramp.volumeAtStep(15), closeTo(0.05, 1e-12));
      expect(ramp.volumeAtStep(16), 0.0);
      expect(ramp.volumeAtStep(99), 0.0);
    });

    test('is monotonic and never above the start volume', () {
      const FadeRamp ramp = FadeRamp(
        startVolume: 1,
        total: Duration(milliseconds: 500),
        steps: 10,
      );
      double previous = ramp.volumeAtStep(0);
      for (int i = 1; i <= ramp.steps; i += 1) {
        final double current = ramp.volumeAtStep(i);
        expect(current, lessThanOrEqualTo(previous));
        previous = current;
      }
      expect(previous, 0.0);
    });

    test('truncation never overshoots the requested duration', () {
      const FadeRamp ramp = FadeRamp(
        startVolume: 0.5,
        total: Duration(milliseconds: 15),
      );
      expect(ramp.stepInterval, lessThan(const Duration(milliseconds: 1)));
      expect(ramp.elapsedAtStep <= ramp.total, isTrue);
      expect(ramp.volumeAtStep(ramp.steps), 0.0);
    });

    test('a zero-length or silent ramp is not audible', () {
      expect(
        const FadeRamp(startVolume: 0.5, total: Duration.zero).isAudible,
        isFalse,
      );
      expect(
        const FadeRamp(startVolume: 0, total: Duration(milliseconds: 300))
            .isAudible,
        isFalse,
      );
      expect(
        const FadeRamp(startVolume: 0.5, total: Duration(milliseconds: 300))
            .isAudible,
        isTrue,
      );
    });

    test('garbage start volumes ramp from silence instead of NaN', () {
      const FadeRamp ramp = FadeRamp(
        startVolume: double.nan,
        total: Duration(milliseconds: 320),
      );
      expect(ramp.isAudible, isFalse);
      expect(ramp.volumeAtStep(0).isNaN, isFalse);
      expect(ramp.volumeAtStep(1).isNaN, isFalse);
      expect(ramp.volumeAtStep(4), 0.0);
    });
  });

  group('service fade-out', () {
    test('ramps to zero in the configured time, then pauses', () async {
      final SystemBehaviorSettings settings =
          await loadSettings(fadeOutOnPauseMs: 640);
      final RecordingPlaybackPort port = RecordingPlaybackPort(volume: 0.8);
      final SystemBehaviorService service =
          buildService(settings: settings, port: port);

      fakeAsync((FakeAsync async) {
        service.handleNotificationSound();
        async.flushMicrotasks();

        async.elapse(const Duration(milliseconds: 639));
        expect(port.pauseCount, 0, reason: 'the fade is not finished yet');

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();

        expect(port.pauseCount, 1);
        expect(port.volumes.length, 16);
        expect(port.volumes.first, closeTo(0.75, 1e-12));
        expect(port.volumes.last, 0.0);
        expect(port.calls.last, 'pause');
        expect(port.calls[port.calls.length - 2], 'volume:0.0');
        expect(service.isFading, isFalse);
      });

      service.dispose();
    });

    test('resuming restores the exact pre-fade volume and stops the ramp',
        () async {
      final SystemBehaviorSettings settings =
          await loadSettings(fadeOutOnPauseMs: 640);
      final RecordingPlaybackPort port = RecordingPlaybackPort(volume: 0.73);
      final SystemBehaviorService service =
          buildService(settings: settings, port: port);

      fakeAsync((FakeAsync async) {
        service.handleNotificationSound();
        async.elapse(const Duration(milliseconds: 200));
        expect(service.isFading, isTrue);

        service.handleAppResumed();
        async.flushMicrotasks();
        expect(port.volumes.last, 0.73);
        expect(service.isFading, isFalse);

        final int callsAfterRestore = port.volumes.length;
        async.elapse(const Duration(seconds: 2));
        expect(port.volumes.length, callsAfterRestore);
        expect(port.pauseCount, 0);
      });

      service.dispose();
    });

    test('a disabled fade pauses immediately', () async {
      final SystemBehaviorSettings settings =
          await loadSettings(fadeOutOnPauseMs: 0);
      final RecordingPlaybackPort port = RecordingPlaybackPort(volume: 0.9);
      final SystemBehaviorService service =
          buildService(settings: settings, port: port);

      await service.handleNotificationSound();

      expect(port.pauseCount, 1);
      expect(port.volumes, isEmpty);
      service.dispose();
    });

    test('an unreadable volume degrades to a plain pause', () async {
      final SystemBehaviorSettings settings =
          await loadSettings(fadeOutOnPauseMs: 640);
      final RecordingPlaybackPort port = RecordingPlaybackPort();
      final SystemBehaviorService service = SystemBehaviorService(
        settings: settings,
        port: port,
        isPlaying: () => true,
      );

      await service.handleNotificationSound();

      expect(port.pauseCount, 1);
      expect(port.volumes, isEmpty);
      service.dispose();
    });
  });
}
