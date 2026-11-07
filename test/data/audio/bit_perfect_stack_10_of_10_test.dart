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

    test('Section 6.2: Live radio and 32-bit float sources are blocked from Bit-Perfect', () {
      final radioBlock = AudioConflicts.bitPerfectSourceBlockedReason(
        isRadio: true,
        path: 'https://stream.pulsr.fm/live_radio',
      );
      expect(radioBlock, isNotNull);

      final floatLossyBlock = AudioConflicts.bitPerfectSourceBlockedReason(
        bitDepth: 32,
        isLossy: true,
        path: 'https://example.com/stream.mp3',
      );
      expect(floatLossyBlock, isNotNull);

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
  });
}
