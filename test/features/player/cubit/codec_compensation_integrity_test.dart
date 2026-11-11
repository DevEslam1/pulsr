import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/features/player/cubit/controllers/player_dsp_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_test_support.dart';

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(EqPreset.defaultPresets.first);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('0.5 applying preset while codec compensation is active yields exact preset gains', () async {
    final handler = RecordingAudioHandler();
    final settingsCubit = _MockSettingsCubit();

    const lossyBtDevice = AudioOutputInfo(
      deviceName: 'SBC/AAC Headphones',
      activeDeviceType: 'bluetooth',
      isBluetooth: true,
      btCodecName: 'aac',
      btCodecConnected: true,
      isUsbDac: false,
      sampleRate: 44100,
      bitDepth: 16,
      isBitPerfectActive: false,
    );

    when(() => settingsCubit.state).thenReturn(
      const SettingsState(currentOutputDevice: lossyBtDevice),
    );
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());

    var state = const PlayerState();
    late PlayerDspController controller;

    controller = PlayerDspController(
      audioHandler: handler,
      settingsCubit: settingsCubit,
      getState: () => state,
      emit: (s) => state = s,
      syncAudioEffects: () {},
      isClosed: () => false,
    );

    // 1. Trigger codec-aware compensation on lossy Bluetooth
    await controller.applyCodecAwareMusicCompensation();

    // Verify compensation altered the initial flat gains
    expect(state.eqPreset.gains, isNot(equals(EqPreset.defaultPresets.first.gains)));

    // 2. Now user applies a new preset (e.g. Bass Boost or Electronic) while comp was active
    final targetPreset = EqPreset.defaultPresets[1]; // non-flat preset
    final ok = await controller.applyPreset(targetPreset);
    expect(ok, isTrue);

    // 3. Gains in state must EQUAL the preset gains EXACTLY
    expect(state.eqPreset.gains, equals(targetPreset.gains));
  });

  test('0.5 user-enabled EQ while comp active is never force-disabled on comp deactivation', () async {
    final handler = RecordingAudioHandler();
    final settingsCubit = _MockSettingsCubit();

    const lossyBtDevice = AudioOutputInfo(
      deviceName: 'SBC/AAC Headphones',
      activeDeviceType: 'bluetooth',
      isBluetooth: true,
      btCodecName: 'aac',
      btCodecConnected: true,
      isUsbDac: false,
      sampleRate: 44100,
      bitDepth: 16,
      isBitPerfectActive: false,
    );

    var currentDevice = lossyBtDevice;
    when(() => settingsCubit.state).thenAnswer((_) => SettingsState(currentOutputDevice: currentDevice));
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());

    var state = const PlayerState(
      dsp: DspSlice(isEqEnabled: false),
    );
    late PlayerDspController controller;

    controller = PlayerDspController(
      audioHandler: handler,
      settingsCubit: settingsCubit,
      getState: () => state,
      emit: (s) => state = s,
      syncAudioEffects: () {},
      isClosed: () => false,
    );

    // 1. Apply compensation (which forces EQ on for the lossy Bluetooth overlay)
    await controller.applyCodecAwareMusicCompensation();
    expect(state.isEqEnabled, isTrue);

    // 2. While comp is active, user explicitly enables EQ
    await controller.setEqualizerEnabled(true);

    // 3. Switch to a wired lossless device where comp deactivates
    currentDevice = const AudioOutputInfo(
      deviceName: 'Wired Headphones',
      activeDeviceType: 'wired',
      isBluetooth: false,
      isUsbDac: false,
      sampleRate: 96000,
      bitDepth: 24,
      isBitPerfectActive: false,
    );

    await controller.applyCodecAwareMusicCompensation();

    // 4. EQ must STILL be enabled because user explicitly expressed intent
    expect(state.isEqEnabled, isTrue);
  });
}
