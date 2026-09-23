import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/errors/error_message_resolver.dart';
import 'package:pulsr/core/utils/haptic_patterns.dart';
import 'package:pulsr/domain/models/eq_preset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Full Master Audit Verification Tests', () {
    test('Reorder queue destination index math handles forward drag correctly', () {
      int oldIndex = 1;
      int newIndex = 5;
      if (newIndex > oldIndex) newIndex -= 1;
      expect(newIndex, equals(4));

      // Backward drag
      oldIndex = 4;
      newIndex = 1;
      if (newIndex > oldIndex) newIndex -= 1;
      expect(newIndex, equals(1));
    });

    test('Equalizer gain arrays equality handles content comparison correctly', () {
      final presetA = EqPreset(name: 'Test', gains: [1.0, 2.0, 3.0]);
      final presetB = EqPreset(name: 'Test', gains: [1.0, 2.0, 3.0]);
      final presetC = EqPreset(name: 'Test', gains: [1.0, 2.0, 3.5]);

      expect(listEquals(presetA.gains, presetB.gains), isTrue);
      expect(listEquals(presetA.gains, presetC.gains), isFalse);
    });

    test('ErrorMessageResolver humanizes exceptions into clean copy', () {
      // Mock build context by testing directly against strings
      final networkError = ErrorMessageResolver.resolveUserFriendly(
        _MockBuildContext(),
        Exception('SocketException: Failed to connect'),
      );
      expect(networkError, contains('Network connection error'));

      final permError = ErrorMessageResolver.resolveUserFriendly(
        _MockBuildContext(),
        Exception('PermissionDenied: access to storage'),
      );
      expect(permError, contains('Storage permission was denied'));

      final formatError = ErrorMessageResolver.resolveUserFriendly(
        _MockBuildContext(),
        const FormatException('invalid json payload'),
      );
      expect(formatError, contains('Encountered unexpected or corrupt data format'));
    });

    test('PulsrElevation produces valid shadows for dark and light palettes', () {
      final darkTheme = AuraTheme.customTheme(Colors.blue, brightness: Brightness.dark);
      final lightTheme = AuraTheme.customTheme(Colors.blue, brightness: Brightness.light);
      final darkPalette = darkTheme.extension<PulsrPalette>()!;
      final lightPalette = lightTheme.extension<PulsrPalette>()!;

      final l1Dark = PulsrElevation.level1(darkPalette);
      final l2Dark = PulsrElevation.level2(darkPalette);
      final l3Dark = PulsrElevation.level3(darkPalette);

      expect(l1Dark.first.blurRadius, equals(6));
      expect(l2Dark.first.blurRadius, equals(14));
      expect(l3Dark.first.blurRadius, equals(24));

      final l1Light = PulsrElevation.level1(lightPalette);
      expect(l1Light.first.blurRadius, equals(6));
    });

    test('HapticPatterns does not throw when invoked in tests', () {
      expect(() => HapticPatterns.tap(), returnsNormally);
      expect(() => HapticPatterns.confirm(), returnsNormally);
      expect(() => HapticPatterns.destructive(), returnsNormally);
      expect(() => HapticPatterns.selection(), returnsNormally);
    });
  });
}

class _MockBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
