// Cross-toggle interaction tests: the settings that deliberately constrain,
// force, or block one another. These prove the *effect* of enabling one switch
// on the others, not just that the switch flips.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/data/services/hires_audio_service.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Scanner extends Mock implements MediaScannerService {}

class _HiRes extends Mock implements HiResAudioService {}

const _usbDac = AudioOutputInfo(
  deviceName: 'USB test DAC',
  isUsbDac: true,
  sampleRate: 48000,
  bitDepth: 24,
  isBitPerfectActive: true,
  isBitPerfectSupported: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const effectsChannel = MethodChannel(PulsrChannels.audioEffects);
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
    when(() => hires.currentOutputInfo).thenReturn(_usbDac);
    when(() => hires.getAudioOutputInfo()).thenAnswer((_) async => _usbDac);
    when(() => hires.setBitPerfectMode(any())).thenAnswer((_) async => true);
    when(() => hires.lastBitPerfectFailureReason).thenReturn(null);
    cubit = SettingsCubit(scannerService: _Scanner(), hiResAudioService: hires);
    await cubit.preferencesReady;
    bypassCalls.clear();
  });

  tearDown(() async {
    await cubit.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(effectsChannel, null);
  });

  group('Bit-Perfect family', () {
    test('enabling Bit-Perfect pushes bypass and persists', () async {
      await cubit.setBitPerfectOutput(true);
      expect(cubit.state.bitPerfectOutput, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.bitPerfectOutput), isTrue);
      // bypass is pushed for (enabled && bypassDspOnBitPerfect) == true
      expect(bypassCalls, [true]);
    });

    test('disabling Bit-Perfect clears Strict and persists', () async {
      await cubit.setStrictBitPerfect(true);
      expect(cubit.state.strictBitPerfect, isTrue);
      await cubit.setBitPerfectOutput(false);
      expect(cubit.state.bitPerfectOutput, isFalse);
      expect(cubit.state.strictBitPerfect, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.strictBitPerfect), isFalse);
    });

    test('Strict forces Bit-Perfect + bypass + follow-track together', () async {
      await cubit.setStrictBitPerfect(true);
      expect(cubit.state.strictBitPerfect, isTrue);
      expect(cubit.state.bitPerfectOutput, isTrue);
      expect(cubit.state.bypassDspOnBitPerfect, isTrue);
      expect(cubit.state.followTrackSampleRate, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.strictBitPerfect), isTrue);
      expect(prefs.getBool(PrefsKeys.followTrackSampleRate), isTrue);
    });

    test('Strict blocks disabling the DSP bypass', () async {
      await cubit.setStrictBitPerfect(true);
      await cubit.setBypassDspOnBitPerfect(false);
      expect(cubit.state.bypassDspOnBitPerfect, isTrue,
          reason: 'bypass cannot be disabled while strict is on');
      expect(cubit.state.errorMessage, isNotNull);
    });

    test('Strict blocks disabling follow-track sample rate', () async {
      await cubit.setStrictBitPerfect(true);
      await cubit.setFollowTrackSampleRate(false);
      expect(cubit.state.followTrackSampleRate, isTrue,
          reason: 'strict requires following the track rate');
      expect(cubit.state.errorMessage, isNotNull);
    });

    test('rejected Bit-Perfect never persists ON', () async {
      when(() => hires.setBitPerfectMode(true)).thenAnswer((_) async => false);
      await cubit.setBitPerfectOutput(true);
      expect(cubit.state.bitPerfectOutput, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.bitPerfectOutput), isFalse);
      expect(cubit.state.errorMessage, isNotNull);
    });
  });

  group('Gapless / Crossfade mutual exclusion', () {
    test('crossfade auto-disables gapless and persists both', () async {
      expect(cubit.state.gaplessPlayback, isTrue);
      await cubit.setCrossfade(4.0);
      expect(cubit.state.crossfadeSeconds, 4.0);
      expect(cubit.state.gaplessPlayback, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('setting_crossfade'), 4.0);
      expect(prefs.getBool('setting_gapless'), isFalse);
    });

    test('gapless auto-zeroes crossfade and persists both', () async {
      await cubit.setCrossfade(4.0);
      await cubit.setGapless(true);
      expect(cubit.state.gaplessPlayback, isTrue);
      expect(cubit.state.crossfadeSeconds, 0.0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_gapless'), isTrue);
      expect(prefs.getDouble('setting_crossfade'), 0.0);
    });

    test('crossfade is clamped to the supported range', () async {
      await cubit.setCrossfade(999.0);
      expect(cubit.state.crossfadeSeconds, 12.0);
      await cubit.setCrossfade(-5.0);
      expect(cubit.state.crossfadeSeconds, 0.0);
    });

    test('Bit-Perfect forces crossfade to zero', () async {
      await cubit.setCrossfade(6.0);
      expect(cubit.state.crossfadeSeconds, 6.0);
      await cubit.setBitPerfectOutput(true);
      expect(cubit.state.crossfadeSeconds, 0.0,
          reason: 'bit-perfect cannot overlap tracks');
    });
  });

  group('DSP-bypass conflicts', () {
    test('Bit-Perfect + bypass blocks enabling ReplayGain', () async {
      await cubit.setBitPerfectOutput(true);
      // Enabling bit-perfect with the bypass on already forces ReplayGain off,
      // so the later explicit request must not resurrect it.
      expect(cubit.state.replayGainMode, ReplayGainMode.off);
      await cubit.setReplayGainMode(ReplayGainMode.auto);
      expect(cubit.state.replayGainMode, ReplayGainMode.off,
          reason: 'ReplayGain must stay off under bit-perfect bypass');
      expect(cubit.state.errorMessage, isNotNull);
    });

    test('crossfade is rejected while Bit-Perfect bypass is active', () async {
      await cubit.setBitPerfectOutput(true);
      await cubit.setCrossfade(4.0);
      expect(cubit.state.crossfadeSeconds, 0.0);
      expect(cubit.state.errorMessage, isNotNull);
    });
  });

  group('DVC / AAudio output conflicts', () {
    test('AAudio Direct blocks DVC and forces crossfade off', () async {
      await cubit.setCrossfade(3.0);
      await cubit.setAaudioOutputEnabled(true);
      expect(cubit.state.aaudioOutputEnabled, isTrue);
      expect(cubit.state.crossfadeSeconds, 0.0);

      await cubit.setDvcEnabled(true);
      expect(cubit.state.dvcEnabled, isFalse,
          reason: 'DVC requires the active DSP path, not AAudio Direct');
      expect(cubit.state.errorMessage, isNotNull);
    });

    test('Bit-Perfect bypass blocks DVC and persists the block', () async {
      await cubit.setBitPerfectOutput(true);
      await cubit.setDvcEnabled(true);
      expect(cubit.state.dvcEnabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.dvcEnabled), isNull);
    });

    test('AAudio Direct disables an already-enabled DVC', () async {
      await cubit.setDvcEnabled(true);
      expect(cubit.state.dvcEnabled, isTrue);
      await cubit.setAaudioOutputEnabled(true);
      expect(cubit.state.dvcEnabled, isFalse,
          reason: 'enabling AAudio must turn DVC back off');
    });
  });
}
