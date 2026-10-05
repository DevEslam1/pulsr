import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pulsr.music/audio_effects');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    AudioEffectsChannel().dispose();
  });

  test('rejected native enable leaves manager off and propagates failure',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    final manager = EqualizerManager();
    await expectLater(
        manager.setCrossfeed(true), throwsA(isA<PlatformException>()));
    expect(manager.isCrossfeedEnabled, isFalse);
    manager.dispose();
  });

  test('unsupported native safety reports failure', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'DSP_UNAVAILABLE');
    });
    await expectLater(
        AudioEffectsChannel().setHeadphoneSafetyParams(enabled: true),
        throwsA(isA<PlatformException>()));
  });

  test('bypass failure preserves hydrated saved dynamic EQ bands', () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.dynamicEqBands: jsonEncode([
        const DynamicEqBandConfig(frequency: 2500, q: 3).toJson(),
      ]),
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setBypassDspForBitPerfect') {
        throw PlatformException(code: 'DSP_NOT_APPLIED');
      }
      if (call.method == 'getCapabilities' ||
          call.method == 'getProcessingCapabilities' ||
          call.method == 'getSpatializerState' ||
          call.method == 'detectOemAudio') {
        return <String, Object>{};
      }
      return call.method.startsWith('set') ? true : null;
    });
    final manager = EqualizerManager();
    await manager.init();
    expect(manager.dynamicEqBands.single.frequency, 2500);
    expect(manager.dynamicEqBands.single.q, 3);
    expect(manager.isSincResamplerEnabled, isFalse);
    manager.dispose();
  });

  test('dynamic bass sends the requested state before committing it', () async {
    bool? pushedEnabled;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setDynamicBassParams') {
        pushedEnabled = call.arguments['enabled'] as bool;
      }
      return true;
    });
    final manager = EqualizerManager();
    await manager.setDynamicBass(enabled: true);
    expect(pushedEnabled, isTrue);
    expect(manager.isDynamicBassEnabled, isTrue);
    manager.dispose();
  });
}
