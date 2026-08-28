import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/adaptive_buffer_engine.dart';
import 'package:pulsr/data/audio/adaptive_playback_buffer.dart';

void main() {
  group('AdaptivePlaybackBuffer - Task 7 Start Buffer Tuning', () {
    test('Wi-Fi fast connection starts with 800ms buffer', () {
      final startBuffer = AdaptivePlaybackBuffer.calculateStartBuffer(
        networkSpeedMbps: 25.0,
        isWifi: true,
      );
      expect(startBuffer, const Duration(milliseconds: 800));
    });

    test('Cellular standard connection starts with 1200ms buffer', () {
      final startBuffer = AdaptivePlaybackBuffer.calculateStartBuffer(
        networkSpeedMbps: 4.0,
        isWifi: false,
      );
      expect(startBuffer, const Duration(milliseconds: 1200));
    });

    test('Poor / 2G connection starts with 2500ms buffer', () {
      final startBuffer = AdaptivePlaybackBuffer.calculateStartBuffer(
        networkSpeedMbps: 0.8,
        isWifi: false,
      );
      expect(startBuffer, const Duration(milliseconds: 2500));
    });

    test('Steady-state buffer remains bounded between 5s and 60s', () {
      final wifiBuffer = AdaptivePlaybackBuffer.calculateBuffer(
        bitrateKbps: 256,
        networkSpeedMbps: 15.0,
        isWifi: true,
      );
      expect(wifiBuffer.inSeconds, inInclusiveRange(5, 30));

      final cellBuffer = AdaptivePlaybackBuffer.calculateBuffer(
        bitrateKbps: 256,
        networkSpeedMbps: 3.0,
        isWifi: false,
      );
      expect(cellBuffer.inSeconds, inInclusiveRange(10, 60));
    });
  });

  group('AdaptiveBufferEngine - Task 7 Dynamic Calculation', () {
    late AdaptiveBufferEngine engine;

    setUp(() {
      engine = AdaptiveBufferEngine();
    });

    test('Local file playback requires minimal 100ms start buffer', () {
      final startBuffer = engine.calculateStartBuffer(
        isWifi: true,
        isLocalFile: true,
      );
      expect(startBuffer, const Duration(milliseconds: 100));
    });

    test('High network speed yields 800ms start buffer on Wi-Fi', () {
      engine.updateNetworkSpeed(20.0);
      final startBuffer = engine.calculateStartBuffer(
        isWifi: true,
        isLocalFile: false,
      );
      expect(startBuffer, const Duration(milliseconds: 800));
    });

    test('Low network speed scales start buffer safely to 2500ms', () {
      engine.updateNetworkSpeed(0.5);
      final startBuffer = engine.calculateStartBuffer(
        isWifi: false,
        isLocalFile: false,
      );
      expect(startBuffer, const Duration(milliseconds: 2500));
    });
  });
}
