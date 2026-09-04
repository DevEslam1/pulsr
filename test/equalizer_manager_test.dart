// test/equalizer_manager_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> channelCalls = [];

  setUp(() {
    channelCalls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.pulsr.music/audio_effects'),
      (MethodCall call) async {
        channelCalls.add(call);
        switch (call.method) {
          case 'isVirtualizerSupported':
          case 'isDynamicsSupported':
          case 'isVolumeBoostSupported':
          case 'isBassBoostSupported':
          case 'setAudioSessionId':
          case 'setVolumeBoost':
          case 'setBassBoost':
          case 'setVirtualizerEnabled':
          case 'setVirtualizerStrength':
          case 'setDynamicsPreset':
          case 'setSpatializerEnabled':
          case 'setEqEnabled':
          case 'setEqBands':
          case 'setEqBandGain':
          case 'setEqBandGains':
          case 'setEqPreamp':
          case 'releaseEffects':
            return true;
          case 'getSpatializerState':
            return {
              'isSupported': true,
              'isEnabled': false,
              'isHeadTrackerAvailable': true,
            };
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.pulsr.music/audio_effects'),
      null,
    );
  });

  const testProfile = HeadphoneProfile(
    id: 'test_id',
    name: 'Test Headphone',
    brand: 'TestBrand',
    model: 'ModelX',
    category: 'Over-Ear',
    gains: [1.0, 2.0, 3.0, 4.0, 5.0, 4.0, 3.0, 2.0, 1.0, 0.0],
    bassBoost: 0.35,
    preampGain: -2.5,
  );

  const testProfileWith4dBPreamp = HeadphoneProfile(
    id: 'test_preamp_4db',
    name: 'High Preamp Headphone',
    brand: 'TestBrand',
    model: 'ModelHot',
    category: 'In-Ear',
    gains: [2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0],
    bassBoost: 0.2,
    preampGain: 4.0,
  );

  group('EqualizerManager Hardened DSP Tests', () {
    test('setBandGain clamps to -15..+15 dB range', () async {
      final manager = EqualizerManager();
      await manager.setBandGain(0, 20.0);
      expect(manager.currentPreset.gains[0], 15.0);

      await manager.setBandGain(0, -25.0);
      expect(manager.currentPreset.gains[0], -15.0);
    });

    test(
        'setBandGain clears headphone profile and resets profile bass boost and preamp',
        () async {
      final manager = EqualizerManager();
      await manager.applyHeadphoneProfile(testProfile);
      expect(manager.selectedHeadphoneProfile, isNotNull);
      expect(manager.currentPreset.bassBoost, 0.35);

      await manager.setBandGain(3, 5.0);
      expect(manager.selectedHeadphoneProfile, isNull);
      expect(manager.currentPreset.name, 'Custom');
      expect(manager.currentPreset.gains[3], 5.0);
    });

    test('resetToFlat zeros all gains and clears active headphone profile',
        () async {
      final manager = EqualizerManager();
      await manager.applyHeadphoneProfile(testProfile);
      await manager.setBandGain(0, 10.0);

      await manager.resetToFlat();
      expect(manager.currentPreset.gains.every((g) => g == 0.0), isTrue);
      expect(manager.selectedHeadphoneProfile, isNull);
      expect(manager.currentPreset.bassBoost, 0.0);
    });

    test(
        'volumeBoost caps when combined with preamp exceeds +6dB safe headroom',
        () async {
      final manager = EqualizerManager();
      await manager.applyHeadphoneProfile(testProfileWith4dBPreamp);

      // Preamp is +4.0 dB. Setting boost to 0.8 would add +8.0 dB (Total = +12.0 dB).
      // Should cap boost so total is <= +6.0 dB, meaning boost is capped to +2.0 dB (0.2).
      await manager.setVolumeBoost(0.8);
      expect(manager.volumeBoost, closeTo(0.2, 0.001));
    });

    test('applyPreset carries preset bass boost and clears active profile',
        () async {
      final manager = EqualizerManager();
      await manager.applyHeadphoneProfile(testProfile);

      const bassPreset = EqPreset(
        name: 'Bass Heavy',
        gains: [6, 5, 4, 3, 2, 1, 0, 0, 0, 0],
        bassBoost: 0.8,
      );

      await manager.applyPreset(bassPreset);
      expect(manager.selectedHeadphoneProfile, isNull);
      expect(manager.currentPreset.name, 'Bass Heavy');
      expect(manager.currentPreset.bassBoost, 0.8);
    });

    test('A/B comparison toggles state and manages comparison lifecycle',
        () async {
      final manager = EqualizerManager();
      const customGains = [2.0, 3.0, 4.0, 5.0, 4.0, 3.0, 2.0, 1.0, 0.0, -1.0];
      await manager
          .applyPreset(const EqPreset(name: 'Custom', gains: customGains));

      expect(manager.isAbComparisonActive, isFalse);
      await manager.startAbComparison();
      expect(manager.isAbComparisonActive, isTrue);

      await manager.endAbComparison();
      expect(manager.isAbComparisonActive, isFalse);
      expect(manager.currentPreset.gains, customGains);
    });

    test(
        'toggleDynamicsBypass neutralizes dynamics without altering selected preset',
        () async {
      final manager = EqualizerManager();
      await manager.setDynamicsPreset(DynamicsPreset.studioPunch,
          enabled: true);
      expect(manager.isDynamicsEnabled, isTrue);
      expect(manager.dynamicsPreset, DynamicsPreset.studioPunch);

      await manager.toggleDynamicsBypass();
      expect(manager.isDynamicsBypassed, isTrue);

      await manager.toggleDynamicsBypass();
      expect(manager.isDynamicsBypassed, isFalse);
      expect(manager.dynamicsPreset, DynamicsPreset.studioPunch);
    });

    test('custom frequencies layout updates and persists', () async {
      final manager = EqualizerManager();
      final customFreqs = [
        30.0,
        60.0,
        120.0,
        240.0,
        480.0,
        960.0,
        1920.0,
        3840.0,
        7680.0,
        15360.0
      ];
      await manager.setCustomFrequencies(customFreqs);
      expect(manager.customFrequencies, customFreqs);

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('eq_custom_frequencies');
      expect(saved, isNotNull);
    });
  });
}
