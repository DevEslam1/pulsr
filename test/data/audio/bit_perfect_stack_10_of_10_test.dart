// test/data/audio/bit_perfect_stack_10_of_10_test.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulsr/core/constants/audio_feature_info.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/bit_perfect_chain.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/data/services/hires_audio_service.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';

class _MockHiResAudioService extends Mock implements HiResAudioService {}
class _MockMediaScannerService extends Mock implements MediaScannerService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BitPerfectChain Verdict Ordering', () {
    test('1. notRequested takes precedence over active=false and mismatches', () {
      final res = assessBitPerfectChain(
        requested: false,
        active: false,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 48000,
        outputBitDepth: 24,
      );
      expect(res.verdict, BitPerfectChainVerdict.notRequested);
      expect(res.isProblem, isFalse);
    });

    test('2. inactive takes precedence over matching or mismatched formats', () {
      final res = assessBitPerfectChain(
        requested: true,
        active: false,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 24,
        failureReason: 'format_unsupported',
      );
      expect(res.verdict, BitPerfectChainVerdict.inactive);
      expect(res.reasonCode, 'format_unsupported');
      expect(res.isProblem, isTrue);
    });

    test('3. DoP carrier takes precedence over sample modification and rate mismatch', () {
      final res = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 2822400,
        sourceBitDepth: 1,
        outputSampleRate: 176400,
        outputBitDepth: 24,
        isDsdDop: true,
        samplesModified: true,
      );
      expect(res.verdict, BitPerfectChainVerdict.unverified);
      expect(res.reasonCode, 'dop_carrier_not_measured');
      expect(res.isProblem, isFalse);
    });

    test('4. samplesModified takes precedence over channels altered and rate mismatch', () {
      final res = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 48000,
        outputBitDepth: 16,
        samplesModified: true,
        channelsAltered: true,
      );
      expect(res.verdict, BitPerfectChainVerdict.unverified);
      expect(res.reasonCode, 'samples_modified');
      expect(res.isVerified, isFalse);
    });

    test('5. channelsAltered takes precedence over rate mismatch', () {
      final res = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 48000,
        outputBitDepth: 16,
        channelsAltered: true,
      );
      expect(res.verdict, BitPerfectChainVerdict.unverified);
      expect(res.reasonCode, 'channels_remapped');
      expect(res.isVerified, isFalse);
    });

    test('6. rate unknown (<= 0) takes precedence over rate mismatch', () {
      final res = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 0,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 24,
      );
      expect(res.verdict, BitPerfectChainVerdict.unverified);
      expect(res.reasonCode, 'rate_unknown');
    });

    test('7. rate mismatch takes precedence over depth unknown and depth reduction', () {
      final res = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 24,
        outputSampleRate: 48000,
        outputBitDepth: 16,
      );
      expect(res.verdict, BitPerfectChainVerdict.resampled);
      expect(res.reasonCode, 'rate_mismatch');
      expect(res.isResampled, isTrue);
      expect(res.isProblem, isTrue);
    });

    test('8. source depth unknown (<= 0) takes precedence over depth reduction', () {
      final res = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 0,
        outputSampleRate: 96000,
        outputBitDepth: 16,
      );
      expect(res.verdict, BitPerfectChainVerdict.unverified);
      expect(res.reasonCode, 'source_depth_unknown');
    });

    test('9. output depth unknown (<= 0) results in unverified', () {
      final res = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 0,
      );
      expect(res.verdict, BitPerfectChainVerdict.unverified);
      expect(res.reasonCode, 'depth_unknown');
    });

    test('10. output depth lower than source yields depthReduced', () {
      final res = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 16,
      );
      expect(res.verdict, BitPerfectChainVerdict.depthReduced);
      expect(res.reasonCode, 'depth_truncated');
      expect(res.isDepthReduced, isTrue);
      expect(res.isProblem, isTrue);
    });

    test('10b. sourceCodecUnconfirmed takes precedence over matching formats and yields unverified', () {
      final res = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 24,
        rateVerified: true,
        sourceCodecUnconfirmed: true,
      );
      expect(res.verdict, BitPerfectChainVerdict.unverified);
      expect(res.reasonCode, 'source_codec_unconfirmed');
      expect(res.isVerified, isFalse);
    });

    test('11. matching rates and equal/wider output depth yields verified', () {
      final res = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 32,
      );
      expect(res.verdict, BitPerfectChainVerdict.verified);
      expect(res.isVerified, isTrue);
      expect(res.isProblem, isFalse);
    });
  });

  group('DspSlice Value Equality (C.4)', () {
    test('default DspSlice instances are equal and share hashCode', () {
      const dsp1 = DspSlice();
      const dsp2 = DspSlice();
      expect(dsp1, equals(dsp2));
      expect(dsp1.hashCode, equals(dsp2.hashCode));
    });

    test('changing any parameter produces inequality', () {
      const base = DspSlice();
      final eqMod = base.copyWith(isEqEnabled: true);
      final volMod = base.copyWith(volumeBoost: 0.5);
      final mbcMod = base.copyWith(isMultibandCompressorEnabled: true);
      final revMod = base.copyWith(isReverbEnabled: true);
      final dynMod = base.copyWith(isDynamicBassEnabled: true);

      expect(base == eqMod, isFalse);
      expect(base == volMod, isFalse);
      expect(base == mbcMod, isFalse);
      expect(base == revMod, isFalse);
      expect(base == dynMod, isFalse);

      expect(base.hashCode == eqMod.hashCode, isFalse);
    });
  });

  group('AudioConflicts Block and Bypass Rules', () {
    test('strictBitPerfectBlockedReason blocks Bluetooth and unconnected devices', () {
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(null),
        isNotNull,
      );

      const btDevice = AudioOutputInfo(
        deviceName: 'Bluetooth Headphones',
        isBluetooth: true,
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
      );
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(btDevice),
        contains('Bluetooth'),
      );
    });

    test('strictBitPerfectBlockedReason allows USB DAC without hard blockers', () {
      const usbDevice = AudioOutputInfo(
        deviceName: 'AudioQuest Dragonfly',
        isBluetooth: false,
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: false,
      );
      expect(AudioConflicts.strictBitPerfectBlockedReason(usbDevice), isNull);
    });

    test('bitPerfectBlockedReason surfaces hard failure reasons', () {
      expect(
        AudioConflicts.bitPerfectReasonMessage('usb_not_supported'),
        contains('exclusive bit-perfect output for this USB DAC'),
      );
      expect(
        AudioConflicts.bitPerfectReasonMessage('requires_android_14_for_usb'),
        contains('Android 14+'),
      );
      expect(
        AudioConflicts.bitPerfectReasonMessage('target_format_unavailable'),
        contains('selected sample rate / bit depth'),
      );
      expect(
        AudioConflicts.bitPerfectReasonMessage('set_mixer_attributes_failed'),
        contains('refused exclusive mode'),
      );
    });

    test('volumeBoostClippingWarning warns when preamp + boost exceeds 0 dBFS', () {
      expect(AudioConflicts.volumeBoostClippingWarning(0.1, 0.0), isNotNull);
      expect(AudioConflicts.volumeBoostClippingWarning(0.5, -6.0), isNull);
    });
  });

  group('SettingsAudioActions Mutex & Concurrency Hardening', () {
    late SettingsCubit cubit;
    late _MockHiResAudioService hires;
    late _MockMediaScannerService scanner;
    const usbChannel = MethodChannel(PulsrChannels.usbExclusive);
    const effectsChannel = MethodChannel(PulsrChannels.audioEffects);

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      hires = _MockHiResAudioService();
      scanner = _MockMediaScannerService();

      when(() => hires.outputDeviceStream).thenAnswer((_) => const Stream.empty());
      when(() => hires.currentOutputInfo).thenReturn(const AudioOutputInfo(
        deviceName: 'Test USB DAC',
        isUsbDac: true,
        sampleRate: 48000,
        bitDepth: 24,
        isBitPerfectActive: true,
      ));
      when(() => hires.setBitPerfectMode(any())).thenAnswer((_) async => true);
      when(() => hires.selectOutputDevice(any())).thenAnswer(
        (_) async => const OutputRouteResult(success: true),
      );
      when(() => hires.clearOutputDevice()).thenAnswer((_) async => true);
      when(() => hires.setTargetOutputFormat(
            sampleRate: any(named: 'sampleRate'),
            bitDepth: any(named: 'bitDepth'),
          )).thenAnswer((_) async => true);
      when(() => hires.getAudioOutputInfo()).thenAnswer(
        (_) async => const AudioOutputInfo(
          deviceName: 'Test USB DAC',
          isUsbDac: true,
          sampleRate: 48000,
          bitDepth: 24,
          isBitPerfectActive: true,
        ),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(usbChannel, (call) async {
        switch (call.method) {
          case 'getStatus':
            return {
              'deviceId': 1,
              'attached': true,
              'permitted': true,
              'streamingSupported': true,
              'streamingActive': true,
              'streamingSampleRate': 48000,
              'streamingBitDepth': 24,
              'streamingChannels': 2,
              'supportedRates': [44100, 48000, 96000],
            };
          case 'startStreaming':
            return {'success': true, 'resultCode': 0};
          case 'stopStreaming':
            return {'success': true};
          case 'getProducerChannels':
            return 2;
          default:
            return null;
        }
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(effectsChannel, (call) async => true);

      cubit = SettingsCubit(scannerService: scanner, hiResAudioService: hires);
      await cubit.preferencesReady;
      await pumpEventQueue();
    });

    tearDown(() async {
      await cubit.close();
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(usbChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(effectsChannel, null);
    });

    test('concurrent mutex paths do not deadlock', () async {
      final futures = <Future>[
        cubit.selectOutputDevice(1),
        cubit.clearOutputDevice(),
        cubit.setBitPerfectTrackFormat(sampleRate: 48000, bitDepth: 24, channels: 2),
        cubit.setAaudioOutputEnabled(true),
        cubit.setAaudioOutputEnabled(false),
      ];

      await Future.wait(futures).timeout(const Duration(seconds: 5));
      expect(cubit.isClosed, isFalse);
    });

    test('refresh-sequence stale result drop: slow response does not overwrite fresh state', () async {
      final slowCompleter = Completer<AudioOutputInfo>();
      const fastInfo = AudioOutputInfo(
        deviceName: 'Fast Updated DAC',
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: true,
      );

      var callCount = 0;
      when(() => hires.getAudioOutputInfo()).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          return slowCompleter.future;
        }
        return Future.value(fastInfo);
      });

      final slowCall = cubit.refreshOutputDevice();
      final fastCall = cubit.refreshOutputDevice();

      await fastCall;
      expect(cubit.state.currentOutputDevice?.deviceName, 'Fast Updated DAC');

      slowCompleter.complete(const AudioOutputInfo(
        deviceName: 'Stale DAC',
        isUsbDac: true,
        sampleRate: 44100,
        bitDepth: 16,
        isBitPerfectActive: false,
      ));
      await slowCall;

      expect(cubit.state.currentOutputDevice?.deviceName, 'Fast Updated DAC');
    });

    test('direct mode track refusal suspends without dropping preference (C.1)', () async {
      // Platform mixer mode refuses bit-perfect so direct USB stream takes over
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => false);
      await cubit.setBitPerfectOutput(true);
      expect(cubit.state.bitPerfectOutput, isTrue);
      expect(cubit.bitPerfectViaDirectStream, isTrue);

      // Make startStreaming fail with format_unsupported for next track
      var isRefusedTrack = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(usbChannel, (call) async {
        if (call.method == 'startStreaming') {
          if (isRefusedTrack) {
            return {'success': false, 'error': 'format_unsupported'};
          }
          return {'success': true, 'resultCode': 0};
        }
        if (call.method == 'stopStreaming') {
          return {'success': true};
        }
        if (call.method == 'getProducerChannels') {
          return 2;
        }
        if (call.method == 'getStatus') {
          return {
            'deviceId': 1,
            'attached': true,
            'permitted': true,
            'streamingActive': !isRefusedTrack,
            'streamingSupported': true,
            'streamingSampleRate': isRefusedTrack ? 0 : 48000,
            'streamingBitDepth': isRefusedTrack ? 0 : 24,
            'streamingChannels': isRefusedTrack ? 0 : 2,
            'supportedRates': [44100, 48000],
          };
        }
        return null;
      });

      when(() => hires.getAudioOutputInfo()).thenAnswer(
        (_) async => AudioOutputInfo(
          deviceName: 'Test USB DAC',
          isUsbDac: true,
          sampleRate: 48000,
          bitDepth: 16,
          isBitPerfectActive: !isRefusedTrack,
        ),
      );

      final applied = await cubit.setBitPerfectTrackFormat(
        sampleRate: 192000,
        bitDepth: 24,
        channels: 2,
      );

      expect(applied, isFalse);
      // Preference stays armed
      expect(cubit.state.bitPerfectOutput, isTrue);
      // UI state reports inactive with truthful failure reason
      expect(cubit.state.currentOutputDevice?.isBitPerfectActive, isFalse);
      expect(cubit.state.currentOutputDevice?.bitPerfectFailureReason, isNotNull);
      expect(cubit.state.errorMessage, contains('Bit-Perfect stays armed'));

      // Next track at supported 48000 succeeds
      isRefusedTrack = false;
      final nextApplied = await cubit.setBitPerfectTrackFormat(
        sampleRate: 48000,
        bitDepth: 24,
        channels: 2,
      );
      expect(nextApplied, isTrue);
      expect(cubit.state.currentOutputDevice?.isBitPerfectActive, isTrue);
    });

    test('strict enable failure triggers rollback', () async {
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => false);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(usbChannel, (call) async {
        if (call.method == 'startStreaming') {
          return {'success': false, 'error': 'claim_failed'};
        }
        if (call.method == 'stopStreaming') return {'success': true};
        if (call.method == 'getStatus') {
          return {
            'deviceId': 1,
            'attached': true,
            'permitted': true,
            'streamingActive': false,
            'streamingSupported': true,
          };
        }
        return null;
      });

      await cubit.setStrictBitPerfect(true);
      expect(cubit.state.strictBitPerfect, isFalse);
      expect(cubit.state.bitPerfectOutput, isFalse);
      expect(cubit.state.bypassDspOnBitPerfect, isTrue); // Restores previous value
    });

    test('Regression 1: selectOutputDevice returns false and does not switch route when stopStreaming fails', () async {
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => false);
      // Start direct USB streaming
      await cubit.setBitPerfectOutput(true);
      expect(cubit.bitPerfectViaDirectStream, isTrue);

      // Make stopStreaming fail
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(usbChannel, (call) async {
        if (call.method == 'stopStreaming') return {'success': false};
        return null;
      });

      var selectCalled = false;
      when(() => hires.selectOutputDevice(any())).thenAnswer((_) async {
        selectCalled = true;
        return const OutputRouteResult(success: true);
      });

      final switched = await cubit.selectOutputDevice(2);
      expect(switched, isFalse);
      expect(selectCalled, isFalse);
      expect(cubit.state.errorMessage, contains('The direct USB stream could not be stopped'));
    });

    test('Regression 2: setBluetoothLatencyOffsetMs per-device vs global prefs', () async {
      // 1. Current output is USB DAC (not Bluetooth)
      await cubit.setBluetoothLatencyOffsetMs(120);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.bluetoothLatencyOffsetMs), 120);

      // 2. Switch output to Bluetooth device
      const btDevice = AudioOutputInfo(
        deviceName: 'Sony WH-1000XM4',
        isBluetooth: true,
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
      );
      when(() => hires.getAudioOutputInfo()).thenAnswer((_) async => btDevice);
      await cubit.refreshOutputDevice();
      expect(cubit.state.currentOutputDevice?.isBluetooth, isTrue);

      // Set latency for Bluetooth device - should NOT overwrite global default
      await prefs.setInt(PrefsKeys.bluetoothLatencyOffsetMs, 50); // set known global
      await cubit.setBluetoothLatencyOffsetMs(250);
      expect(prefs.getInt(PrefsKeys.bluetoothLatencyOffsetMs), 50); // global unchanged!
      expect(cubit.state.bluetoothLatencyOffsetMs, 250);
    });

    test('Regression 3: _rollbackBitPerfectEnable restores previous user preferences on failure', () async {
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => false);
      // User sets bypassDsp to false and followRate to false
      await cubit.setBypassDspOnBitPerfect(false);
      await cubit.setFollowTrackSampleRate(false);
      expect(cubit.state.bypassDspOnBitPerfect, isFalse);
      expect(cubit.state.followTrackSampleRate, isFalse);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(usbChannel, (call) async {
        if (call.method == 'startStreaming') {
          return {'success': false, 'error': 'claim_failed'};
        }
        if (call.method == 'stopStreaming') return {'success': true};
        if (call.method == 'getStatus') {
          return {
            'deviceId': 1,
            'attached': true,
            'permitted': true,
            'streamingActive': false,
            'streamingSupported': true,
          };
        }
        return null;
      });

      await cubit.setStrictBitPerfect(true);
      expect(cubit.state.strictBitPerfect, isFalse);
      expect(cubit.state.bitPerfectOutput, isFalse);
      // Restored previous values!
      expect(cubit.state.bypassDspOnBitPerfect, isFalse);
      expect(cubit.state.followTrackSampleRate, isFalse);
    });

    test('Regression 4: _setStrictBitPerfect(false) triggers refreshOutputDevice()', () async {
      var refreshed = false;
      when(() => hires.getAudioOutputInfo()).thenAnswer((_) async {
        refreshed = true;
        return const AudioOutputInfo(
          deviceName: 'Refreshed DAC',
          isUsbDac: true,
          sampleRate: 48000,
          bitDepth: 24,
          isBitPerfectActive: false,
        );
      });

      await cubit.setStrictBitPerfect(false);
      expect(refreshed, isTrue);
      expect(cubit.state.currentOutputDevice?.deviceName, 'Refreshed DAC');
    });

    test('Strict disable restores pre-Strict values (enable with false/false -> disable returns false/false)', () async {
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => true);
      // Start with bypass=false and followRate=false
      await cubit.setBypassDspOnBitPerfect(false);
      await cubit.setFollowTrackSampleRate(false);
      expect(cubit.state.bypassDspOnBitPerfect, isFalse);
      expect(cubit.state.followTrackSampleRate, isFalse);

      // Enable Strict: forces bypass=true, follow=true
      await cubit.setStrictBitPerfect(true);
      expect(cubit.state.strictBitPerfect, isTrue);
      expect(cubit.state.bypassDspOnBitPerfect, isTrue);
      expect(cubit.state.followTrackSampleRate, isTrue);

      // Disable Strict: restores pre-Strict values (false and false)
      await cubit.setStrictBitPerfect(false);
      expect(cubit.state.strictBitPerfect, isFalse);
      expect(cubit.state.bypassDspOnBitPerfect, isFalse);
      expect(cubit.state.followTrackSampleRate, isFalse);
    });

    test('Double-enabling Strict Bit-Perfect preserves original pre-Strict values', () async {
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => true);
      await cubit.setBypassDspOnBitPerfect(false);
      await cubit.setFollowTrackSampleRate(false);

      // First enable: saves false / false, forces true / true
      await cubit.setStrictBitPerfect(true);
      expect(cubit.state.strictBitPerfect, isTrue);
      expect(cubit.state.bypassDspOnBitPerfect, isTrue);
      expect(cubit.state.followTrackSampleRate, isTrue);

      // Second enable: must NOT overwrite original false / false with true / true!
      await cubit.setStrictBitPerfect(true);
      expect(cubit.state.strictBitPerfect, isTrue);

      // Disable: restores original false / false
      await cubit.setStrictBitPerfect(false);
      expect(cubit.state.strictBitPerfect, isFalse);
      expect(cubit.state.bypassDspOnBitPerfect, isFalse);
      expect(cubit.state.followTrackSampleRate, isFalse);
    });

    test('Simulated restart: pre-Strict values loaded from SharedPreferences restore on disable and clear keys', () async {
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.strictBitPerfect, true);
      await prefs.setBool(PrefsKeys.bitPerfectOutput, true);
      await prefs.setBool(PrefsKeys.bypassDspOnBitPerfect, true);
      await prefs.setBool(PrefsKeys.followTrackSampleRate, true);
      await prefs.setBool(PrefsKeys.preStrictBypass, false);
      await prefs.setBool(PrefsKeys.preStrictFollowRate, false);

      final restartedCubit = SettingsCubit(scannerService: scanner, hiResAudioService: hires);
      await restartedCubit.preferencesReady;
      await pumpEventQueue();

      expect(restartedCubit.state.strictBitPerfect, isTrue);
      expect(restartedCubit.state.bypassDspOnBitPerfect, isTrue);
      expect(restartedCubit.state.followTrackSampleRate, isTrue);

      // Disabling Strict Bit-Perfect restores false / false from persisted preStrict keys
      await restartedCubit.setStrictBitPerfect(false);
      expect(restartedCubit.state.strictBitPerfect, isFalse);
      expect(restartedCubit.state.bypassDspOnBitPerfect, isFalse);
      expect(restartedCubit.state.followTrackSampleRate, isFalse);

      // Storage keys are cleaned up
      expect(prefs.getBool(PrefsKeys.preStrictBypass), isNull);
      expect(prefs.getBool(PrefsKeys.preStrictFollowRate), isNull);

      await restartedCubit.close();
    });

    test('Strict disable when never enabled in session does not change values', () async {
      await cubit.setBypassDspOnBitPerfect(false);
      await cubit.setFollowTrackSampleRate(true);

      // Never enabled strict, now call disable
      await cubit.setStrictBitPerfect(false);
      expect(cubit.state.strictBitPerfect, isFalse);
      expect(cubit.state.bypassDspOnBitPerfect, isFalse);
      expect(cubit.state.followTrackSampleRate, isTrue);
    });

    test('Section 6.2: Source classification, policy and per-track re-evaluation', () {
      // 1. Radio flag blocks
      final radioFlagBlock = AudioConflicts.bitPerfectSourceBlockedReason(
        isRadio: true,
        path: 'https://stream.pulsr.fm/live',
      );
      expect(radioFlagBlock, contains('Live radio and lossy streams'));

      // 2. HTTP URL containing "radio" is NOT blocked
      final normalHttpUrl = AudioConflicts.bitPerfectSourceBlockedReason(
        isRadio: false,
        path: 'https://cdn.example.com/radiohead/ok_computer_01.flac',
        bitDepth: 24,
      );
      expect(normalHttpUrl, isNull);

      // 3. ALAC .m4a allowed
      final alacBlock = AudioConflicts.bitPerfectSourceBlockedReason(
        path: '/storage/music/song.m4a',
        codec: 'alac',
        bitDepth: 24,
      );
      expect(alacBlock, isNull);

      // 4. Lossy local file (MP3) blocked per policy with clear message
      final mp3Block = AudioConflicts.bitPerfectSourceBlockedReason(
        path: '/storage/music/song.mp3',
        bitDepth: 16,
      );
      expect(mp3Block, contains('Live radio and lossy streams'));

      // 5. 32-bit float source gets dedicated 32-bit localized message
      final floatBlock = AudioConflicts.bitPerfectSourceBlockedReason(
        bitDepth: 32,
        path: '/storage/music/master.wav',
      );
      expect(floatBlock, contains('32-bit floating point audio requires lossy conversion'));

      // 5b. 32-bit integer is not float; it gets its own explanation.
      final int32Block = AudioConflicts.bitPerfectSourceBlockedReason(
        bitDepth: 32,
        path: '/storage/music/master.wav',
        codec: 'pcm_s32le',
      );
      expect(int32Block, contains('32-bit integer audio needs a float32 stage'));
      final float32CodecBlock = AudioConflicts.bitPerfectSourceBlockedReason(
        bitDepth: 32,
        path: '/storage/music/master.wav',
        codec: 'pcm_f32le',
      );
      expect(float32CodecBlock, contains('32-bit floating point audio'));
      expect(
        AudioConflicts.classifySourceSampleFormat(codec: 'pcm_s32le'),
        AudioSourceSampleFormat.integer,
      );
      expect(
        AudioConflicts.classifySourceSampleFormat(codec: 'pcm_f32le'),
        AudioSourceSampleFormat.float,
      );
      expect(
        AudioConflicts.classifySourceSampleFormat(path: '/music/a.wav'),
        AudioSourceSampleFormat.unknown,
      );

      // 6. Complete lossless extensions pass
      final flacBlock = AudioConflicts.bitPerfectSourceBlockedReason(
        bitDepth: 24,
        path: '/storage/music/song.flac',
      );
      expect(flacBlock, isNull);
    });

    test('Section 6.3: UAC1 sample-rate readback unsupported outcomes', () {
      // Normal mode allows stream, assessBitPerfectChain marks unverified with rate_not_verified
      final normalVerdict = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 44100,
        outputBitDepth: 16,
        rateVerified: false,
      );
      expect(normalVerdict.verdict, BitPerfectChainVerdict.unverified);
      expect(normalVerdict.reasonCode, 'rate_not_verified');

      // Strict mode refuses stream with uac1_rate_readback_unsupported
      expect(
        AudioConflicts.bitPerfectReasonMessage('uac1_rate_readback_unsupported'),
        contains('sample-rate readback'),
      );
      expect(
        UsbStreamResult.uac1RateReadbackUnsupported.toUserMessage(),
        contains('sample-rate readback'),
      );
    });

    test('Section 2.2: Channel counter semantics: mismatch on track A, clean track B gives clean verdict', () {
      // Track A had channel mismatch (status.channelMismatchFrames > 0 -> channelsAltered: true)
      final trackAVerdict = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 44100,
        outputBitDepth: 16,
        channelsAltered: true,
      );
      expect(trackAVerdict.verdict, BitPerfectChainVerdict.unverified);
      expect(trackAVerdict.reasonCode, 'channels_remapped');

      // Track B is clean (resetChannelMismatchFrames called, frames = 0 -> channelsAltered: false)
      final trackBVerdict = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 44100,
        outputBitDepth: 16,
        channelsAltered: false,
        rateVerified: true,
      );
      expect(trackBVerdict.verdict, BitPerfectChainVerdict.verified);
      expect(trackBVerdict.isVerified, isTrue);
    });

    test('Ambiguous containers: ALAC allowed & verifiable, no-codec allowed & unverified, AAC blocked', () {
      // 1. ALAC in .m4a with codec: 'alac' is allowed through and can be verified
      final alacState = AudioConflicts.classifySourceCodec(path: '/music/track.m4a', codec: 'alac');
      expect(alacState, AudioSourceCodecState.lossless);
      final alacBlocked = AudioConflicts.bitPerfectSourceBlockedReason(
        path: '/music/track.m4a',
        codec: 'alac',
        bitDepth: 24,
      );
      expect(alacBlocked, isNull);
      final alacAssessment = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 24,
        rateVerified: true,
        sourceCodecUnconfirmed: false,
      );
      expect(alacAssessment.verdict, BitPerfectChainVerdict.verified);
      expect(alacAssessment.isVerified, isTrue);

      // 2. Ambiguous .m4a with no codec is allowed through but assessBitPerfectChain marks unverified
      final unknownState = AudioConflicts.classifySourceCodec(path: '/music/track.m4a');
      expect(unknownState, AudioSourceCodecState.unknown);
      final unknownBlocked = AudioConflicts.bitPerfectSourceBlockedReason(
        path: '/music/track.m4a',
        bitDepth: 16,
      );
      expect(unknownBlocked, isNull);
      final unknownAssessment = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 44100,
        outputBitDepth: 16,
        rateVerified: true,
        sourceCodecUnconfirmed: true,
      );
      expect(unknownAssessment.verdict, BitPerfectChainVerdict.unverified);
      expect(unknownAssessment.reasonCode, 'source_codec_unconfirmed');
      expect(unknownAssessment.isVerified, isFalse);

      // 3. AAC in .m4a with codec: 'aac' is blocked per policy
      final aacState = AudioConflicts.classifySourceCodec(path: '/music/track.m4a', codec: 'aac');
      expect(aacState, AudioSourceCodecState.lossy);
      final aacBlocked = AudioConflicts.bitPerfectSourceBlockedReason(
        path: '/music/track.m4a',
        codec: 'aac',
        bitDepth: 16,
      );
      expect(aacBlocked, contains('Live radio and lossy streams'));
    });

    test('Mixer path source block error deduplication and clearance', () async {
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => true);
      when(() => hires.setTargetOutputFormat(
            sampleRate: any(named: 'sampleRate'),
            bitDepth: any(named: 'bitDepth'),
          )).thenAnswer((_) async => true);

      // Enable Bit-Perfect output via mixer path (not direct USB)
      await cubit.setBitPerfectOutput(true);
      expect(cubit.state.bitPerfectOutput, isTrue);
      expect(cubit.bitPerfectViaDirectStream, isFalse);

      final emittedErrors = <String?>[];
      final sub = cubit.stream.listen((s) {
        if (s.errorMessage != null) {
          emittedErrors.add(s.errorMessage);
        }
      });

      // 1. First blocked track: 32-bit source triggers error emission
      final res1 = await cubit.setBitPerfectTrackFormat(
        sampleRate: 48000,
        bitDepth: 32,
        channels: 2,
      );
      expect(res1, isFalse);
      expect(cubit.state.errorMessage, contains('32-bit floating point audio'));
      expect(emittedErrors.length, 1);

      // 2. Second track with same blocked reason: error emission is suppressed (deduplicated)
      final res2 = await cubit.setBitPerfectTrackFormat(
        sampleRate: 96000,
        bitDepth: 32,
        channels: 2,
      );
      expect(res2, isFalse);
      expect(emittedErrors.length, 1); // Not duplicated!

      // 3. Supported track succeeds and clears _lastSourceBlockReason and errorMessage
      final res3 = await cubit.setBitPerfectTrackFormat(
        sampleRate: 48000,
        bitDepth: 24,
        channels: 2,
      );
      expect(res3, isTrue);
      expect(cubit.state.errorMessage, isNull);

      // 4. Next blocked track emits the error again since the block reason was cleared
      final res4 = await cubit.setBitPerfectTrackFormat(
        sampleRate: 48000,
        bitDepth: 32,
        channels: 2,
      );
      expect(res4, isFalse);
      expect(cubit.state.errorMessage, contains('32-bit floating point audio'));
      expect(emittedErrors.length, 2);

      await sub.cancel();
    });

    test('1.2: Failed teardown during rollback keeps saved pre-Strict values; successful one clears them', () async {
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => false);
      final prefs = await SharedPreferences.getInstance();

      // Configure non-default bypass and followRate
      await cubit.setBypassDspOnBitPerfect(false);
      await cubit.setFollowTrackSampleRate(false);

      // 1. Enable Strict via direct stream
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(usbChannel, (call) async {
        switch (call.method) {
          case 'startStreaming':
            return {'success': true, 'resultCode': 0};
          case 'stopStreaming':
            return {'success': true};
          case 'getProducerChannels':
            return 2;
          case 'resetChannelMismatchFrames':
            return true;
          case 'getStatus':
            return {
              'deviceId': 1,
              'attached': true,
              'permitted': true,
              'streamingActive': true,
              'streamingSupported': true,
              'streamingSampleRate': 48000,
              'streamingBitDepth': 24,
              'streamingChannels': 2,
              'supportedRates': [44100, 48000],
            };
          default:
            return null;
        }
      });

      await cubit.setStrictBitPerfect(true);
      expect(cubit.state.strictBitPerfect, isTrue);
      expect(prefs.getBool(PrefsKeys.preStrictBypass), isFalse);
      expect(prefs.getBool(PrefsKeys.preStrictFollowRate), isFalse);

      // 2. Track format negotiation fails in Strict mode -> triggers rollback.
      // Initially, teardown fails (stopShouldSucceed = false).
      var stopShouldSucceed = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(usbChannel, (call) async {
        switch (call.method) {
          case 'startStreaming':
            return {'success': false, 'error': 'format_unsupported'};
          case 'stopStreaming':
            return {'success': stopShouldSucceed};
          case 'getProducerChannels':
            return 2;
          case 'resetChannelMismatchFrames':
            return true;
          case 'getStatus':
            return {
              'deviceId': 1,
              'attached': true,
              'permitted': true,
              'streamingActive': false,
              'streamingSupported': true,
            };
          default:
            return null;
        }
      });

      final appliedFail = await cubit.setBitPerfectTrackFormat(
        sampleRate: 192000,
        bitDepth: 24,
        channels: 2,
      );
      expect(appliedFail, isFalse);
      // Stop failed, so preStrict values must be KEPT in prefs
      expect(prefs.getBool(PrefsKeys.preStrictBypass), isFalse);
      expect(prefs.getBool(PrefsKeys.preStrictFollowRate), isFalse);

      // 3. Now teardown succeeds during rollback
      stopShouldSucceed = true;
      final appliedSuccessTeardown = await cubit.setBitPerfectTrackFormat(
        sampleRate: 192000,
        bitDepth: 24,
        channels: 2,
      );
      expect(appliedSuccessTeardown, isFalse);
      // Successful teardown clears them
      expect(prefs.getBool(PrefsKeys.preStrictBypass), isNull);
      expect(prefs.getBool(PrefsKeys.preStrictFollowRate), isNull);
    });

    test('1.3: Fresh cubit sees persisted pre-Strict values and does not overwrite them on re-enable', () async {
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.preStrictBypass, false);
      await prefs.setBool(PrefsKeys.preStrictFollowRate, false);

      final freshCubit = SettingsCubit(scannerService: scanner, hiResAudioService: hires);
      await freshCubit.preferencesReady;
      await pumpEventQueue();

      // Enable Strict in fresh cubit: must NOT overwrite saved false/false with current true/true
      await freshCubit.setStrictBitPerfect(true);
      expect(prefs.getBool(PrefsKeys.preStrictBypass), isFalse);
      expect(prefs.getBool(PrefsKeys.preStrictFollowRate), isFalse);

      // Disable Strict: must restore saved false/false
      await freshCubit.setStrictBitPerfect(false);
      expect(freshCubit.state.bypassDspOnBitPerfect, isFalse);
      expect(freshCubit.state.followTrackSampleRate, isFalse);

      await freshCubit.close();
    });

    test('1.5: Unrelated error set earlier survives a successful track change; source-block error is cleared', () async {
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => true);
      when(() => hires.setTargetOutputFormat(
            sampleRate: any(named: 'sampleRate'),
            bitDepth: any(named: 'bitDepth'),
          )).thenAnswer((_) async => true);

      await cubit.setBitPerfectOutput(true);

      // Part A: An unrelated error survives a successful track format apply
      cubit.emit(cubit.state.copyWith(errorMessage: 'Unrelated equalizer preset load failed'));
      expect(cubit.state.errorMessage, 'Unrelated equalizer preset load failed');

      final appliedA = await cubit.setBitPerfectTrackFormat(
        sampleRate: 48000,
        bitDepth: 24,
        channels: 2,
      );
      expect(appliedA, isTrue);
      // Unrelated error survives!
      expect(cubit.state.errorMessage, 'Unrelated equalizer preset load failed');

      // Part B: A source-block error is set and then cleared by a successful track change
      final appliedBlock = await cubit.setBitPerfectTrackFormat(
        sampleRate: 48000,
        bitDepth: 32,
        channels: 2,
      );
      expect(appliedBlock, isFalse);
      expect(cubit.state.errorMessage, contains('32-bit floating point audio'));

      final appliedClean = await cubit.setBitPerfectTrackFormat(
        sampleRate: 48000,
        bitDepth: 24,
        channels: 2,
      );
      expect(appliedClean, isTrue);
      // Source-block error is cleared!
      expect(cubit.state.errorMessage, isNull);
    });

    test('1.6: Scanned FLAC and ALAC tracks reach verified status, not unverified', () {
      // 1. Scanned FLAC track with codec: 'FLAC'
      final flacAssessment = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 24,
        rateVerified: true,
        sourceCodecUnconfirmed: AudioConflicts.classifySourceCodec(
              path: 'content://media/external/audio/media/100',
              codec: 'FLAC',
            ) ==
            AudioSourceCodecState.unknown,
      );
      expect(flacAssessment.verdict, BitPerfectChainVerdict.verified);
      expect(flacAssessment.isVerified, isTrue);

      // 2. Scanned ALAC track with codec: 'ALAC'
      final alacAssessment = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 44100,
        outputBitDepth: 16,
        rateVerified: true,
        sourceCodecUnconfirmed: AudioConflicts.classifySourceCodec(
              path: 'content://media/external/audio/media/101',
              codec: 'ALAC',
            ) ==
            AudioSourceCodecState.unknown,
      );
      expect(alacAssessment.verdict, BitPerfectChainVerdict.verified);
      expect(alacAssessment.isVerified, isTrue);
    });
  });
}
