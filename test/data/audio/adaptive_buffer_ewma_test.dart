import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/adaptive_buffer_engine.dart';

void main() {
  group('AdaptiveBufferEngine — EWMA & Variance Buffering', () {
    late AdaptiveBufferEngine engine;

    setUp(() {
      engine = AdaptiveBufferEngine();
    });

    test('EWMA smoothly tracks network speed updates', () {
      // Baseline starts at 10.0 Mbps
      expect(engine.averageNetworkSpeedMbps, equals(10.0));

      // First sample seeds EWMA directly to avoid initialization bias
      engine.updateNetworkSpeed(5.0);
      expect(engine.averageNetworkSpeedMbps, equals(5.0));

      // Subsequent sample uses EWMA with alpha = 0.3:
      // delta = 10.0 - 5.0 = 5.0; ewma = 5.0 + 0.3 * 5.0 = 6.5
      engine.updateNetworkSpeed(10.0);
      expect(engine.averageNetworkSpeedMbps, closeTo(6.5, 0.01));
    });

    test('High variance / jittery connection escalates bucket to generous', () {
      // Simulating a swinging link (alternating 1 Mbps and 12 Mbps)
      for (int i = 0; i < 6; i++) {
        engine.updateNetworkSpeed(1.0);
        engine.updateNetworkSpeed(12.0);
      }

      expect(engine.varianceMbps, greaterThan(0.0));
      // Even on Wi-Fi, swinging throughput should select generous bucket
      final bucket = engine.bucketFor(isWifi: true, isLocal: false);
      expect(bucket, equals(BufferBucket.generous));
    });

    test('Stable fast link maintains standard bucket on Wi-Fi', () {
      for (int i = 0; i < 5; i++) {
        engine.updateNetworkSpeed(15.0);
      }

      final bucket = engine.bucketFor(isWifi: true, isLocal: false);
      expect(bucket, equals(BufferBucket.standard));
    });

    test('Optimal buffer uses real track duration and obeys 50s ceiling', () {
      // Long track at high bitrate on slow link: without cap would exceed 50s
      final buf = engine.calculateOptimalBuffer(
        bitrateKbps: 1411,
        isWifi: false,
        isLocalFile: false,
        trackDuration: const Duration(minutes: 10),
      );
      expect(buf.inSeconds, lessThanOrEqualTo(50));
      expect(buf.inSeconds, greaterThanOrEqualTo(AdaptiveBufferEngine.minBufferMs ~/ 1000));

      // Short track (30s) produces smaller buffer than default 240s
      final shortBuf = engine.calculateOptimalBuffer(
        bitrateKbps: 320,
        isWifi: true,
        isLocalFile: false,
        trackDuration: const Duration(seconds: 30),
      );
      final defaultBuf = engine.calculateOptimalBuffer(
        bitrateKbps: 320,
        isWifi: true,
        isLocalFile: false,
      );
      expect(shortBuf.inSeconds, lessThanOrEqualTo(defaultBuf.inSeconds));
    });

    test('reset clears EWMA and variance back to baseline', () {
      engine.updateNetworkSpeed(2.0);
      engine.updateNetworkSpeed(18.0);
      expect(engine.varianceMbps, greaterThan(0.0));

      engine.reset();
      expect(engine.averageNetworkSpeedMbps, equals(10.0));
      expect(engine.varianceMbps, equals(0.0));
    });

    test('Engine respects trackDuration parameter', () {
      engine.updateNetworkSpeed(5.0);

      final shortBuf = engine.calculateOptimalBuffer(
        bitrateKbps: 320,
        isWifi: true,
        isLocalFile: false,
        trackDuration: const Duration(seconds: 45),
      );

      final longBuf = engine.calculateOptimalBuffer(
        bitrateKbps: 320,
        isWifi: true,
        isLocalFile: false,
        trackDuration: const Duration(minutes: 8),
      );

      expect(shortBuf.inSeconds, lessThanOrEqualTo(longBuf.inSeconds));
    });
  });
}
