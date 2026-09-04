import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/device_profile_service.dart';
import 'package:pulsr/core/services/settings_profiles_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceProfileService.deviceKeyFor', () {
    test('built-in speaker collapses to one stable key', () {
      expect(
        DeviceProfileService.deviceKeyFor('Phone Speaker',
            deviceType: 'builtin', isBluetooth: false),
        'builtin:speaker',
      );
      expect(
        DeviceProfileService.deviceKeyFor('Eslams iPhone',
            deviceType: 'BUILTIN', isBluetooth: false),
        'builtin:speaker',
      );
    });

    test('bluetooth names are normalized (case + whitespace)', () {
      expect(
        DeviceProfileService.deviceKeyFor('  Sony   XM5 ',
            deviceType: 'bt', isBluetooth: true),
        'bt:sony xm5',
      );
      expect(
        DeviceProfileService.deviceKeyFor('SONY XM5',
            deviceType: 'BT', isBluetooth: true),
        'bt:sony xm5',
      );
    });

    test('same name on different transports is a different device', () {
      final usb = DeviceProfileService.deviceKeyFor('Sony XM5',
          deviceType: 'usb', isBluetooth: false);
      final bt = DeviceProfileService.deviceKeyFor('Sony XM5',
          deviceType: 'bt', isBluetooth: true);
      expect(usb, isNot(bt));
    });

    test('empty name keeps the type component', () {
      expect(
        DeviceProfileService.deviceKeyFor('  ',
            deviceType: 'wired', isBluetooth: false),
        'wired:unknown',
      );
    });
  });

  group('DeviceProfileService links + registry', () {
    late DeviceProfileService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = DeviceProfileService();
    });

    test('auto-switch defaults to enabled and toggles', () async {
      expect(await service.isAutoSwitchEnabled(), isTrue);
      await service.setAutoSwitchEnabled(false);
      expect(await service.isAutoSwitchEnabled(), isFalse);
    });

    test('remember/link/forget round-trip', () async {
      expect(await service.linkForDeviceKey('bt:sony xm5'), isNull);
      await service.rememberLink(
          deviceKey: 'bt:sony xm5',
          deviceLabel: 'Sony XM5',
          profileId: 'profile_car');
      final link = await service.linkForDeviceKey('bt:sony xm5');
      expect(link, isNotNull);
      expect(link!.profileId, 'profile_car');
      expect(link.deviceLabel, 'Sony XM5');
      await service.forgetLink('bt:sony xm5');
      expect(await service.linkForDeviceKey('bt:sony xm5'), isNull);
    });

    test('forgetLink for unknown key is a no-op', () async {
      await service.forgetLink('nope');
      expect(await service.getLinks(), isEmpty);
    });

    test('rememberDevice dedups, orders newest first and caps at 30', () async {
      for (var i = 0; i < 35; i++) {
        await service.rememberDevice('bt:dev$i', 'Dev $i');
      }
      await service.rememberDevice('bt:dev10', 'Dev 10 refreshed');
      final devices = await service.registryDevices();
      expect(devices.length, 30);
      expect(devices.first.deviceKey, 'bt:dev10');
      expect(devices.first.deviceLabel, 'Dev 10 refreshed');
      expect(devices.any((d) => d.deviceKey == 'bt:dev0'), isFalse);
      expect(devices.any((d) => d.deviceKey == 'bt:dev34'), isTrue);
    });
  });

  group('SettingsProfile JSON back-compat', () {
    test('round-trips the optional Phase-3 stage fields', () {
      const profile = SettingsProfile(
        id: 'p1',
        name: 'Test',
        type: ProfileType.custom,
        eqPresetName: 'Flat',
        saturationEnabled: true,
        dynamicEqEnabled: false,
      );
      final restored = SettingsProfile.fromJson(profile.toJson());
      expect(restored.saturationEnabled, isTrue);
      expect(restored.dynamicEqEnabled, isFalse);
      expect(restored.stereoWidthEnabled, isNull);
      expect(restored.subCrossoverEnabled, isNull);
      expect(restored.loudnessContourEnabled, isNull);
    });

    test('legacy JSON without the new keys decodes to nulls', () {
      final restored = SettingsProfile.fromJson({
        'id': 'p1',
        'name': 'Old',
        'type': 'custom',
        'eqPresetName': 'Flat',
      });
      expect(restored.saturationEnabled, isNull);
      expect(restored.bitPerfectEnabled, isFalse);
    });
  });
}