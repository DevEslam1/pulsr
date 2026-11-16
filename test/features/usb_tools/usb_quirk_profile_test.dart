// test/features/usb_tools/usb_quirk_profile_test.dart
//
// Pure-Dart tests for the quirk profile value type: JSON round-trip, strict
// validation, the lowercase `vid:pid` key and the diagnostics one-liner.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/usb_tools/usb_quirk_profile.dart';

void main() {
  group('UsbQuirkProfile json', () {
    test('round-trips every field', () {
      final profile = UsbQuirkProfile(
        vid: 0x1D6B,
        pid: 0x0104,
        label: 'Melo DAC',
        silenceMs: 250,
        altResetOnStop: true,
        force16Bit: true,
        hidEnabled: true,
        transferSizeBytes: 8192,
        bufferMs: 40,
      );

      final decoded = UsbQuirkProfile.fromJson(profile.toJson());

      expect(decoded, profile);
      expect(decoded.silenceMs, 250);
      expect(decoded.transferSizeBytes, 8192);
      expect(decoded.bufferMs, 40);
      expect(decoded.hidEnabled, isTrue);
    });

    test('ignores unknown keys and defaults absent knobs', () {
      final decoded = UsbQuirkProfile.fromJson(<String, Object?>{
        'vid': 0x0a12,
        'pid': 1,
        'label': 'Ancient DAC',
        'futureKnob': 'ignored',
      });

      expect(decoded.vid, 0x0a12);
      expect(decoded.silenceMs, 0);
      expect(decoded.altResetOnStop, isFalse);
      expect(decoded.force16Bit, isFalse);
      expect(decoded.hidEnabled, isFalse);
      expect(decoded.transferSizeBytes, 0);
      expect(decoded.bufferMs, 0);
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
          'silenceMs': '250',
        }),
        throwsA(
          isA<QuirkValidationError>()
              .having((e) => e.field, 'field', 'silenceMs'),
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
        silenceMs: UsbQuirkProfile.maxSilenceMs,
        bufferMs: UsbQuirkProfile.maxBufferMs,
        transferSizeBytes: UsbQuirkProfile.maxTransferSizeBytes,
      );
      expect(profile.silenceMs, UsbQuirkProfile.maxSilenceMs);
    });

    test('rejects out-of-range knobs with the offending field', () {
      final cases = <String, Matcher>{
        'silenceMs': isA<QuirkValidationError>().having(
          (e) => e.field,
          'field',
          'silenceMs',
        ),
        'bufferMs': isA<QuirkValidationError>().having(
          (e) => e.field,
          'field',
          'bufferMs',
        ),
        'transferSizeBytes': isA<QuirkValidationError>().having(
          (e) => e.field,
          'field',
          'transferSizeBytes',
        ),
      };

      expect(
        () => UsbQuirkProfile(vid: 1, pid: 2, label: 'd', silenceMs: 2501),
        throwsA(cases['silenceMs']),
      );
      expect(
        () => UsbQuirkProfile(vid: 1, pid: 2, label: 'd', bufferMs: 501),
        throwsA(cases['bufferMs']),
      );
      // 256 B is inside the USB packet range but below the accepted minimum.
      expect(
        () => UsbQuirkProfile(
          vid: 1,
          pid: 2,
          label: 'd',
          transferSizeBytes: 256,
        ),
        throwsA(cases['transferSizeBytes']),
      );
      expect(
        () => UsbQuirkProfile(
          vid: 1,
          pid: 2,
          label: 'd',
          transferSizeBytes: 131072,
        ),
        throwsA(cases['transferSizeBytes']),
      );
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
      final edited = base.copyWith(silenceMs: 100, force16Bit: true);

      expect(edited.vid, 0x0a12);
      expect(edited.label, 'DAC');
      expect(edited.silenceMs, 100);
      expect(edited.force16Bit, isTrue);
      expect(base.silenceMs, 0);
      expect(() => base.copyWith(silenceMs: 3000), throwsA(isA<QuirkValidationError>()));
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
        silenceMs: 250,
        bufferMs: 40,
        force16Bit: true,
        altResetOnStop: true,
        hidEnabled: true,
      );
      final line = profile.describe();
      expect(line, startsWith('1d6b:0104 "Melo DAC": '));
      expect(line, contains('silence 250ms'));
      expect(line, contains('buffer 40ms'));
      expect(line, contains('transfer auto'));
      expect(line, contains('force 16-bit'));
      expect(line, contains('alt-reset on stop'));
      expect(line, contains('HID consumer keys'));
      expect(line.contains('\n'), isFalse);
    });

    test('equality covers every field', () {
      final a = UsbQuirkProfile(vid: 1, pid: 2, label: 'd', bufferMs: 10);
      final b = a.copyWith();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(bufferMs: 20), isFalse);
    });
  });
}
