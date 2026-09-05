import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/device_profile_service.dart';
import 'package:pulsr/core/services/hires_audio_service.dart';
import 'package:pulsr/core/services/settings_profiles_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_cubit_test.dart'; // TestPulsrAudioHandler + mocktail mocks

/// Host-safe fake: pushes [AudioOutputInfo] events without platform channels.
class FakeHiResAudioService extends HiResAudioService {
  final StreamController<AudioOutputInfo> deviceController =
      StreamController<AudioOutputInfo>.broadcast();

  @override
  Stream<AudioOutputInfo> get outputDeviceStream => deviceController.stream;

  void emitDevice(AudioOutputInfo info) => deviceController.add(info);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHiResAudioService fakeHiRes;
  late TestPulsrAudioHandler handler;
  late MockMusicRepository repo;
  late MockToggleFavoriteUseCase fav;
  late SettingsCubit settings;
  late SettingsProfilesService profilesService;
  late DeviceProfileService deviceService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeHiRes = FakeHiResAudioService();
    handler = TestPulsrAudioHandler();
    repo = MockMusicRepository();
    fav = MockToggleFavoriteUseCase();
    settings = SettingsCubit(scannerService: MockMediaScannerService());
    profilesService = SettingsProfilesService();
    deviceService = DeviceProfileService();
  });

  tearDown(() async {
    await fakeHiRes.deviceController.close();
    await settings.close();
  });

  AudioOutputInfo btDevice() => const AudioOutputInfo(
        deviceName: 'Sony XM5',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 24,
        isBitPerfectActive: false,
        activeDeviceType: 'bluetooth',
        isBluetooth: true,
      );

  // Derived, never hardcoded: the key format is owned by deviceKeyFor.
  String btKey() => DeviceProfileService.deviceKeyFromInfo(btDevice());

  Future<PlayerCubit> buildCubit() async {
    return PlayerCubit(
      audioHandler: handler,
      repository: repo,
      toggleFavoriteUseCase: fav,
      settingsCubit: settings,
      settingsProfilesService: profilesService,
      deviceProfileService: deviceService,
      hiResAudioService: fakeHiRes,
    );
  }

  test('auto-applies the linked profile when the linked device activates',
      () async {
    const profile = SettingsProfile(
      id: 'profile_car_test',
      name: 'Car Test',
      type: ProfileType.car,
      eqPresetName: 'Bass Boost',
      volumeBoost: 0.3,
      crossfadeEnabled: true,
      crossfadeSeconds: 4.0,
      saturationEnabled: true,
    );
    await profilesService.saveProfile(profile);
    await deviceService.rememberLink(
        deviceKey: btKey(),
        deviceLabel: 'Sony XM5',
        profileId: 'profile_car_test');
    final cubit = await buildCubit();
    addTearDown(cubit.close);

    fakeHiRes.emitDevice(btDevice());
    await pumpEventQueue();

    expect(cubit.state.eqPreset.name, 'Bass Boost');
    expect(cubit.state.isSaturationEnabled, isTrue);
    expect(cubit.state.volumeBoost, 0.3);
    expect(settings.state.crossfadeSeconds, 4.0);
  });

  test('same-device re-emission does not re-apply (format-change dedup)',
      () async {
    const first = SettingsProfile(
      id: 'profile_car_test',
      name: 'Car Test',
      type: ProfileType.car,
      eqPresetName: 'Bass Boost',
    );
    const second = SettingsProfile(
      id: 'profile_home_test',
      name: 'Home Test',
      type: ProfileType.home,
      eqPresetName: 'Flat',
    );
    await profilesService.saveProfile(first);
    await profilesService.saveProfile(second);
    await deviceService.rememberLink(
        deviceKey: btKey(),
        deviceLabel: 'Sony XM5',
        profileId: 'profile_car_test');
    final cubit = await buildCubit();
    addTearDown(cubit.close);

    fakeHiRes.emitDevice(btDevice());
    await pumpEventQueue();
    expect(cubit.state.eqPreset.name, 'Bass Boost');

    // Re-point the link, then re-emit the SAME device (e.g. sample-rate
    // change): the device key did not change, so no re-apply may happen.
    await deviceService.rememberLink(
        deviceKey: btKey(),
        deviceLabel: 'Sony XM5',
        profileId: 'profile_home_test');
    fakeHiRes.emitDevice(btDevice());
    await pumpEventQueue();
    expect(cubit.state.eqPreset.name, 'Bass Boost');
  });

  test('auto-switch disabled -> linked profile is not applied', () async {
    const profile = SettingsProfile(
      id: 'profile_car_test',
      name: 'Car Test',
      type: ProfileType.car,
      eqPresetName: 'Bass Boost',
      saturationEnabled: true,
    );
    await profilesService.saveProfile(profile);
    await deviceService.rememberLink(
        deviceKey: btKey(),
        deviceLabel: 'Sony XM5',
        profileId: 'profile_car_test');
    await deviceService.setAutoSwitchEnabled(false);
    final cubit = await buildCubit();
    addTearDown(cubit.close);

    fakeHiRes.emitDevice(btDevice());
    await pumpEventQueue();

    expect(cubit.state.eqPreset.name, 'Flat');
    expect(cubit.state.isSaturationEnabled, isFalse);
  });
}