// test/smart_audio_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/smart_audio_service.dart';
import 'package:pulsr/domain/services/smart_audio_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SmartAudioService', () {
    test('defaults to Auto mode', () async {
      final service = SmartAudioService();
      expect(await service.getMode(), SmartAudioMode.auto);
      expect(await service.isEnabled(), isTrue);
    });

    test('persists Manual mode across instances', () async {
      await SmartAudioService().setMode(SmartAudioMode.manual);
      final reloaded = SmartAudioService();
      expect(await reloaded.getMode(), SmartAudioMode.manual);
      expect(await reloaded.isEnabled(), isFalse);
    });

    test('remembers and forgets per-device AutoEQ links', () async {
      final service = SmartAudioService();
      await service.rememberAutoEqLink(
        deviceKey: 'bluetooth:wh 1000xm5',
        deviceLabel: 'WH-1000XM5',
        profileId: 'sony_wh1000xm5',
        score: 1.0,
      );

      final link = await service.linkForDeviceKey('bluetooth:wh 1000xm5');
      expect(link, isNotNull);
      expect(link!.profileId, 'sony_wh1000xm5');
      expect(link.score, 1.0);
    });

    test('unknown mode name falls back to Auto', () {
      expect(SmartAudioMode.fromName('nonsense'), SmartAudioMode.auto);
      expect(SmartAudioMode.fromName(null), SmartAudioMode.auto);
      expect(SmartAudioMode.fromName('manual'), SmartAudioMode.manual);
    });
  });
}
