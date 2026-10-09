// test/data/audio/adaptive_buffer_engine_coverage_test.dart
//
// Branch coverage for AdaptiveBufferEngine: the BufferBucket profile getters,
// the forced-bucket override lifecycle, environment evaluation, throughput
// sampling with EWMA/variance, the underrun quality step-down and disposal.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/adaptive_buffer_engine.dart';

void main() {
  group('BufferBucket profiles', () {
    test('each bucket exposes min/max/rebuffer durations', () {
      expect(BufferBucket.minimal.minBufferDuration,
          const Duration(seconds: 10));
      expect(BufferBucket.standard.minBufferDuration,
          const Duration(seconds: 30));
      expect(BufferBucket.generous.minBufferDuration,
          const Duration(seconds: 50));

      expect(BufferBucket.minimal.maxBufferDuration,
          const Duration(seconds: 20));
      expect(BufferBucket.standard.maxBufferDuration,
          const Duration(seconds: 60));
      expect(BufferBucket.generous.maxBufferDuration,
          const Duration(seconds: 90));

      expect(BufferBucket.minimal.bufferForPlaybackAfterRebufferDuration,
          const Duration(milliseconds: 500));
      expect(BufferBucket.standard.bufferForPlaybackAfterRebufferDuration,
          const Duration(milliseconds: 800));
      expect(BufferBucket.generous.bufferForPlaybackAfterRebufferDuration,
          const Duration(milliseconds: 1500));

      for (final bucket in BufferBucket.values) {
        expect(bucket.bufferForPlaybackDuration,
            const Duration(milliseconds: 250));
      }
    });
  });

  group('forced bucket override', () {
    test('forceBucket emits once and overrides bucketFor', () async {
      final engine = AdaptiveBufferEngine();
      final events = <BufferBucket>[];
      final sub = engine.onBucketChanged.listen(events.add);

      engine.forceBucket(BufferBucket.generous);
      expect(engine.currentBucket, BufferBucket.generous);
      expect(engine.bucketFor(isWifi: true, isLocal: false),
          BufferBucket.generous);

      // Re-forcing the same value does not emit again.
      engine.forceBucket(BufferBucket.generous);
      await Future<void>.delayed(Duration.zero);
      expect(events, [BufferBucket.generous]);

      engine.releaseForce();
      expect(engine.currentBucket, BufferBucket.standard);
      await Future<void>.delayed(Duration.zero);
      expect(events, [BufferBucket.generous, BufferBucket.standard]);

      // Releasing when nothing is forced is a no-op.
      engine.releaseForce();
      await Future<void>.delayed(Duration.zero);
      expect(events, [BufferBucket.generous, BufferBucket.standard]);

      await sub.cancel();
      engine.dispose();
    });

    test('evaluateBucket suppresses emission while a force is held', () async {
      final engine = AdaptiveBufferEngine();
      final events = <BufferBucket>[];
      final sub = engine.onBucketChanged.listen(events.add);

      engine.forceBucket(BufferBucket.minimal);
      // A local environment bucket would be minimal anyway.
      engine.evaluateBucket(isWifi: false, isLocal: true);
      await Future<void>.delayed(Duration.zero);
      expect(events, [BufferBucket.minimal]);

      // The internal bucket tracks the real environment so releaseForce emits
      // the environment value, not the stale forced value.
      engine.evaluateBucket(isWifi: false, isLocal: false); // -> standard
      engine.releaseForce();
      await Future<void>.delayed(Duration.zero);
      expect(events, [BufferBucket.minimal, BufferBucket.standard]);

      await sub.cancel();
      engine.dispose();
    });
  });

  group('environment bucketing', () {
    test('local storage is minimal, slow links are generous', () {
      final engine = AdaptiveBufferEngine();
      expect(engine.bucketFor(isWifi: false, isLocal: true),
          BufferBucket.minimal);

      engine.updateNetworkSpeed(1.0); // < 2.0
      expect(engine.bucketFor(isWifi: false, isLocal: false),
          BufferBucket.generous);

      engine.reset();
      engine.updateNetworkSpeed(10.0);
      expect(
          engine.bucketFor(isWifi: true, isLocal: false), BufferBucket.standard);
      engine.dispose();
    });

    test('evaluateBucket emits only when the bucket actually changes', () async {
      final engine = AdaptiveBufferEngine();
      final events = <BufferBucket>[];
      final sub = engine.onBucketChanged.listen(events.add);

      engine.updateNetworkSpeed(1.0); // slow -> generous
      engine.evaluateBucket(isWifi: true, isLocal: false); // -> generous
      engine.reset();
      engine.updateNetworkSpeed(15.0); // fast + stable -> standard
      engine.evaluateBucket(isWifi: true, isLocal: false); // -> standard
      engine.evaluateBucket(isWifi: true, isLocal: false); // no change
      await Future<void>.delayed(Duration.zero);
      expect(events, [BufferBucket.generous, BufferBucket.standard]);

      await sub.cancel();
      engine.dispose();
    });
  });

  group('throughput sampling', () {
    test('sampleThroughput ignores short/zero samples and updates otherwise',
        () {
      final engine = AdaptiveBufferEngine();
      final before = engine.averageNetworkSpeedMbps;
      engine.sampleThroughput(1000, const Duration(milliseconds: 100));
      expect(engine.averageNetworkSpeedMbps, before,
          reason: 'under 200ms is ignored');
      engine.sampleThroughput(0, const Duration(seconds: 1));
      expect(engine.averageNetworkSpeedMbps, before, reason: 'zero bytes');

      // 1,000,000 bytes in 1s == 8 Mbps.
      engine.sampleThroughput(1000000, const Duration(seconds: 1));
      expect(engine.averageNetworkSpeedMbps, closeTo(8.0, 0.01));
      engine.dispose();
    });

    test('updateNetworkSpeed ignores non-finite or non-positive samples', () {
      final engine = AdaptiveBufferEngine();
      engine.updateNetworkSpeed(double.nan);
      engine.updateNetworkSpeed(double.infinity);
      engine.updateNetworkSpeed(0.0);
      engine.updateNetworkSpeed(-3.0);
      expect(engine.averageNetworkSpeedMbps, 10.0);
      engine.dispose();
    });
  });

  group('buffer calculations', () {
    test('calculateStartBuffer covers every branch', () {
      final engine = AdaptiveBufferEngine();
      expect(
        engine.calculateStartBuffer(isWifi: true, isLocalFile: true),
        const Duration(milliseconds: 100),
      );

      engine.updateNetworkSpeed(20.0);
      expect(
        engine.calculateStartBuffer(isWifi: true, isLocalFile: false),
        const Duration(milliseconds: 800),
      );

      engine.reset();
      engine.updateNetworkSpeed(4.0);
      expect(
        engine.calculateStartBuffer(isWifi: false, isLocalFile: false),
        const Duration(milliseconds: 1200),
      );

      engine.reset();
      engine.updateNetworkSpeed(1.0);
      expect(
        engine.calculateStartBuffer(isWifi: false, isLocalFile: false),
        const Duration(milliseconds: 2500),
      );
      engine.dispose();
    });

    test('calculateOptimalBuffer handles local, zero bitrate and zero speed',
        () {
      final engine = AdaptiveBufferEngine();
      expect(
        engine.calculateOptimalBuffer(
            bitrateKbps: 128, isWifi: true, isLocalFile: true),
        Duration.zero,
      );

      // bitrateKbps <= 0 and speed <= 0 exercise the fallback constants.
      final buffer = engine.calculateOptimalBuffer(
        bitrateKbps: 0,
        isWifi: true,
        isLocalFile: false,
        trackDuration: const Duration(seconds: 30),
      );
      expect(buffer.inSeconds,
          greaterThanOrEqualTo(AdaptiveBufferEngine.minBufferMs ~/ 1000));
      engine.dispose();
    });

    test('jitter raises the safety multiplier', () {
      final engine = AdaptiveBufferEngine();
      for (var i = 0; i < 6; i++) {
        engine.updateNetworkSpeed(1.0);
        engine.updateNetworkSpeed(12.0);
      }
      expect(engine.varianceMbps, greaterThan(0));
      final buffer = engine.calculateOptimalBuffer(
        bitrateKbps: 320,
        isWifi: false,
        isLocalFile: false,
        trackDuration: const Duration(minutes: 5),
      );
      expect(buffer.inSeconds, lessThanOrEqualTo(50));
      engine.dispose();
    });
  });

  group('underrun quality step-down', () {
    test('two underruns within 30s step high -> medium -> low', () async {
      final engine = AdaptiveBufferEngine();
      final steps = <String>[];
      final sub = engine.onStepDownQualityRequested.listen(steps.add);

      engine.recordBufferUnderrun(currentQuality: 'high');
      expect(steps, isEmpty);
      engine.recordBufferUnderrun(currentQuality: 'high');
      await Future<void>.delayed(Duration.zero);
      expect(steps, ['medium']);

      engine.recordBufferUnderrun(currentQuality: 'medium');
      engine.recordBufferUnderrun(currentQuality: 'medium');
      await Future<void>.delayed(Duration.zero);
      expect(steps, ['medium', 'low']);

      // 'low' is terminal: two more underruns must not emit.
      engine.recordBufferUnderrun(currentQuality: 'low');
      engine.recordBufferUnderrun(currentQuality: 'low');
      await Future<void>.delayed(Duration.zero);
      expect(steps, ['medium', 'low']);

      // An unrecognised quality has no step-down target.
      engine.recordBufferUnderrun(currentQuality: 'lossless');
      engine.recordBufferUnderrun(currentQuality: 'lossless');
      await Future<void>.delayed(Duration.zero);
      expect(steps, ['medium', 'low']);

      await sub.cancel();
      engine.dispose();
    });
  });

  group('lifecycle', () {
    test('reset restores the defaults', () {
      final engine = AdaptiveBufferEngine();
      engine.updateNetworkSpeed(2.0);
      engine.updateNetworkSpeed(18.0);
      engine.recordBufferUnderrun();
      engine.reset();
      expect(engine.averageNetworkSpeedMbps, 10.0);
      expect(engine.varianceMbps, 0.0);
      engine.dispose();
    });

    test('dispose closes both streams', () async {
      final engine = AdaptiveBufferEngine();
      engine.dispose();
      // A closed broadcast stream signals done to a fresh listener.
      await expectLater(engine.onBucketChanged, emitsDone);
      await expectLater(engine.onStepDownQualityRequested, emitsDone);
      // Forcing/evaluating after dispose is a no-op, not a crash.
      engine.forceBucket(BufferBucket.minimal);
      engine.evaluateBucket(isWifi: false, isLocal: true);
    });
  });
}
