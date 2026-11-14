import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/audio/format_aware_decoder.dart';
import 'package:pulsr/data/audio/usb_hardware_volume_curve.dart';
import 'package:pulsr/data/services/hires_audio_service.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/audio_quality_info.dart';
import 'package:pulsr/features/player/cubit/controllers/player_dsp_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/player/player_test_support.dart';
import '../../features/settings/support/settings_section_harness.dart';

class _MockHiResService extends Mock implements HiResAudioService {}

Uint8List _buildMinimalDsfBytes() {
  const blockSize = 16;
  const totalSize = 28 + 52 + 12 + blockSize * 2;
  final bytes = Uint8List(totalSize);
  final bd = ByteData.sublistView(bytes);
  // 'DSD ' chunk
  bytes.setAll(0, 'DSD '.codeUnits);
  bd.setUint64(4, 28, Endian.little);
  bd.setUint64(12, totalSize, Endian.little);
  bd.setUint64(20, 0, Endian.little);
  // 'fmt ' chunk
  bytes.setAll(28, 'fmt '.codeUnits);
  bd.setUint64(32, 52, Endian.little);
  bd.setUint32(40, 1, Endian.little); // format version
  bd.setUint32(44, 0, Endian.little); // format ID (DSD raw)
  bd.setUint32(48, 2, Endian.little); // channel type (stereo)
  bd.setUint32(52, 2, Endian.little); // channels
  bd.setUint32(56, 2822400, Endian.little); // DSD64 sample rate
  bd.setUint32(60, 1, Endian.little); // bits per sample (LSB first)
  bd.setUint64(64, 64, Endian.little); // sample count
  bd.setUint32(72, blockSize, Endian.little); // block size per channel
  // 'data' chunk
  bytes.setAll(80, 'data'.codeUnits);
  bd.setUint64(84, 12 + blockSize * 2, Endian.little);
  return bytes;
}

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(buildSong(0));
  });

  const usbChannel = MethodChannel(PulsrChannels.usbExclusive);
  const hiresChannel = MethodChannel(PulsrChannels.hiresDac);
  const audioEffectsChannel = MethodChannel(PulsrChannels.audioEffects);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AudioQualityInfo.dsdDopActive = false;
    AudioQualityInfo.dsdNativeActive = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    _messenger.setMockMethodCallHandler(usbChannel, null);
    _messenger.setMockMethodCallHandler(hiresChannel, null);
    _messenger.setMockMethodCallHandler(audioEffectsChannel, null);
  });

  test('UsbHardwareVolumeCurve.linearFor inverts dbFor accurately', () {
    for (final v in <double>[0.01, 0.1, 0.25, 0.5, 0.75, 1.0]) {
      final db = UsbHardwareVolumeCurve.dbFor(v, minDb: -60.0, maxDb: 0.0);
      final back =
          UsbHardwareVolumeCurve.linearFor(db, minDb: -60.0, maxDb: 0.0);
      expect(back, closeTo(v, 1e-9));
    }

    expect(
      UsbHardwareVolumeCurve.linearFor(-80.0, minDb: -80.0, maxDb: 6.0),
      0.0,
    );
    expect(
      UsbHardwareVolumeCurve.linearFor(6.0, minDb: -80.0, maxDb: 6.0),
      1.0,
    );
    expect(
      UsbHardwareVolumeCurve.linearFor(0.0, minDb: 0.0, maxDb: 0.0),
      1.0,
    );
    expect(
      UsbHardwareVolumeCurve.linearFor(double.nan, minDb: -60.0, maxDb: 0.0),
      1.0,
    );
  });

  test('UsbExclusiveService.resetHardwareVolume calls reset and refreshes status',
      () async {
    final calls = <String>[];
    _messenger.setMockMethodCallHandler(usbChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'resetHardwareVolume') {
        return <String, dynamic>{'hardwareVolumeApplied': false, 'volumeDb': 0.0};
      }
      if (call.method == 'getStatus') {
        return <String, dynamic>{
          'attached': true,
          'permitted': true,
          'hardwareVolumeApplied': false,
          'hardwareVolumeDb': 0.0,
        };
      }
      return null;
    });

    final ok = await UsbExclusiveService().resetHardwareVolume();
    expect(ok, isTrue);
    expect(calls, containsAllInOrder(<String>['resetHardwareVolume', 'getStatus']));
  });

  test('DsdDecoderHelper.probeDopCapabilities never implies nativeDsd from dsd512',
      () async {
    _messenger.setMockMethodCallHandler(hiresChannel, (call) async {
      if (call.method == 'getDopCapabilities') {
        return <String, dynamic>{
          'dsd64': true,
          'dsd128': true,
          'dsd256': true,
          'dsd512': true,
          'dop': true,
          'nativeDac': true,
          'nativeDsd': false,
        };
      }
      return null;
    });

    final caps = await DsdDecoderHelper.probeDopCapabilities();
    expect(caps.dsd512, isTrue);
    expect(caps.dop, isTrue);
    expect(caps.nativeDsd, isFalse);
  });

  test('decodeForFormat & decodeDsdFile with updateGlobalState=false avoid global flag race',
      () async {
    final tmpDir = Directory.systemTemp.createTempSync('pulsr_dsd_test_');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final dsfFile = File('${tmpDir.path}/track.dsf')
      ..writeAsBytesSync(_buildMinimalDsfBytes());

    AudioQualityInfo.dsdDopActive = false;
    AudioQualityInfo.dsdNativeActive = false;

    bool? resolvedDop;
    bool? resolvedNative;
    const dopCaps = DsdDacCapabilities(
      dsd64: true,
      dsd128: false,
      dsd256: false,
      dop: true,
      nativeDac: true,
    );
    final dsdSong = buildSong(10, path: dsfFile.path);
    const dsdTag = MediaItem(id: '10', title: 'DSD Track');

    final dopSource = await DsdDecoderHelper.decodeDsdFile(
      dsdSong,
      dsdTag,
      forceDop: true,
      dopCapabilities: dopCaps,
      updateGlobalState: false,
      onTransportResolved: (isDop, isNativeDsd) {
        resolvedDop = isDop;
        resolvedNative = isNativeDsd;
      },
    );
    expect(dopSource, isNotNull);
    expect(resolvedDop, isTrue);
    expect(resolvedNative, isFalse);
    // Active global state must remain untouched during background/parallel decode.
    expect(AudioQualityInfo.dsdDopActive, isFalse);
    expect(AudioQualityInfo.dsdNativeActive, isFalse);

    // Conversely, pre-resolving a non-DSD FLAC while DoP is currently active
    // must not clobber AudioQualityInfo.dsdDopActive.
    AudioQualityInfo.dsdDopActive = true;
    final decoder = FormatAwareDecoder(
      resolveYtmStream: (song, tag) async => AudioSource.uri(Uri.parse('https://example.com/a.m4a'), tag: tag),
    );
    bool? flacDop;
    bool? flacNative;
    await decoder.decodeForFormat(
      buildSong(11, path: '/music/test.flac'),
      const MediaItem(id: '11', title: 'FLAC Track'),
      updateGlobalState: false,
      onTransportResolved: (isDop, isNativeDsd) {
        flacDop = isDop;
        flacNative = isNativeDsd;
      },
    );
    expect(flacDop, isFalse);
    expect(flacNative, isFalse);
    expect(AudioQualityInfo.dsdDopActive, isTrue);
  });

  test('PlayerDspController resumes suspended Direct USB on matching track rate even with followFormat OFF',
      () async {
    var streamingActive = true;
    var streamingSampleRate = 48000;
    _messenger.setMockMethodCallHandler(usbChannel, (call) async {
      if (call.method == 'getStatus') {
        return <String, dynamic>{
          'attached': true,
          'permitted': true,
          'streamingSupported': true,
          'streamingActive': streamingActive,
          'streamingSampleRate': streamingActive ? streamingSampleRate : 0,
          'streamingBitDepth': streamingActive ? 24 : 0,
          'streamingChannels': streamingActive ? 2 : 0,
          'supportedRates': <int>[44100, 48000],
        };
      }
      if (call.method == 'getProducerChannels') {
        return 2;
      }
      return null;
    });
    await UsbExclusiveService().getStatus();

    final handler = RecordingAudioHandler();
    final hires = _MockHiResService();
    when(() => hires.outputDeviceStream)
        .thenAnswer((_) => const Stream<AudioOutputInfo>.empty());
    final settings = MockSettingsCubit();
    const currentSettings = SettingsState(
      bitPerfectOutput: true,
      bypassDspOnBitPerfect: true,
      outputFormatNegotiationEnabled: true,
      followTrackSampleRate: false,
      currentOutputDevice: AudioOutputInfo(
        deviceName: 'USB DAC',
        isUsbDac: true,
        sampleRate: 48000,
        targetSampleRate: 48000,
        bitDepth: 24,
        isBitPerfectActive: true,
        supportedSampleRates: <int>[44100, 48000],
      ),
    );
    when(() => settings.state).thenAnswer((_) => currentSettings);
    when(() => settings.bitPerfectViaDirectStream).thenReturn(true);
    when(() => settings.validateBitPerfectTrackSource(any()))
        .thenAnswer((_) async => true);
    when(() => settings.suspendDirectBitPerfectForTrack(any()))
        .thenAnswer((_) async {
      streamingActive = false;
      streamingSampleRate = 0;
      await UsbExclusiveService().getStatus();
      return true;
    });
    when(() => settings.setBitPerfectTrackFormat(
          sampleRate: any(named: 'sampleRate'),
          bitDepth: any(named: 'bitDepth'),
          channels: any(named: 'channels'),
        )).thenAnswer((_) async => true);
    when(() => settings.refreshOutputDevice()).thenAnswer((_) async {});

    var playerState = const PlayerState();
    final controller = PlayerDspController(
      audioHandler: handler,
      settingsCubit: settings,
      hiResAudioService: hires,
      getState: () => playerState,
      emit: (s) => playerState = s,
      syncAudioEffects: ({bool force = false}) {},
      isClosed: () => false,
    );
    addTearDown(controller.dispose);

    // Mismatched 96kHz track with followTrackSampleRate=false suspends Direct USB.
    await controller.maybeFollowTrackSampleRate(
      buildSong(1, path: '/music/96.flac', sampleRate: 96000, bitDepth: 24),
    );
    verify(() => settings.suspendDirectBitPerfectForTrack(any())).called(1);

    // Subsequent 48kHz track matching the locked rate must resume Direct USB.
    await controller.maybeFollowTrackSampleRate(
      buildSong(2, path: '/music/48.flac', sampleRate: 48000, bitDepth: 24),
    );
    verify(() => settings.setBitPerfectTrackFormat(
          sampleRate: 48000,
          bitDepth: 24,
        )).called(1);
  });

  test('SettingsCubit enables float output on bit-perfect and resets USB HW volume when disabled',
      () async {
    stubSettingsChannels();
    addTearDown(clearSettingsChannels);

    final usbCalls = <String>[];
    _messenger.setMockMethodCallHandler(usbChannel, (call) async {
      usbCalls.add(call.method);
      if (call.method == 'getStatus') {
        return <String, dynamic>{
          'attached': true,
          'permitted': true,
          'streamingSupported': true,
          'streamingActive': false,
        };
      }
      if (call.method == 'resetHardwareVolume') {
        return <String, dynamic>{'hardwareVolumeApplied': false};
      }
      return null;
    });
    _messenger.setMockMethodCallHandler(hiresChannel, (call) async {
      if (call.method == 'setBitPerfectModeDetailed') {
        return <String, dynamic>{'success': true};
      }
      if (call.method == 'setBitPerfectMode') return true;
      return null;
    });

    final cubit = SettingsCubit(scannerService: MockMediaScannerService());
    addTearDown(cubit.close);
    await cubit.preferencesReady;

    await cubit.setFloatOutputEnabled(false);
    expect(cubit.state.floatOutputEnabled, isFalse);

    await cubit.setBitPerfectOutput(true);
    expect(cubit.state.floatOutputEnabled, isTrue);

    await cubit.setUsbHardwareVolumeEnabled(true);
    usbCalls.clear();
    await cubit.setUsbHardwareVolumeEnabled(false);
    expect(cubit.state.usbHardwareVolumeEnabled, isFalse);
    expect(usbCalls, contains('resetHardwareVolume'));
  });
}
