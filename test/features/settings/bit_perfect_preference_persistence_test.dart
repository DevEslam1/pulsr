// Regression coverage for the saved Bit-Perfect choice across route changes:
// booting without a USB DAC must not erase the preference, plugging a DAC in
// must re-arm the transport by itself, and unplugging must only suspend it.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/services/hires_audio_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/settings_section_harness.dart';

/// Route source the cubit subscribes to, with the transport calls the arming
/// path makes kept off the platform channels.
class _FakeRouteAudio extends HiResAudioService {
  _FakeRouteAudio(this.info);

  AudioOutputInfo info;
  final StreamController<AudioOutputInfo> _routes =
      StreamController<AudioOutputInfo>.broadcast();
  int enableCalls = 0;
  int disableCalls = 0;
  bool transportOn = false;

  @override
  Stream<AudioOutputInfo> get outputDeviceStream => _routes.stream;

  @override
  AudioOutputInfo? get currentOutputInfo => info;

  @override
  Future<AudioOutputInfo> getAudioOutputInfo({
    bool allowCached = false,
  }) async =>
      info;

  @override
  Future<bool> setBitPerfectMode(bool enabled) async {
    if (enabled) {
      enableCalls++;
    } else {
      disableCalls++;
    }
    transportOn = enabled;
    return true;
  }

  /// Drives the same broadcast path the platform event channel uses.
  void emit(AudioOutputInfo next) {
    info = next;
    _routes.add(next);
  }

  @override
  void dispose() {
    if (!_routes.isClosed) _routes.close();
    super.dispose();
  }
}

const _usbDac = AudioOutputInfo(
  deviceName: 'Test USB DAC',
  isUsbDac: true,
  sampleRate: 48000,
  bitDepth: 24,
  isBitPerfectActive: false,
  isBitPerfectSupported: true,
  activeDeviceType: 'usb',
);

const _speaker = AudioOutputInfo(
  deviceName: 'Speaker',
  isUsbDac: false,
  sampleRate: 48000,
  bitDepth: 16,
  isBitPerfectActive: false,
  isBitPerfectSupported: false,
  activeDeviceType: 'builtin',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    stubSettingsChannels();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    clearSettingsChannels();
  });

  Future<SettingsCubit> boot(_FakeRouteAudio audio) async {
    final cubit = SettingsCubit(
      scannerService: MockMediaScannerService(),
      hiResAudioService: audio,
    );
    addTearDown(cubit.close);
    await cubit.preferencesReady;
    return cubit;
  }

  test('boot without a DAC keeps the saved preference, transport off',
      () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.bitPerfectOutput: true,
      PrefsKeys.strictBitPerfect: true,
    });
    final audio = _FakeRouteAudio(_speaker);
    addTearDown(audio.dispose);

    final cubit = await boot(audio);

    // The runtime transport cannot open on a speaker, so it stays off...
    expect(cubit.state.bitPerfectOutput, isFalse);
    expect(cubit.state.strictBitPerfect, isFalse);
    // ...but the user's choice is not this boot's outcome to erase.
    expect(cubit.bitPerfectPreferred, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.bitPerfectOutput), isTrue);
    expect(prefs.getBool(PrefsKeys.strictBitPerfect), isTrue);
    expect(audio.enableCalls, 0);
  });

  test('plugging a USB DAC re-arms the saved preference', () async {
    SharedPreferences.setMockInitialValues({PrefsKeys.bitPerfectOutput: true});
    final audio = _FakeRouteAudio(_speaker);
    addTearDown(audio.dispose);

    final cubit = await boot(audio);
    expect(cubit.state.bitPerfectOutput, isFalse);

    audio.emit(_usbDac);
    await pumpEventQueue(times: 40);

    expect(cubit.state.currentOutputDevice?.isUsbDac, isTrue);
    expect(cubit.state.bitPerfectOutput, isTrue);
    expect(audio.enableCalls, 1);
    expect(audio.transportOn, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.bitPerfectOutput), isTrue);
  });

  test(
      'plugging a USB DAC restores a saved Strict choice, not just Bit-Perfect',
      () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.bitPerfectOutput: true,
      PrefsKeys.strictBitPerfect: true,
    });
    final audio = _FakeRouteAudio(_speaker);
    addTearDown(audio.dispose);

    final cubit = await boot(audio);
    expect(cubit.state.strictBitPerfect, isFalse);

    audio.emit(_usbDac);
    await pumpEventQueue(times: 80);

    // Ordinary Bit-Perfect is armed first, then Strict upgrades it. A DAC that
    // refuses Strict still keeps the working exclusive setup.
    expect(cubit.state.bitPerfectOutput, isTrue);
    expect(cubit.state.strictBitPerfect, isTrue);
    expect(audio.enableCalls, greaterThanOrEqualTo(1));
  });

  test('unplugging suspends the transport without erasing the preference',
      () async {
    SharedPreferences.setMockInitialValues({PrefsKeys.bitPerfectOutput: true});
    final audio = _FakeRouteAudio(_usbDac);
    addTearDown(audio.dispose);

    final cubit = await boot(audio);
    expect(cubit.state.bitPerfectOutput, isTrue);

    audio.emit(_speaker);
    await pumpEventQueue(times: 40);

    expect(cubit.state.bitPerfectOutput, isFalse);
    expect(cubit.state.strictBitPerfect, isFalse);
    expect(audio.disableCalls, 1);
    expect(audio.transportOn, isFalse);
    // The unplug releases the DAC, not the user's choice.
    expect(cubit.bitPerfectPreferred, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.bitPerfectOutput), isTrue);

    // The same saved choice is what the next attach arms from.
    audio.emit(_usbDac);
    await pumpEventQueue(times: 40);
    expect(cubit.state.bitPerfectOutput, isTrue);
    expect(prefs.getBool(PrefsKeys.bitPerfectOutput), isTrue);
  });

  test(
      'H-48 startup does not flicker bitPerfectOutput true when no USB DAC is attached',
      () async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.bitPerfectOutput: true,
    });
    final audio = _FakeRouteAudio(_speaker);
    addTearDown(audio.dispose);

    final cubit = SettingsCubit(
      scannerService: MockMediaScannerService(),
      hiResAudioService: audio,
    );
    final observedBitPerfect = <bool>[cubit.state.bitPerfectOutput];
    final sub =
        cubit.stream.listen((s) => observedBitPerfect.add(s.bitPerfectOutput));
    addTearDown(() async {
      await sub.cancel();
      await cubit.close();
    });

    await cubit.preferencesReady;
    await pumpEventQueue(times: 40);

    expect(observedBitPerfect, everyElement(isFalse));
    expect(cubit.bitPerfectPreferred, isTrue);
  });
}
