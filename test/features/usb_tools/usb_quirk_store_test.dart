// test/features/usb_tools/usb_quirk_store_test.dart
//
// Store tests: round-trip, per-device precedence over the global defaults,
// lowercase hex keying (including a hand-edited uppercase key) and tolerance of
// a corrupt document.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/usb_tools/usb_quirk_profile.dart';
import 'package:pulsr/features/usb_tools/usb_quirk_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<UsbQuirkStore> _newStore([
  Map<String, Object> initial = const <String, Object>{},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return UsbQuirkStore(prefs: prefs);
}

Future<SharedPreferences> _newPrefs([
  Map<String, Object> initial = const <String, Object>{},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final profile = UsbQuirkProfile(
    vid: 0x1d6b,
    pid: 0x0104,
    label: 'Melo DAC',
    hidEnabled: true,
  );

  group('UsbQuirkStore round-trip', () {
    test('put then all/get returns the stored profile', () async {
      final store = await _newStore();

      expect(await store.put(profile), isTrue);
      expect(store.all(), <UsbQuirkProfile>[profile]);
      expect(store.get(profile.vid, profile.pid), profile);
      expect(store.get(0x0001, 0x0002), isNull);
    });

    test('persists under the versioned key with lowercase hex keys', () async {
      final prefs = await _newPrefs();
      final store = UsbQuirkStore(prefs: prefs);

      await store.put(profile);

      final raw = prefs.getString(UsbQuirkStore.storageKey);
      expect(raw, isNotNull);
      expect(raw, contains('"1d6b:0104"'));
      expect(raw, isNot(contains('1D6B')));
      final decoded = jsonDecode(raw!) as Map<String, Object?>;
      final devices =
          decoded[UsbQuirkStore.devicesField] as Map<String, Object?>;
      expect(devices.keys, <String>['1d6b:0104']);
      expect(
        (devices['1d6b:0104'] as Map<String, Object?>)['label'],
        'Melo DAC',
      );
    });

    test('a hand-edited uppercase key still resolves', () async {
      final payload = <String, Object?>{
        UsbQuirkStore.devicesField: <String, Object?>{
          '1D6B:0104': profile.toJson(),
        },
      };
      final store = await _newStore(<String, Object>{
        UsbQuirkStore.storageKey: jsonEncode(payload),
      });

      expect(store.get(0x1d6b, 0x0104), profile);
      expect(store.all().single.key, '1d6b:0104');
    });

    test('orders profiles by label', () async {
      final store = await _newStore();
      await store.put(UsbQuirkProfile(vid: 1, pid: 1, label: 'Zeta'));
      await store.put(UsbQuirkProfile(vid: 1, pid: 2, label: 'alpha'));

      expect(store.all().map((p) => p.label), <String>['alpha', 'Zeta']);
    });
  });

  group('UsbQuirkStore defaults', () {
    test('per-device entry wins over global defaults', () async {
      final store = await _newStore();
      final globals = UsbQuirkProfile(
        vid: 0,
        pid: 0,
        label: 'Slow DACs',
        hidEnabled: true,
      );

      expect(await store.setGlobalDefaults(globals), isTrue);
      await store.put(profile);

      expect(store.globalDefaults, globals);
      expect(store.profileForDevice(profile.vid, profile.pid), profile);
      expect(store.profileForDevice(0x9999, 0x8888), globals);
      expect(store.profileForDevice(null, null), globals);
    });

    test('unknown device with no defaults resolves to null', () async {
      final store = await _newStore();
      expect(store.profileForDevice(0x9999, 0x8888), isNull);
      expect(store.profileForDevice(null, null), isNull);
      expect(store.globalDefaults, isNull);
    });

    test('clearing the defaults removes them', () async {
      final store = await _newStore();
      await store.setGlobalDefaults(
        UsbQuirkProfile(vid: 0, pid: 0, label: 'Fallback', hidEnabled: false),
      );
      expect(store.globalDefaults, isNotNull);

      expect(await store.setGlobalDefaults(null), isTrue);
      expect(store.globalDefaults, isNull);
    });
  });

  group('UsbQuirkStore removal', () {
    test('remove drops the entry and falls back to the defaults', () async {
      final store = await _newStore();
      final globals = UsbQuirkProfile(vid: 0, pid: 0, label: 'Fallback');
      await store.setGlobalDefaults(globals);
      await store.put(profile);

      expect(await store.remove(profile.vid, profile.pid), isTrue);

      expect(store.get(profile.vid, profile.pid), isNull);
      expect(store.all(), isEmpty);
      expect(store.profileForDevice(profile.vid, profile.pid), globals);
    });

    test('removing an absent entry reports success', () async {
      final store = await _newStore();
      expect(await store.remove(1, 2), isTrue);
    });
  });

  group('UsbQuirkStore corruption tolerance', () {
    test('a non-JSON document reads as empty and can be replaced', () async {
      final prefs = await _newPrefs(<String, Object>{
        UsbQuirkStore.storageKey: 'this is not json',
      });
      final store = UsbQuirkStore(prefs: prefs);

      expect(store.all(), isEmpty);
      expect(store.profileForDevice(1, 2), isNull);

      expect(await store.put(profile), isTrue);
      expect(store.get(profile.vid, profile.pid), profile);
    });

    test('a non-object document and a non-object devices field are skipped',
        () async {
      final listStore = await _newStore(<String, Object>{
        UsbQuirkStore.storageKey: '[1,2,3]',
      });
      expect(listStore.all(), isEmpty);

      final devicesStore = await _newStore(<String, Object>{
        UsbQuirkStore.storageKey: jsonEncode(<String, Object?>{
          UsbQuirkStore.devicesField: 'nope',
        }),
      });
      expect(devicesStore.all(), isEmpty);
    });

    test('one unreadable entry does not hide the readable ones', () async {
      final store = await _newStore(<String, Object>{
        UsbQuirkStore.storageKey: jsonEncode(<String, Object?>{
          UsbQuirkStore.devicesField: <String, Object?>{
            '0a12:0001': profile.toJson(),
            '0a12:0002': <String, Object?>{'vid': 0x0a12},
            '0a12:0003': 'garbage',
          },
        }),
      });

      final all = store.all();
      expect(all, hasLength(1));
      expect(all.single.key, '1d6b:0104');
    });

    test('an invalid global defaults entry is ignored', () async {
      final store = await _newStore(<String, Object>{
        UsbQuirkStore.storageKey: jsonEncode(<String, Object?>{
          UsbQuirkStore.globalDefaultsField: <String, Object?>{
            'label': 'no ids',
          },
        }),
      });

      expect(store.globalDefaults, isNull);
    });
  });
}
