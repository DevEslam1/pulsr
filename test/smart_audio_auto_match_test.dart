// test/smart_audio_auto_match_test.dart
//
// Verifies the Smart Audio device watcher: in Auto mode a connected headphone
// is matched to its bundled AutoEQ profile and applied; in Manual mode nothing
// is applied automatically.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/device_profile_service.dart';
import 'package:pulsr/core/services/hires_audio_service.dart';
import 'package:pulsr/core/services/settings_profiles_service.dart';
import 'package:pulsr/core/services/smart_audio_service.dart';
import 'package:pulsr/data/audio/headphone_profiles_repository.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/services/smart_audio_plan.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_cubit_test.dart'; // TestPulsrAudioHandler + mocktail mocks

class FakeHiResAudioService extends HiResAudioService {
  final StreamController<AudioOutputInfo> deviceController =
      StreamController<AudioOutputInfo>.broadcast();

  @override
  Stream<AudioOutputInfo> get outputDeviceStream => deviceController.stream;

  void emitDevice(AudioOutputInfo info) => deviceController.add(info);
}

AudioOutputInfo btDevice(String name) => AudioOutputInfo(
      deviceName: name,
      isUsbDac: false,
      sampleRate: 48000,
      bitDepth: 24,
      isBitPerfectActive: false,
      activeDeviceType: 'bluetooth',
      isBluetooth: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHiResAudioService fakeHiRes;
  late TestPulsrAudioHandler handler;
  late SettingsCubit settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeHiRes = FakeHiResAudioService();
    handler = TestPulsrAudioHandler();
    settings = SettingsCubit(scannerService: MockMediaScannerService());
  });

  tearDown(() async {
    await fakeHiRes.deviceController.close();
    await settings.close();
  });

  Future<PlayerCubit> buildCubit() async {
    return PlayerCubit(
      audioHandler: handler,
      repository: MockMusicRepository(),
      toggleFavoriteUseCase: MockToggleFavoriteUseCase(),
      settingsCubit: settings,
      settingsProfilesService: SettingsProfilesService(),
      deviceProfileService: DeviceProfileService(),
      hiResAudioService: fakeHiRes,
      smartAudioService: SmartAudioService(),
    );
  }

  test('Auto mode applies the AutoEQ profile matched for the headphone',
      () async {
    // Sanity: the bundled profiles must be loadable for this feature to work.
    final repo = HeadphoneProfilesRepository();
    await repo.loadProfiles();
    expect(repo.profiles, isNotEmpty);

    final cubit = await buildCubit();
    addTearDown(cubit.close);

    fakeHiRes.emitDevice(btDevice('WH-1000XM5'));
    await pumpEventQueue();

    expect(cubit.state.selectedHeadphoneProfile?.id, 'sony_wh1000xm5');
  });

  test('Auto mode remembers the match for the device key', () async {
    final cubit = await buildCubit();
    addTearDown(cubit.close);

    fakeHiRes.emitDevice(btDevice('WH-1000XM5'));
    await pumpEventQueue();

    final key = DeviceProfileService.deviceKeyFromInfo(btDevice('WH-1000XM5'));
    final link = await SmartAudioService().linkForDeviceKey(key);
    expect(link?.profileId, 'sony_wh1000xm5');
  });

  test('Manual mode does not auto-apply any profile', () async {
    await SmartAudioService().setMode(SmartAudioMode.manual);
    final cubit = await buildCubit();
    addTearDown(cubit.close);

    fakeHiRes.emitDevice(btDevice('WH-1000XM5'));
    await pumpEventQueue();

    expect(cubit.state.selectedHeadphoneProfile, isNull);
  });
}
