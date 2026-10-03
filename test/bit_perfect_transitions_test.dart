import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/domain/services/hires_audio_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Scanner extends Mock implements MediaScannerService {}

class _HiRes extends Mock implements HiResAudioService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const effectsChannel = MethodChannel(PulsrChannels.audioEffects);
  const device = AudioOutputInfo(
      deviceName: 'USB test DAC',
      isUsbDac: true,
      sampleRate: 48000,
      bitDepth: 24,
      isBitPerfectActive: true,
      isBitPerfectSupported: true);
  late _HiRes hires;
  late SettingsCubit cubit;
  final bypassCalls = <bool>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    bypassCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(effectsChannel, (call) async {
      if (call.method == 'setBypassDspForBitPerfect') {
        bypassCalls.add((call.arguments as Map)['bypass'] as bool);
        return true;
      }
      return null;
    });
    hires = _HiRes();
    when(() => hires.outputDeviceStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => hires.currentOutputInfo).thenReturn(device);
    when(() => hires.getAudioOutputInfo()).thenAnswer((_) async => device);
    when(() => hires.setBitPerfectMode(any())).thenAnswer((_) async => true);
    cubit = SettingsCubit(scannerService: _Scanner(), hiResAudioService: hires);
    await cubit.preferencesReady;
    bypassCalls.clear();
  });
  tearDown(() async {
    await cubit.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(effectsChannel, null);
  });
  test('strict ON/OFF/ON updates native bypass and saved switches', () async {
    await cubit.setStrictBitPerfect(true);
    expect(cubit.state.strictBitPerfect, true);
    expect(cubit.state.bitPerfectOutput, true);
    expect(cubit.state.bypassDspOnBitPerfect, true);
    expect(cubit.state.followTrackSampleRate, true);
    await cubit.setStrictBitPerfect(false);
    expect(cubit.state.strictBitPerfect, false);
    expect(cubit.state.bitPerfectOutput, false);
    await cubit.setStrictBitPerfect(true);
    expect(bypassCalls, [true, false, true]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.strictBitPerfect), true);
    expect(prefs.getBool(PrefsKeys.bitPerfectOutput), true);
  });
  test('disabling bit-perfect also clears strict mode', () async {
    await cubit.setStrictBitPerfect(true);
    await cubit.setBitPerfectOutput(false);
    expect(cubit.state.strictBitPerfect, false);
    expect(cubit.state.bitPerfectOutput, false);
    expect(bypassCalls, [true, false]);
  });
  test('strict refuses disabling bypass or follow-track', () async {
    await cubit.setStrictBitPerfect(true);
    await cubit.setBypassDspOnBitPerfect(false);
    await cubit.setFollowTrackSampleRate(false);
    expect(cubit.state.bypassDspOnBitPerfect, true);
    expect(cubit.state.followTrackSampleRate, true);
    expect(bypassCalls, [true]);
  });
  test('failed hardware OFF preserves enabled state', () async {
    await cubit.setStrictBitPerfect(true);
    when(() => hires.setBitPerfectMode(false)).thenAnswer((_) async => false);
    await cubit.setStrictBitPerfect(false);
    expect(cubit.state.strictBitPerfect, true);
    expect(cubit.state.bitPerfectOutput, true);
    expect(bypassCalls, [true]);
  });
  test('native rejection rolls hardware back without saving ON', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(effectsChannel, (_) async => false);
    await cubit.setStrictBitPerfect(true);
    expect(cubit.state.strictBitPerfect, false);
    expect(cubit.state.bitPerfectOutput, false);
    verify(() => hires.setBitPerfectMode(false)).called(1);
  });
  test('rapid ON/OFF requests run in order', () async {
    final gate = Completer<bool>();
    when(() => hires.setBitPerfectMode(true)).thenAnswer((_) => gate.future);
    final on = cubit.setBitPerfectOutput(true);
    await pumpEventQueue();
    final off = cubit.setBitPerfectOutput(false);
    await pumpEventQueue();
    verifyNever(() => hires.setBitPerfectMode(false));
    gate.complete(true);
    await Future.wait([on, off]);
    expect(cubit.state.bitPerfectOutput, false);
    expect(bypassCalls, [true, false]);
  });

  test('boot rejects unavailable saved strict mode and clears its switches',
      () async {
    await cubit.close();
    SharedPreferences.setMockInitialValues({
      PrefsKeys.strictBitPerfect: true,
      PrefsKeys.bitPerfectOutput: true,
      PrefsKeys.bypassDspOnBitPerfect: true,
    });
    when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => false);
    cubit = SettingsCubit(scannerService: _Scanner(), hiResAudioService: hires);
    await cubit.preferencesReady;
    expect(cubit.state.strictBitPerfect, false);
    expect(cubit.state.bitPerfectOutput, false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.strictBitPerfect), false);
    expect(prefs.getBool(PrefsKeys.bitPerfectOutput), false);
    expect(bypassCalls.last, false);
  });

  test('losing the DAC clears strict mode and restores native DSP', () async {
    await cubit.close();
    final routes = StreamController<AudioOutputInfo>.broadcast();
    when(() => hires.outputDeviceStream).thenAnswer((_) => routes.stream);
    cubit = SettingsCubit(scannerService: _Scanner(), hiResAudioService: hires);
    await cubit.preferencesReady;
    bypassCalls.clear();
    await cubit.setStrictBitPerfect(true);
    const disconnected = AudioOutputInfo(
        deviceName: 'Speaker',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
        isBitPerfectSupported: false);
    when(() => hires.getAudioOutputInfo())
        .thenAnswer((_) async => disconnected);
    routes.add(disconnected);
    await pumpEventQueue(times: 30);
    expect(cubit.state.strictBitPerfect, false);
    expect(cubit.state.bitPerfectOutput, false);
    expect(bypassCalls, [true, false]);
    await routes.close();
  });

  test('AAudio disables DVC and refuses re-enabling it on the bypassed path',
      () async {
    await cubit.setDvcEnabled(true);
    expect(cubit.state.dvcEnabled, true);
    await cubit.setAaudioOutputEnabled(true);
    expect(cubit.state.aaudioOutputEnabled, true);
    expect(cubit.state.dvcEnabled, false);
    await cubit.setDvcEnabled(true);
    expect(cubit.state.dvcEnabled, false);
    await cubit.setAaudioOutputEnabled(false);
    expect(cubit.state.aaudioOutputEnabled, false);
  });
}
