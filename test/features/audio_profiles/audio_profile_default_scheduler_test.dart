// Regression test for P0-1.8: the profile marked as default is actually applied
// once at startup and again when the pinned USB DAC is attached — never twice
// for the same event (the last-applied marker prevents loops).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';
import 'package:pulsr/features/audio_profiles/audio_profile_bootstrap.dart';
import 'package:pulsr/features/audio_profiles/audio_profile_keys.dart';
import 'package:pulsr/features/audio_profiles/audio_profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SharedPreferences prefs;

  final String flagKey = AudioProfileKeys.whitelist.first;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_audio_profile_sched');
    SharedPreferences.setMockInitialValues(<String, Object>{flagKey: true});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  AudioProfileService buildService() => AudioProfileService(
        prefs: prefs,
        rootDirectory: () async => tempDir,
        reloadSettings: () async {},
        resyncEffects: () async {},
        clock: () => DateTime(2024, 5, 1, 10),
      );

  test('startup applies the unpinned default exactly once', () async {
    final service = buildService();
    final profile = await service.captureCurrent('Studio');
    expect(await service.setGlobalDefaults(profile.id), isTrue);

    // Something else changed the setting after the profile was captured.
    await prefs.setBool(flagKey, false);

    final report = await service.applyDefaultProfile(startup: true);

    expect(report, isNotNull);
    expect(report!.appliedCount, greaterThan(0));
    expect(prefs.getBool(flagKey), isTrue,
        reason: 'the default profile restores its captured value');

    // A settings refresh replays the startup path: it must be a no-op.
    expect(await service.applyDefaultProfile(startup: true), isNull);
  });

  test('a device-pinned profile applies only on the matching DAC', () async {
    final service = buildService();
    final profile = await service.captureCurrent(
      'USB DAC',
      deviceVid: 0x152A,
      devicePid: 0x8757,
    );
    expect(await service.setGlobalDefaults(profile.id), isTrue);
    await prefs.setBool(flagKey, false);

    // Pinned profile + no device (startup before enumeration) => skip.
    expect(await service.applyDefaultProfile(startup: true), isNull);
    expect(prefs.getBool(flagKey), isFalse);

    // A different DAC must not apply it.
    expect(
      await service.applyDefaultProfile(
        deviceVid: 0x1234,
        devicePid: 0x0001,
        deviceKey: 'usb:4660:1',
      ),
      isNull,
    );
    expect(prefs.getBool(flagKey), isFalse);

    // The pinned DAC applies it.
    final applied = await service.applyDefaultProfile(
      deviceVid: 0x152A,
      devicePid: 0x8757,
      deviceKey: 'usb:5418:34647',
    );
    expect(applied, isNotNull);
    expect(prefs.getBool(flagKey), isTrue);

    // The same attach event again is a no-op (no apply loop).
    expect(
      await service.applyDefaultProfile(
        deviceVid: 0x152A,
        devicePid: 0x8757,
        deviceKey: 'usb:5418:34647',
      ),
      isNull,
    );
  });

  test('clearing the marker lets the profile apply again', () async {
    final service = buildService();
    final profile = await service.captureCurrent('Portable');
    expect(await service.setGlobalDefaults(profile.id), isTrue);

    expect(await service.applyDefaultProfile(startup: true), isNotNull);
    expect(await service.applyDefaultProfile(startup: true), isNull);

    await service.clearLastAppliedMarker();
    expect(await service.applyDefaultProfile(startup: true), isNotNull);
  });

  test('no default profile means nothing runs', () async {
    final service = buildService();
    expect(await service.applyDefaultProfile(startup: true), isNull);
    expect(await service.applyDefaultProfile(deviceVid: 1, devicePid: 2), isNull);
  });

  test('a missing profile file is skipped without throwing', () async {
    final service = buildService();
    final profile = await service.captureCurrent('Gone');
    expect(await service.setGlobalDefaults(profile.id), isTrue);
    await service.delete(profile.id);

    expect(await service.applyDefaultProfile(startup: true), isNull);
  });

  group('AudioProfileBootstrap glue', () {
    const matchingDac = UsbExclusiveStatus(
      attached: true,
      permitted: true,
      vendorId: 0x152A,
      productId: 0x8757,
    );
    const detached = UsbExclusiveStatus(attached: false, permitted: false);

    Future<void> waitForMarker(Object? expected) async {
      for (var i = 0; i < 200; i++) {
        final marker = prefs.getString(AudioProfileService.lastAppliedProfileKey);
        if (marker == expected) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('marker never became $expected '
          '(was ${prefs.getString(AudioProfileService.lastAppliedProfileKey)})');
    }

    test('startup skips a pinned profile, attach applies, detach frees it',
        () async {
      final service = buildService();
      final profile = await service.captureCurrent(
        'USB DAC',
        deviceVid: 0x152A,
        devicePid: 0x8757,
      );
      expect(await service.setGlobalDefaults(profile.id), isTrue);
      await prefs.setBool(flagKey, false);

      final usb = UsbExclusiveService();
      final bootstrap =
          AudioProfileBootstrap(service: service, usbExclusive: usb);
      addTearDown(bootstrap.dispose);

      // Startup with no DAC attached: a pinned profile has no device to match.
      expect(await bootstrap.start(), isNull);
      expect(prefs.getString(AudioProfileService.lastAppliedProfileKey), isNull);
      expect(prefs.getBool(flagKey), isFalse);

      // Matching DAC attached: the listener applies the profile.
      final marker = '${profile.id}@usb:5418:34647';
      usb.debugPublishStatus(matchingDac);
      await waitForMarker(marker);
      expect(prefs.getBool(flagKey), isTrue,
          reason: 'the applied profile restores its captured value');

      // A duplicate attach is not a second apply (marker unchanged and the
      // live value is left alone).
      await prefs.setBool(flagKey, false);
      usb.debugPublishStatus(matchingDac);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(prefs.getBool(flagKey), isFalse,
          reason: 'no duplicate apply for the same attachment');

      // Detaching frees the marker so plugging the DAC back in re-applies.
      usb.debugPublishStatus(detached);
      await waitForMarker(null);
      expect(prefs.getBool(flagKey), isFalse);

      usb.debugPublishStatus(matchingDac);
      await waitForMarker(marker);
      expect(prefs.getBool(flagKey), isTrue);
    });

    test(
        'AudioProfileBootstrap runs trailing pass when USB status arrives during active apply',
        () async {
      final service = buildService();
      final profile = await service.captureCurrent(
        'USB DAC',
        deviceVid: 0x152A,
        devicePid: 0x8757,
      );
      expect(await service.setGlobalDefaults(profile.id), isTrue);
      await prefs.setBool(flagKey, false);

      final usb = UsbExclusiveService();
      final bootstrap =
          AudioProfileBootstrap(service: service, usbExclusive: usb);
      addTearDown(bootstrap.dispose);

      await bootstrap.start();

      final marker = '${profile.id}@usb:5418:34647';
      usb.debugPublishStatus(detached);
      usb.debugPublishStatus(matchingDac);
      await waitForMarker(marker);
      expect(prefs.getBool(flagKey), isTrue);
    });

    test('BUG-P2-9: detects DAC A -> DAC B hot-swap without intermediate detach',
        () async {
      final service = buildService();
      final profile = await service.captureCurrent(
        'DAC B Profile',
        deviceVid: 0x152A,
        devicePid: 0x8757,
      );
      expect(await service.setGlobalDefaults(profile.id), isTrue);
      await prefs.setBool(flagKey, false);

      const dacA = UsbExclusiveStatus(
        attached: true,
        permitted: true,
        vendorId: 0x1111,
        productId: 0x2222,
      );
      final usb = UsbExclusiveService();
      final bootstrap =
          AudioProfileBootstrap(service: service, usbExclusive: usb);
      addTearDown(bootstrap.dispose);

      await bootstrap.start();
      usb.debugPublishStatus(dacA);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(prefs.getBool(flagKey), isFalse);

      // Hot-swap directly from dacA to matchingDac (attached stays true)
      final marker = '${profile.id}@usb:5418:34647';
      usb.debugPublishStatus(matchingDac);
      await waitForMarker(marker);
      expect(prefs.getBool(flagKey), isTrue);
    });
  });
}
