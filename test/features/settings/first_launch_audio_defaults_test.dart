// test/features/settings/first_launch_audio_defaults_test.dart
//
// Locks the first-launch (fresh install) audio/DSP default state to the
// highest-quality path for every route:
//   * every coloring/effect DSP stage OFF, EQ disabled on a Flat preset,
//     preamp 0 dB, no boosts (the path stays bit-transparent by default);
//   * highest-precision internal path (float output ON, dither ON,
//     resampler OFF);
//   * Bit-Perfect / Strict Bit-Perfect OFF globally but coupled to the DSP
//     bypass, so an install does not lock out EQ/crossfade/ReplayGain;
//   * Bluetooth Hi-Res ON so the lossy link is never made worse;
//   * DSD output prefers DoP (native DSD over PCM) on a capable USB DAC;
//   * Smart Audio ON (auto) so capable devices engage the best path with no
//     user tuning;
//   * streaming + download quality at the highest tier.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/domain/services/smart_audio_plan.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('first-launch SettingsState audio defaults are clean/neutral', () {
    const s = SettingsState();

    test('no coloring/effect DSP stage is on by default', () {
      expect(s.crossfeedEnabled, isFalse);
      expect(s.reverbEnabled, isFalse);
      expect(s.monoMix, isFalse);
      expect(s.stereoBalance, 0.0);
      // Limiter is a safety stage; it stays at its existing OFF default and
      // only engages when something boosts (nothing does by default).
      expect(s.limiterEnabled, isFalse);
    });

    test('highest-precision internal path: float ON, resampler OFF', () {
      expect(s.floatOutputEnabled, isTrue);
      expect(s.sincResamplerEnabled, isFalse);
      // Per-track output-format negotiation stays on so hi-res is automatic.
      expect(s.outputFormatNegotiationEnabled, isTrue);
    });

    test('bit-perfect stays opt-in; BT Hi-Res ON; DSD prefers DoP', () {
      expect(s.bitPerfectOutput, isFalse);
      expect(s.strictBitPerfect, isFalse);
      expect(s.bypassDspOnBitPerfect, isTrue);
      // Bluetooth Hi-Res is ON: it never makes the lossy link worse and has no
      // DSP-conflict cost.
      expect(s.bluetoothHiResEnabled, isTrue);
      // AAudio Direct is an alternate exclusive path that conflicts with the
      // Bit-Perfect direct-USB tee, so it stays opt-in.
      expect(s.aaudioOutputEnabled, isFalse);
      expect(s.dvcEnabled, isFalse);
      expect(s.usbHardwareVolumeEnabled, isFalse);
      expect(s.dsdOutputMode, DsdOutputMode.dop);
    });

    test('ReplayGain is OFF (pure level/tone by default)', () {
      expect(s.replayGainMode, ReplayGainMode.off);
    });

    test('streaming and download quality default to the highest tier', () {
      expect(s.streamingQuality, YtmAudioQuality.high);
      expect(s.downloadQuality, YtmAudioQuality.high);
      // `high` is the top of the enum — i.e. maximum available quality.
      expect(YtmAudioQuality.values.last, YtmAudioQuality.high);
    });
  });

  group('Smart Audio is ON (auto) by default', () {
    test('a missing stored mode resolves to auto', () {
      expect(SmartAudioMode.fromName(null), SmartAudioMode.auto);
      expect(SmartAudioMode.fromName('bogus'), SmartAudioMode.auto);
    });
  });

  group('first-launch EqualizerManager defaults are neutral', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const {});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.pulsr.music/audio_effects'),
        (MethodCall call) async => null,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.pulsr.music/audio_effects'),
        null,
      );
    });

    test('EQ disabled on a Flat preset, preamp 0 dB, no boosts', () {
      final eq = EqualizerManager();
      expect(eq.isEnabled, isFalse);
      expect(eq.currentPreset.name, 'Flat');
      expect(eq.currentPreset.gains.every((g) => g == 0.0), isTrue,
          reason: 'the active preset must start neutral (all bands 0 dB)');
      expect(eq.currentPreset.bassBoost, 0.0);
      expect(eq.preampDb, 0.0);
      expect(eq.volumeBoost, 0.0);
      expect(eq.selectedHeadphoneProfile, isNull);
      expect(eq.eqBandCount, 10);
    });

    test('every effect/coloring stage flag is off', () {
      final eq = EqualizerManager();
      expect(eq.isVirtualizerEnabled, isFalse);
      expect(eq.isSpatializerEnabled, isFalse);
      expect(eq.isDynamicsEnabled, isFalse);
      expect(eq.isCrossfeedEnabled, isFalse);
      expect(eq.isReverbEnabled, isFalse);
      expect(eq.isSaturationEnabled, isFalse);
      expect(eq.isStereoWidthEnabled, isFalse);
      expect(eq.isLoudnessContourEnabled, isFalse);
      expect(eq.isSubCrossoverEnabled, isFalse);
      expect(eq.isDynamicEqEnabled, isFalse);
      expect(eq.isMultibandCompressorEnabled, isFalse);
      expect(eq.isDynamicBassEnabled, isFalse);
      expect(eq.isViperDdcEnabled, isFalse);
      expect(eq.isArbitraryEqEnabled, isFalse);
      expect(eq.isLiveProgEnabled, isFalse);
      expect(eq.isLimiterEnabled, isFalse);
      expect(eq.monoMix, isFalse);
      expect(eq.stereoBalance, 0.0);
    });

    test('highest-precision path: dither ON, resampler OFF, bypass not forced',
        () {
      final eq = EqualizerManager();
      expect(eq.isDitherEnabled, isTrue);
      expect(eq.ditherTargetBitDepth, 16);
      expect(eq.isSincResamplerEnabled, isFalse);
      expect(eq.isBitPerfectBypass, isFalse);
      expect(eq.dspPreference, 'native');
    });
  });
}
