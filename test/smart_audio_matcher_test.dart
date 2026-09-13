// test/smart_audio_matcher_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/services/headphone_device_matcher.dart';

const _sonyWh = HeadphoneProfile(
  id: 'sony_wh1000xm5',
  name: 'Sony WH-1000XM5',
  brand: 'Sony',
  model: 'WH-1000XM5',
  category: 'Over-Ear',
  gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
);

const _sonyWf = HeadphoneProfile(
  id: 'sony_wf1000xm5',
  name: 'Sony WF-1000XM5',
  brand: 'Sony',
  model: 'WF-1000XM5',
  category: 'TWS Earbuds',
  gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
);

const _airpods = HeadphoneProfile(
  id: 'apple_airpods_pro_2',
  name: 'AirPods Pro (2nd Gen)',
  brand: 'Apple',
  model: 'AirPods Pro 2',
  category: 'TWS Earbuds',
  gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
);

const _profiles = [_sonyWh, _sonyWf, _airpods];

void main() {
  group('HeadphoneDeviceMatcher', () {
    test('matches an exact product name to its own profile', () {
      final match = HeadphoneDeviceMatcher.match(
        deviceName: 'WH-1000XM5',
        profiles: _profiles,
      );
      expect(match, isNotNull);
      expect(match!.profile.id, 'sony_wh1000xm5');
      expect(match.score, greaterThan(0.9));
      expect(match.reason, 'exact-model');
    });

    test('is resilient to prefixes and transport suffixes', () {
      for (final name in [
        'LE_WH-1000XM5',
        'Sony WH-1000XM5 (Bluetooth)',
        'WH-1000XM5 Hands-Free',
      ]) {
        final match = HeadphoneDeviceMatcher.match(
          deviceName: name,
          profiles: _profiles,
        );
        expect(match?.profile.id, 'sony_wh1000xm5', reason: 'for "$name"');
      }
    });

    test('matches AirPods Pro with a brand-qualified name', () {
      final match = HeadphoneDeviceMatcher.match(
        deviceName: 'Apple AirPods Pro 2',
        profiles: _profiles,
      );
      expect(match?.profile.id, 'apple_airpods_pro_2');
    });

    test('rejects an ambiguous "Sony XM5" rather than guessing', () {
      // Equally close to WH-1000XM5 and WF-1000XM5 -> must not guess.
      final match = HeadphoneDeviceMatcher.match(
        deviceName: 'Sony XM5',
        profiles: _profiles,
      );
      expect(match, isNull);
    });

    test('returns null for an unknown device', () {
      final match = HeadphoneDeviceMatcher.match(
        deviceName: 'Generic USB Audio Device',
        profiles: _profiles,
      );
      expect(match, isNull);
    });

    test('handles an empty profile list and empty device name', () {
      expect(
        HeadphoneDeviceMatcher.match(deviceName: 'WH-1000XM5', profiles: const []),
        isNull,
      );
      expect(
        HeadphoneDeviceMatcher.match(deviceName: '', profiles: _profiles),
        isNull,
      );
    });
  });
}
