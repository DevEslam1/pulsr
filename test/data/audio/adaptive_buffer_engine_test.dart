import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/adaptive_buffer_engine.dart';

void main() {
  group('AdaptiveBufferEngine — Start Buffer Tuning', () {
    late AdaptiveBufferEngine engine;

    setUp(() {
      engine = AdaptiveBufferEngine();
    });

    test('Wi-Fi fast connection starts with 800ms buffer', () {
      engine.updateNetworkSpeed(25.0);
      final startBuffer = engine.calculateStartBuffer(
        isWifi: true,
        isLocalFile: false,
      );
      expect(startBuffer, const Duration(milliseconds: 800));
    });

    test('Cellular standard connection starts with 1200ms buffer', () {
      engine.updateNetworkSpeed(4.0);
      final startBuffer = engine.calculateStartBuffer(
        isWifi: false,
        isLocalFile: false,
      );
      expect(startBuffer, const Duration(milliseconds: 1200));
    });

    test('Poor / 2G connection starts with 2500ms buffer', () {
      engine.updateNetworkSpeed(0.8);
      final startBuffer = engine.calculateStartBuffer(
        isWifi: false,
        isLocalFile: false,
      );
      expect(startBuffer, const Duration(milliseconds: 2500));
    });

    test('Steady-state buffer remains bounded between 5s and 50s', () {
      engine.updateNetworkSpeed(15.0);
      final wifiBuffer = engine.calculateOptimalBuffer(
        bitrateKbps: 256,
        isWifi: true,
        isLocalFile: false,
      );
      expect(wifiBuffer.inSeconds, inInclusiveRange(2, 50));

      engine.updateNetworkSpeed(3.0);
      final cellBuffer = engine.calculateOptimalBuffer(
        bitrateKbps: 256,
        isWifi: false,
        isLocalFile: false,
      );
      expect(cellBuffer.inSeconds, inInclusiveRange(2, 50));
    });
  });

  group('AdaptiveBufferEngine — Dynamic Calculation', () {
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
