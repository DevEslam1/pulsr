// test/data/audio/usb_uac2_mute_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/hires_dac_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PulsrChannels.hiresDac);
  const bridge = HiresDacBridge();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('HiresDacBridge CS_MUTE', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('getUac2HardwareMute returns boolean state from native bridge',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getUac2HardwareMute') {
          return true;
        }
        return null;
      });

      final result = await bridge.getUac2HardwareMute();
      expect(result, isTrue);
    });

    test('getUac2HardwareMute returns false when unmuted', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getUac2HardwareMute') {
          return false;
        }
        return null;
      });

      final result = await bridge.getUac2HardwareMute();
      expect(result, isFalse);
    });

    test(
        'getUac2HardwareMute returns null when platform returns null or errors',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getUac2HardwareMute') {
          return null;
        }
        return null;
      });

      final result = await bridge.getUac2HardwareMute();
      expect(result, isNull);
    });

    test('setUac2HardwareMute passes muted flag and returns result', () async {
      bool? passedMuted;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setUac2HardwareMute') {
          passedMuted = call.arguments['muted'] as bool?;
          return true;
        }
        return false;
      });

      final success = await bridge.setUac2HardwareMute(true);
      expect(success, isTrue);
      expect(passedMuted, isTrue);

      final unmutedSuccess = await bridge.setUac2HardwareMute(false);
      expect(unmutedSuccess, isTrue);
      expect(passedMuted, isFalse);
    });

    test('non-Android platform fails closed without invoking channel',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final getResult = await bridge.getUac2HardwareMute();
      expect(getResult, isNull);

      final setResult = await bridge.setUac2HardwareMute(true);
      expect(setResult, isFalse);
    });
  });
}
