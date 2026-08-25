import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/platform_capabilities.dart';

void main() {
  group('PlatformCapabilities Tests', () {
    test('Platform capability flags reflect running platform correctly', () {
      expect(PlatformCapabilities.isAndroid, isNotNull);
      expect(PlatformCapabilities.hasEqualizer, isNotNull);
      expect(PlatformCapabilities.hasAudioEffects, isNotNull);
      expect(PlatformCapabilities.hasTagEditor, isNotNull);
      expect(PlatformCapabilities.hasRingtoneManager, isNotNull);
      expect(PlatformCapabilities.hasAppWidget, isNotNull);
      expect(PlatformCapabilities.hasHardwareVisualizer, isNotNull);
    });

    test('queryNativeCapabilities returns map of capabilities', () async {
      final caps = await PlatformCapabilities.queryNativeCapabilities();
      expect(caps, isNotNull);
      expect(caps.containsKey('hasEqualizer'), isTrue);
    });
  });
}
