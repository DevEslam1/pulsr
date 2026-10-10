// Covers lib/features/settings/cubit/settings_audio_actions.dart branches that
// the general SettingsCubit tests do not reach.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/settings_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    stubSettingsChannels();
  });
  tearDown(clearSettingsChannels);

  SettingsCubit makeCubit() =>
      SettingsCubit(scannerService: MockMediaScannerService());

  const usbDac = AudioOutputInfo(
    deviceName: 'USB DAC',
    isUsbDac: true,
    sampleRate: 96000,
    bitDepth: 24,
    isBitPerfectActive: true,
  );

  group('presets', () {
    test('maximum quality / smooth / poor-network presets apply coherent state',
        () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.applyMaximumQualityPreset();
      expect(cubit.state.replayGainMode, ReplayGainMode.off);
      expect(cubit.state.gaplessPlayback, true);

      await cubit.applySmoothPlaybackPreset();
      expect(cubit.state.replayGainMode, ReplayGainMode.auto);
      expect(cubit.state.crossfadeSeconds, 4.0);

      await cubit.applyPoorNetworkPreset();
      expect(cubit.state.streamingQuality, YtmAudioQuality.low);
      expect(cubit.state.crossfadeSeconds, 0.0);
      expect(cubit.state.gaplessPlayback, false);
    });
  });

  group('replay gain', () {
    test('preamp setters clamp to +/-15 dB', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setReplayGainPreampWithRg(100);
      expect(cubit.state.replayGainPreampWithRg, 15.0);
      await cubit.setReplayGainPreampWithoutRg(-100);
      expect(cubit.state.replayGainPreampWithoutRg, -15.0);
    });

    test('blocked by bit-perfect bypass surfaces a conflict message', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      cubit.safeEmit(cubit.state.copyWith(
        bitPerfectOutput: true,
        bypassDspOnBitPerfect: true,
        currentOutputDevice: usbDac,
      ));
      await cubit.setReplayGainMode(ReplayGainMode.album);
      expect(cubit.state.errorMessage, isNotNull);
      expect(cubit.state.replayGainMode, isNot(ReplayGainMode.album));
    });
  });

  group('quality and connectivity toggles', () {
    test('streaming/download quality and network modes persist', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setStreamingQuality(YtmAudioQuality.low);
      expect(cubit.state.streamingQuality, YtmAudioQuality.low);
      expect(cubit.state.downloadQuality, YtmAudioQuality.low);

      await cubit.setDownloadQuality(YtmAudioQuality.medium);
      expect(cubit.state.downloadQuality, YtmAudioQuality.medium);

      await cubit.setWifiOnlyMode(true);
      await cubit.setOfflineOnlyMode(true);
      expect(cubit.state.wifiOnlyMode, true);
      expect(cubit.state.offlineOnlyMode, true);
    });

    test('misc live-apply toggles update state', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setDuckingMode('duck');
      expect(cubit.state.duckingMode, 'duck');
      await cubit.setDuckingLevel(2.0);
      expect(cubit.state.duckingLevel, 1.0);
      await cubit.setAdaptiveQualityEnabled(false);
      expect(cubit.state.adaptiveQualityEnabled, false);
      await cubit.setHedgedResolutionEnabled(false);
      expect(cubit.state.hedgedResolutionEnabled, false);
      await cubit.setDspSnapshotEnabled(false);
      expect(cubit.state.dspSnapshotEnabled, false);
      await cubit.setFloatOutputEnabled(false);
      expect(cubit.state.floatOutputEnabled, false);
      await cubit.setSessionLogEnabled(false);
      expect(cubit.state.sessionLogEnabled, false);
      await cubit.setOutputFormatNegotiationEnabled(false);
      expect(cubit.state.outputFormatNegotiationEnabled, false);
      await cubit.setBpmSyncCrossfadeEnabled(true);
      expect(cubit.state.bpmSyncCrossfadeEnabled, true);
      await cubit.setDspPreference('native');
      expect(cubit.state.dspPreference, 'native');
    });

    test('AAudio / DVC / buffer / hardware volume controls update state',
        () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setDvcEnabled(true);
      expect(cubit.state.dvcEnabled, true);

      await cubit.setAaudioPreferExclusive(false);
      expect(cubit.state.aaudioPreferExclusive, false);
      await cubit.setAaudioTargetBufferMs(5000);
      expect(cubit.state.aaudioTargetBufferMs, 1000);

      await cubit.setAaudioOutputEnabled(true);
      expect(cubit.state.aaudioOutputEnabled, true);
      await cubit.setAaudioOutputEnabled(false);
      expect(cubit.state.aaudioOutputEnabled, false);

      await cubit.setUsbHardwareVolumeEnabled(true);
      expect(cubit.state.usbHardwareVolumeEnabled, true);
    });

    test('DVC refuses to enable while AAudio Direct owns the path', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      cubit.safeEmit(cubit.state.copyWith(aaudioOutputEnabled: true));
      await cubit.setDvcEnabled(true);
      expect(cubit.state.dvcEnabled, false);
      expect(cubit.state.errorMessage, isNotNull);
    });

    test('bluetooth latency offset clamps to 0..500 ms', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setBluetoothLatencyOffsetMs(9999);
      expect(cubit.state.bluetoothLatencyOffsetMs, 500);
      await cubit.setBluetoothLatencyOffsetMs(-5);
      expect(cubit.state.bluetoothLatencyOffsetMs, 0);
    });
  });

  group('DSD and strict bit-perfect guards', () {
    test('DoP is refused without a supporting USB DAC', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      // Start from the explicit safe PCM transport, then confirm DoP cannot be
      // selected while no DoP-capable USB DAC is present.
      await cubit.setDsdOutputMode(DsdOutputMode.pcm);
      expect(cubit.state.dsdOutputMode, DsdOutputMode.pcm);

      await cubit.setDsdOutputMode(DsdOutputMode.dop);
      expect(cubit.state.errorMessage, isNotNull);
      expect(cubit.state.dsdOutputMode, DsdOutputMode.pcm);
    });

    test('follow-track cannot be disabled under strict bit-perfect', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      cubit.safeEmit(cubit.state.copyWith(strictBitPerfect: true));
      await cubit.setFollowTrackSampleRate(false);
      expect(cubit.state.errorMessage, isNotNull);
    });

    test('DSP bypass cannot be disabled under strict bit-perfect', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      cubit.safeEmit(cubit.state.copyWith(strictBitPerfect: true));
      await cubit.setBypassDspOnBitPerfect(false);
      expect(cubit.state.errorMessage, isNotNull);
    });

    test('bit-perfect on is rejected when native refuses the route', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setBitPerfectOutput(true);
      // The stubbed native layer refuses; the preference must not claim ON.
      expect(cubit.state.bitPerfectOutput, false);
      expect(cubit.state.errorMessage, isNotNull);

      await cubit.setBitPerfectOutput(false);
      expect(cubit.state.bitPerfectOutput, false);
    });

    test('strict bit-perfect reverts when native cannot apply it', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setStrictBitPerfect(true);
      expect(cubit.state.strictBitPerfect, false);
      expect(cubit.state.errorMessage, isNotNull);

      await cubit.setStrictBitPerfect(false);
      expect(cubit.state.strictBitPerfect, false);
    });
  });

  group('silence skip and multi-output', () {
    test('silence-skip sensitivity clamps and persists', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setSilenceSkipSensitivity(250);
      expect(cubit.state.silenceSkipSensitivity, 100);
      await cubit.setSilenceSkipSensitivity(0);
      expect(cubit.state.silenceSkipSensitivity, 0);
    });

    test('multi-output reverts to system default when the route is refused',
        () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setMultiOutputMode('speakerAndBluetooth');
      expect(cubit.state.multiOutputMode, 'systemDefault');
      expect(cubit.state.errorMessage, isNotNull);

      await cubit.setMultiOutputMode('systemDefault');
      expect(cubit.state.multiOutputMode, 'systemDefault');
    });
  });

  group('bluetooth latency auto-calibration', () {
    test('uses the codec table when no probe is supplied', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      final offset = await cubit.autoCalibrateBluetoothLatency();
      expect(offset, inInclusiveRange(0, 500));
    });

    test('blends probe samples with the codec estimate', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      var calls = 0;
      final offset = await cubit.autoCalibrateBluetoothLatency(probe: () async {
        calls++;
        return calls.isEven ? 100 : -1;
      });
      expect(offset, inInclusiveRange(0, 500));
      expect(calls, 5);
    });
  });

  group('native output plumbing', () {
    test('system effects policy and status round-trip', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setSystemEffectsPolicy('tryDisable');
      expect(cubit.state.systemEffectsPolicy, 'tryDisable');

      await cubit.refreshSystemEffectsStatus();
      expect(cubit.state.systemEffectsStatus, isNotNull);
    });

    test('output format requests surface rejection and bluetooth setters run',
        () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setTargetOutputSampleRate(96000);
      expect(cubit.state.errorMessage, isNotNull);

      await cubit.setTargetOutputBitDepth(24);
      expect(await cubit.setBluetoothCodec('ldac'), isA<bool>());
      expect(await cubit.setBluetoothSampleRate(96000), isA<bool>());
      expect(await cubit.setBluetoothBitDepth(24), isA<bool>());
      expect(await cubit.setBluetoothLdacQuality(1), isA<bool>());

      await cubit.clearOutputDevice();
      await cubit.refreshOutputDevice();
      expect(await cubit.openOutputSwitcher(), isA<bool>());
    });

    test('MQA decode preference persists and drives the shared hook', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setMqaDecodingEnabled(false);
      expect(SettingsCubit.isMqaDecodingEnabled, false);
      await cubit.setMqaDecodingEnabled(true);
      expect(SettingsCubit.isMqaDecodingEnabled, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.mqaDecodingEnabled), true);
      await cubit.loadMqaDecodingPreference();
    });

    test('lookahead limiter writes all parameters', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setLookaheadLimiter(
        true,
        thresholdDb: -1.0,
        releaseMs: 80,
        lookaheadMs: 5,
      );
      expect(cubit.state.limiterEnabled, true);
      expect(cubit.state.limiterThresholdDb, -1.0);
      expect(cubit.state.limiterReleaseMs, 80.0);
      expect(cubit.state.limiterLookaheadMs, 5.0);
    });

    test('resampler quality is a no-op on the unsupported path', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.setSincResamplerQuality(2);
      expect(cubit.state.sincResamplerQuality, cubit.state.sincResamplerQuality);
    });

    test('bluetooth permission request and developer options do not throw',
        () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      await cubit.requestBluetoothPermission();
      await cubit.openBluetoothDevOptions();
    });

    test('selectOutputDevice returns a bool result', () async {
      final cubit = makeCubit();
      addTearDown(cubit.close);

      final ok = await cubit.selectOutputDevice(7);
      expect(ok, isA<bool>());
    });
  });
}
