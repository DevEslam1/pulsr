// test/core/utils/pulsr_haptics_unified_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/utils/pulsr_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> platformCalls = [];

  setUp(() {
    platformCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method.startsWith('HapticFeedback.')) {
        platformCalls.add(call);
      }
      return null;
    });
    PulsrHaptics.setEnabled(true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    PulsrHaptics.setEnabled(true);
  });

  group('PulsrHaptics Master Switch', () {
    test('when enabled, haptic calls reach platform channel', () async {
      PulsrHaptics.setEnabled(true);
      expect(PulsrHaptics.enabled.value, isTrue);

      await PulsrHaptics.selectionClick();
      await PulsrHaptics.lightImpact();
      await PulsrHaptics.mediumImpact();
      await PulsrHaptics.heavyImpact();
      await PulsrHaptics.vibrate();

      expect(platformCalls, isNotEmpty);
      expect(
        platformCalls.map((c) => c.method).toList(),
        containsAll([
          'HapticFeedback.vibrate',
        ]),
      );
    });

    test('when disabled, ZERO haptic feedback invocations reach platform', () async {
      PulsrHaptics.setEnabled(false);
      expect(PulsrHaptics.enabled.value, isFalse);

      platformCalls.clear();

      await PulsrHaptics.tap();
      await PulsrHaptics.light();
      await PulsrHaptics.confirm();
      await PulsrHaptics.destructive();
      await PulsrHaptics.selection();
      await PulsrHaptics.selectionClick();
      await PulsrHaptics.lightImpact();
      await PulsrHaptics.mediumImpact();
      await PulsrHaptics.heavyImpact();
      await PulsrHaptics.vibrate();
      await PulsrHaptics.success();
      await PulsrHaptics.error();

      expect(platformCalls, isEmpty,
          reason: 'Toggle OFF must produce zero haptics app-wide');
    });

    test('PrefsKeys.hapticsEnabled key exists and matches expected constant', () {
      expect(PrefsKeys.hapticsEnabled, 'setting_haptics_enabled');
    });
  });
}
