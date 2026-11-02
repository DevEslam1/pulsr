import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/services/ambient_sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AmbientSoundEffect', () {
    test('contains rain and fire with valid asset paths', () {
      expect(AmbientSoundEffect.values, contains(AmbientSoundEffect.rain));
      expect(AmbientSoundEffect.values, contains(AmbientSoundEffect.fire));

      for (final effect in AmbientSoundEffect.values) {
        expect(effect.label, isNotEmpty);
        expect(effect.emoji, isNotEmpty);
        expect(effect.assetPath, startsWith('assets/sounds/'));
        expect(effect.remoteUrl, startsWith('https://'));
      }
    });
  });

  group('AmbientSoundService', () {
    test('singleton instance returns identical instance', () {
      final a = AmbientSoundService();
      final b = AmbientSoundService();
      expect(identical(a, b), isTrue);
    });

    test('volume clamping works correctly', () async {
      final service = AmbientSoundService();

      await service.setVolume(1.5);
      expect(service.volume, 1.0);

      await service.setVolume(-0.2);
      expect(service.volume, 0.0);

      await service.setVolume(0.7);
      expect(service.volume, 0.7);
    });

    test('switching effect updates property and notifies listeners', () async {
      final service = AmbientSoundService();
      var notified = false;
      void listener() => notified = true;

      service.addListener(listener);
      await service.setEffect(AmbientSoundEffect.fire);

      expect(service.effect, AmbientSoundEffect.fire);
      expect(notified, isTrue);

      service.removeListener(listener);
    });

    test('onQuranModeDisabled turns off sound if active', () async {
      final service = AmbientSoundService();
      if (service.isEnabled) {
        await service.onQuranModeDisabled();
        expect(service.isEnabled, isFalse);
      }
    });
  });
}

