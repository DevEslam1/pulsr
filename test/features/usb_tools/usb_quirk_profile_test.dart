// test/features/usb_tools/usb_quirk_profile_test.dart
//
// Pure-Dart tests for the quirk profile value type: JSON round-trip, strict
// validation, the lowercase `vid:pid` key, migration of profiles written by the
// removed write-only knobs, and the diagnostics one-liner.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/usb_tools/usb_quirk_profile.dart';

void main() {
  group('UsbQuirkProfile json', () {
    test('round-trips every field', () {
      final profile = UsbQuirkProfile(
        vid: 0x1D6B,
        pid: 0x0104,
        label: 'Melo DAC',
        hidEnabled: true,
      );

      final decoded = UsbQuirkProfile.fromJson(profile.toJson());

      expect(decoded, profile);
      expect(decoded.hidEnabled, isTrue);
      expect(profile.toJson().keys, <String>[
        'vid',
        'pid',
        'label',
        'hidEnabled',
      ]);
    });

    test('drops knobs that were persisted by older builds', () {
      // Profiles written before the dead knobs were removed still load.
      final decoded = UsbQuirkProfile.fromJson(<String, Object?>{
        'vid': 0x0a12,
        'pid': 1,
        'label': 'Ancient DAC',
        'silenceMs': 250,
        'bufferMs': 40,
        'transferSizeBytes': 8192,
        'force16Bit': true,
        'altResetOnStop': true,
        'futureKnob': 'ignored',
      });

      expect(decoded.vid, 0x0a12);
      expect(decoded.label, 'Ancient DAC');
      expect(decoded.hidEnabled, isFalse);
      expect(decoded.toJson().containsKey('silenceMs'), isFalse);
    });

    test('ignores unknown keys and defaults absent knobs', () {
      final decoded = UsbQuirkProfile.fromJson(<String, Object?>{
        'vid': 0x0a12,
        'pid': 1,
        'label': 'Ancient DAC',
        'futureKnob': 'ignored',
      });

      expect(decoded.vid, 0x0a12);
      expect(decoded.hidEnabled, isFalse);
    });

    test('falls back to the default label when none is stored', () {
      final decoded = UsbQuirkProfile.fromJson(<String, Object?>{
        'vid': 1,
        'pid': 2,
      });
      expect(decoded.label, UsbQuirkProfile.defaults.label);
    });

    test('rejects a missing vid and a wrong-typed knob', () {
      expect(
        () => UsbQuirkProfile.fromJson(<String, Object?>{'pid': 2}),
        throwsA(
          isA<QuirkValidationError>().having((e) => e.field, 'field', 'vid'),
        ),
      );
      expect(
        () => UsbQuirkProfile.fromJson(<String, Object?>{
          'vid': 1,
          'pid': 2,
          'hidEnabled': 'yes',
        }),
        throwsA(
          isA<QuirkValidationError>()
              .having((e) => e.field, 'field', 'hidEnabled'),
        ),
      );
    });

    test('tryFromJson returns null instead of throwing', () {
      expect(UsbQuirkProfile.tryFromJson('not a map'), isNull);
      expect(UsbQuirkProfile.tryFromJson(<String, Object?>{'pid': 1}), isNull);
      expect(
        UsbQuirkProfile.tryFromJson(<String, Object?>{'vid': 1, 'pid': 2}),
        isNotNull,
      );
    });
  });

  group('UsbQuirkProfile validation', () {
    test('accepts the boundary values', () {
      final profile = UsbQuirkProfile(
        vid: UsbQuirkProfile.maxUsbId,
        pid: 0,
        label: 'x',
        hidEnabled: true,
      );
      expect(profile.vid, UsbQuirkProfile.maxUsbId);
    });

    test('rejects an empty label and a non-16-bit usb id', () {
      expect(
        () => UsbQuirkProfile(vid: 1, pid: 2, label: '   '),
        throwsA(
          isA<QuirkValidationError>()
              .having((e) => e.code, 'code', 'usb-quirk-label-empty'),
        ),
      );
      expect(
        () => UsbQuirkProfile(vid: 0x10000, pid: 2, label: 'd'),
        throwsA(
          isA<QuirkValidationError>()
              .having((e) => e.code, 'code', 'usb-quirk-vid-range'),
        ),
      );
      expect(
        () => UsbQuirkProfile(vid: 1, pid: -1, label: 'd'),
        throwsA(
          isA<QuirkValidationError>()
              .having((e) => e.code, 'code', 'usb-quirk-pid-range'),
        ),
      );
    });

    test('copyWith keeps untouched fields and re-validates', () {
      final base = UsbQuirkProfile(vid: 0x0a12, pid: 1, label: 'DAC');
      final edited = base.copyWith(hidEnabled: true);

      expect(edited.vid, 0x0a12);
      expect(edited.label, 'DAC');
      expect(edited.hidEnabled, isTrue);
      expect(base.hidEnabled, isFalse);
      expect(
        () => base.copyWith(label: ' '),
        throwsA(isA<QuirkValidationError>()),
      );
    });

    test('trims the label', () {
      expect(
        UsbQuirkProfile(vid: 1, pid: 2, label: '  DAC  ').label,
        'DAC',
      );
    });
  });

  group('UsbQuirkProfile identity', () {
    test('keys are lowercase hex padded to four digits', () {
      expect(UsbQuirkProfile.deviceKey(0x0a12, 0x1), '0a12:0001');
      expect(UsbQuirkProfile.deviceKey(0xFFFF, 0), 'ffff:0000');
      expect(
        UsbQuirkProfile(vid: 0x1D6B, pid: 0x0104, label: 'd').key,
        '1d6b:0104',
      );
    });

    test('describe is one line and collapses neutral profiles', () {
      expect(UsbQuirkProfile.defaults.describe(), contains('defaults'));
      expect(
        UsbQuirkProfile.defaults.describe().contains('\n'),
        isFalse,
      );

      final profile = UsbQuirkProfile(
        vid: 0x1d6b,
        pid: 0x0104,
        label: 'Melo DAC',
        hidEnabled: true,
      );
      final line = profile.describe();
      expect(line, startsWith('1d6b:0104 "Melo DAC": '));
      expect(line, contains('HID consumer keys'));
      expect(line.contains('\n'), isFalse);
    });

    test('equality covers every field', () {
      final a = UsbQuirkProfile(vid: 1, pid: 2, label: 'd', hidEnabled: true);
      final b = a.copyWith();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(hidEnabled: false), isFalse);
    });
  });
}
