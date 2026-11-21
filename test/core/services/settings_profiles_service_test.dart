import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/services/theme_scheduler_service.dart';
import 'package:pulsr/data/services/settings_profiles_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsProfilesService', () {
    test('returns built-in defaults before any custom profile exists',
        () async {
      final service = SettingsProfilesService();
      final profiles = await service.getProfiles();
      expect(profiles, SettingsProfile.defaultProfiles);
    });

    test('saveProfile adds a custom profile and persists it', () async {
      final service = SettingsProfilesService();
      const custom = SettingsProfile(
        id: 'profile_custom_1',
        name: 'My Setup',
        type: ProfileType.custom,
        eqPresetName: 'Bass Boost',
        volumeBoost: 0.25,
      );
      await service.saveProfile(custom);

      final reloaded = SettingsProfilesService();
      final profiles = await reloaded.getProfiles();
      expect(profiles.length, SettingsProfile.defaultProfiles.length + 1);
      final saved = profiles.firstWhere((p) => p.id == custom.id);
      expect(saved.name, 'My Setup');
      expect(saved.type, ProfileType.custom);
      expect(saved.eqPresetName, 'Bass Boost');
      expect(saved.volumeBoost, 0.25);
    });

    test('saveProfile updates an existing profile in place', () async {
      final service = SettingsProfilesService();
      const first = SettingsProfile(
        id: 'profile_custom_1',
        name: 'First',
        type: ProfileType.custom,
      );
      const renamed = SettingsProfile(
        id: 'profile_custom_1',
        name: 'Renamed',
        type: ProfileType.custom,
      );
      await service.saveProfile(first);
      await service.saveProfile(renamed);

      final profiles = await service.getProfiles();
      final matches = profiles.where((p) => p.id == 'profile_custom_1');
      expect(matches.length, 1);
      expect(matches.first.name, 'Renamed');
    });

    test('deleteProfile removes the custom profile', () async {
      final service = SettingsProfilesService();
      await service.saveProfile(const SettingsProfile(
        id: 'profile_custom_1',
        name: 'My Setup',
        type: ProfileType.custom,
      ));
      await service.deleteProfile('profile_custom_1');

      final profiles = await service.getProfiles();
      expect(profiles.any((p) => p.id == 'profile_custom_1'), isFalse);
    });

    test('SettingsProfile.fromJson null-guards id and name', () {
      final p = SettingsProfile.fromJson(<String, dynamic>{});
      expect(p.id, '');
      expect(p.name, 'Custom Profile');
    });

    test('SettingsProfile copyWith, ==, hashCode works properly', () {
      const p1 = SettingsProfile(
        id: 'p1',
        name: 'Profile 1',
        type: ProfileType.custom,
      );
      final p2 = p1.copyWith(name: 'Profile 2');
      expect(p1, isNot(equals(p2)));
      expect(p1.hashCode, isNot(equals(p2.hashCode)));

      final p3 = p2.copyWith(name: 'Profile 1');
      expect(p1, equals(p3));
      expect(p1.hashCode, equals(p3.hashCode));
    });

    test('getProfiles skips malformed entries individually without wiping profiles', () async {
      SharedPreferences.setMockInitialValues({
        'setting_custom_profiles': '[{"id":"valid_1","name":"Valid 1"}, {"corrupt":true}, 12345, {"id":"valid_2","name":"Valid 2"}]',
      });
      final service = SettingsProfilesService();
      final profiles = await service.getProfiles();
      expect(profiles.length, 2);
      expect(profiles[0].id, 'valid_1');
      expect(profiles[1].id, 'valid_2');
    });
  });

  group('ThemeSchedulerService', () {
    test('updateScheduleHours stores the requested window', () {
      final service = ThemeSchedulerService();
      expect(service.startHour, 19);
      expect(service.endHour, 6);

      service.updateScheduleHours(start: 21, end: 7);
      expect(service.startHour, 21);
      expect(service.endHour, 7);
      service.dispose();
    });

    test('startScheduler reports the current night state', () {
      final service = ThemeSchedulerService();
      var called = false;
      service.startScheduler((_) => called = true);
      expect(called, isTrue);
      service.stopScheduler();
      service.dispose();
    });
  });
}
