// test/data/audio/dac_voicing_service_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/dac_voicing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PulsrChannels.audioEffects);
  final calls = <MethodCall>[];
  late DacVoicingService service;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    // The service is a process singleton; reset it to shipped defaults so cases
    // cannot leak state into each other.
    service = DacVoicingService.instance
      ..enabled = false
      ..character = DacVoicingCharacter.sharp
      ..amount = 0
      ..loaded = false;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<String> pushedMethods() => calls.map((c) => c.method).toList();

  group('DacVoicingService', () {
    test('parameters are pushed before the enable edge', () async {
      await service.setEnabled(true);
      // The stage reads its character when it is switched on; pushing the
      // enable first would render one block with the previous filter.
      expect(pushedMethods(),
          ['setDacVoicingParams', 'setDacVoicingEnabled']);
      expect(calls.last.arguments['enabled'], isTrue);
    });

    test('character and amount use the native argument names', () async {
      await service.setCharacter(DacVoicingCharacter.minimumPhase);
      await service.setAmount(0.4);
      final params = calls
          .where((c) => c.method == 'setDacVoicingParams')
          .map((c) => c.arguments)
          .last;
      expect(params['character'], 2);
      expect(params['voicingAmount'], closeTo(0.4, 1e-9));
    });

    test('out-of-range amounts are clamped before they reach native', () async {
      await service.setAmount(7.5);
      expect(service.amount, 1.0);
      await service.setAmount(-3);
      expect(service.amount, 0.0);
      final params = calls
          .where((c) => c.method == 'setDacVoicingParams')
          .map((c) => c.arguments)
          .last;
      expect(params['voicingAmount'], 0.0);
    });

    test('the preference survives a restart', () async {
      await service.setEnabled(true);
      await service.setCharacter(DacVoicingCharacter.slow);
      await service.setAmount(0.65);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.dacVoicingEnabled), isTrue);
      expect(prefs.getInt(PrefsKeys.dacVoicingCharacter),
          DacVoicingCharacter.slow.index);
      expect(
          prefs.getDouble(PrefsKeys.dacVoicingAmount), closeTo(0.65, 1e-9));

      // Fresh startup: fields back to shipped defaults, nothing loaded yet.
      service
        ..enabled = false
        ..character = DacVoicingCharacter.sharp
        ..amount = 0
        ..loaded = false;
      calls.clear();

      await service.load();
      expect(service.loaded, isTrue);
      expect(service.enabled, isTrue);
      expect(service.character, DacVoicingCharacter.slow);
      expect(service.amount, closeTo(0.65, 1e-9));
      expect(pushedMethods(), ['setDacVoicingParams', 'setDacVoicingEnabled']);
      expect(calls.first.arguments['character'],
          DacVoicingCharacter.slow.index);
    });

    test('a corrupt stored index or amount cannot crash the restore',
        () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.dacVoicingEnabled: true,
        PrefsKeys.dacVoicingCharacter: 99,
        PrefsKeys.dacVoicingAmount: 42.0,
      });
      await service.load();
      expect(service.character.index,
          lessThanOrEqualTo(DacVoicingCharacter.values.length - 1));
      expect(service.amount, 1.0);
    });

    test('off Android nothing is pushed', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await service.setEnabled(true);
      expect(calls, isEmpty);
      // The user-visible state still tracks, so the settings UI stays honest
      // about what will be asserted once playback runs on Android.
      expect(service.enabled, isTrue);
    });
  });
}
