import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ambient_sound_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AmbientSoundService.playerFactory = () => FakeAudioPlayer();
  });

  tearDown(() {
    AmbientSoundService.playerFactory = () => FakeAudioPlayer();
  });

  group('AmbientSoundEffect', () {
    test('contains all 9 expected effects with valid metadata', () {
      const expectedEffects = [
        AmbientSoundEffect.rain,
        AmbientSoundEffect.fire,
        AmbientSoundEffect.forest,
        AmbientSoundEffect.ocean,
        AmbientSoundEffect.wind,
        AmbientSoundEffect.thunder,
        AmbientSoundEffect.birds,
        AmbientSoundEffect.cafe,
        AmbientSoundEffect.whiteNoise,
      ];

      expect(AmbientSoundEffect.values.length, 9);

      for (final e in expectedEffects) {
        expect(AmbientSoundEffect.values, contains(e));
      }

      for (final effect in AmbientSoundEffect.values) {
        expect(effect.label, isNotEmpty, reason: '${effect.name} label');
        expect(effect.emoji, isNotEmpty, reason: '${effect.name} emoji');
        expect(effect.assetPath, startsWith('assets/sounds/'),
            reason: '${effect.name} assetPath');
        expect(effect.remoteUrl, startsWith('https://'),
            reason: '${effect.name} remoteUrl');
      }
    });

    test('displayName includes emoji and label', () {
      for (final effect in AmbientSoundEffect.values) {
        expect(effect.displayName, contains(effect.emoji));
        expect(effect.displayName, contains(effect.label));
      }
    });
  });

  group('AmbientSoundService – multi-effect', () {
    test('singleton instance returns identical instance', () {
      final a = AmbientSoundService();
      final b = AmbientSoundService();
      expect(identical(a, b), isTrue);
    });

    test('starts with no active effects and isEnabled is false', () {
      final service = AmbientSoundService();
      expect(service.activeEffects, isEmpty);
      expect(service.isEnabled, isFalse);
    });

    test('toggleEffect adds effect and updates isEnabled', () async {
      final service = AmbientSoundService();
      var notified = false;
      void listener() => notified = true;
      service.addListener(listener);

      await service.toggleEffect(AmbientSoundEffect.rain);

      expect(service.isEffectActive(AmbientSoundEffect.rain), isTrue);
      expect(service.isEnabled, isTrue);
      expect(notified, isTrue);

      // Clean up
      await service.toggleEffect(AmbientSoundEffect.rain);
      service.removeListener(listener);
    });

    test('toggleEffect removes effect when already active', () async {
      final service = AmbientSoundService();

      await service.toggleEffect(AmbientSoundEffect.fire);
      expect(service.isEffectActive(AmbientSoundEffect.fire), isTrue);

      await service.toggleEffect(AmbientSoundEffect.fire);
      expect(service.isEffectActive(AmbientSoundEffect.fire), isFalse);
      expect(service.isEnabled, isFalse);
    });

    test('multiple effects can be active simultaneously', () async {
      final service = AmbientSoundService();

      await service.toggleEffect(AmbientSoundEffect.rain);
      await service.toggleEffect(AmbientSoundEffect.fire);
      await service.toggleEffect(AmbientSoundEffect.ocean);

      expect(service.activeEffects.length, 3);
      expect(service.isEffectActive(AmbientSoundEffect.rain), isTrue);
      expect(service.isEffectActive(AmbientSoundEffect.fire), isTrue);
      expect(service.isEffectActive(AmbientSoundEffect.ocean), isTrue);

      // Clean up
      for (final e in List.of(service.activeEffects)) {
        await service.toggleEffect(e);
      }
    });

    test('setEffectVolume clamps and notifies', () async {
      final service = AmbientSoundService();

      await service.setEffectVolume(AmbientSoundEffect.rain, 1.5);
      expect(service.volumeFor(AmbientSoundEffect.rain), 1.0);

      await service.setEffectVolume(AmbientSoundEffect.rain, -0.2);
      expect(service.volumeFor(AmbientSoundEffect.rain), 0.0);

      await service.setEffectVolume(AmbientSoundEffect.rain, 0.7);
      expect(service.volumeFor(AmbientSoundEffect.rain), closeTo(0.7, 0.001));
    });

    test('each effect has its own independent volume', () async {
      final service = AmbientSoundService();

      await service.setEffectVolume(AmbientSoundEffect.rain, 0.3);
      await service.setEffectVolume(AmbientSoundEffect.fire, 0.8);

      expect(service.volumeFor(AmbientSoundEffect.rain), closeTo(0.3, 0.001));
      expect(service.volumeFor(AmbientSoundEffect.fire), closeTo(0.8, 0.001));
    });

    test('onPlayerPlaybackStateChanged updates isPlayerPlaying and notifies',
        () {
      final service = AmbientSoundService();
      var notified = false;
      void listener() => notified = true;
      service.addListener(listener);

      service.onPlayerPlaybackStateChanged(true);
      expect(service.isPlayerPlaying, isTrue);
      expect(notified, isTrue);

      notified = false;
      service.onPlayerPlaybackStateChanged(false);
      expect(service.isPlayerPlaying, isFalse);
      expect(notified, isTrue);

      service.removeListener(listener);
    });

    test('onPlayerPlaybackStateChanged is idempotent for same state', () {
      final service = AmbientSoundService();
      var count = 0;
      void listener() => count++;
      service.addListener(listener);

      // Default is false, calling false again is no-op
      service.onPlayerPlaybackStateChanged(false);
      expect(count, 0);

      service.onPlayerPlaybackStateChanged(true);
      expect(count, 1);

      service.onPlayerPlaybackStateChanged(true);
      expect(count, 1); // no duplicate

      service.removeListener(listener);
    });

    test('onQuranModeDisabled is a no-op and does not change state', () async {
      final service = AmbientSoundService();
      final before = service.isEnabled;
      await service.onQuranModeDisabled();
      expect(service.isEnabled, before);
    });

    test('setEnabled(false) disables all active effects and stops players',
        () async {
      final service = AmbientSoundService();
      await service.toggleEffect(AmbientSoundEffect.ocean);
      await service.toggleEffect(AmbientSoundEffect.fire);
      expect(service.isEnabled, isTrue);
      expect(service.activeEffects.length, 2);

      await service.setEnabled(false);

      expect(service.isEnabled, isFalse);
      expect(service.activeEffects, isEmpty);
    });

    test('setEnabled(true) restores previously active effects or defaults to rain',
        () async {
      final service = AmbientSoundService();
      // First enable ocean
      await service.toggleEffect(AmbientSoundEffect.ocean);
      expect(service.isEffectActive(AmbientSoundEffect.ocean), isTrue);

      // Disable via setEnabled
      await service.setEnabled(false);
      expect(service.isEnabled, isFalse);

      // Re-enable via setEnabled - should restore ocean
      await service.setEnabled(true);
      expect(service.isEnabled, isTrue);
      expect(service.isEffectActive(AmbientSoundEffect.ocean), isTrue);

      // Clean up
      await service.setEnabled(false);
    });
  });
}
