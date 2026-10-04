// Coverage-focused tests for AudioFeatureInfo localization and AudioConflicts.
// Existing coverage lives in test/audio_conflicts_extended_test.dart; this file
// fills the l10n switch branches, fallback strings and every guard outcome.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_feature_info.dart';
import 'package:pulsr/core/utils/l10n_holder.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/l10n/generated/app_localizations_en.dart';

const _features = <AudioFeatureInfo>[
  AudioFeatureRegistry.bitPerfect,
  AudioFeatureRegistry.bypassDsp,
  AudioFeatureRegistry.followTrackSampleRate,
  AudioFeatureRegistry.strictBitPerfect,
  AudioFeatureRegistry.equalizer,
  AudioFeatureRegistry.bassBoost,
  AudioFeatureRegistry.crossfeed,
  AudioFeatureRegistry.limiter,
  AudioFeatureRegistry.reverb,
  AudioFeatureRegistry.panner,
  AudioFeatureRegistry.resampler,
  AudioFeatureRegistry.virtualizer,
  AudioFeatureRegistry.spatializer,
  AudioFeatureRegistry.dynamics,
  AudioFeatureRegistry.roomCorrection,
  AudioFeatureRegistry.dsdNative,
  AudioFeatureRegistry.mqa,
  AudioFeatureRegistry.gapless,
  AudioFeatureRegistry.crossfade,
  AudioFeatureRegistry.replayGain,
  AudioFeatureRegistry.oem,
  AudioFeatureRegistry.volumeBoost,
  AudioFeatureRegistry.saturation,
  AudioFeatureRegistry.stereoWidth,
  AudioFeatureRegistry.loudnessContour,
  AudioFeatureRegistry.subCrossover,
  AudioFeatureRegistry.dynamicEq,
  AudioFeatureRegistry.multibandCompressor,
  AudioFeatureRegistry.dynamicBass,
  AudioFeatureRegistry.viperDdc,
  AudioFeatureRegistry.arbitraryEq,
  AudioFeatureRegistry.liveProg,
];

AudioOutputInfo _device({
  bool isBluetooth = false,
  bool isBitPerfectActive = false,
  bool isBitPerfectSupported = false,
  String? reason,
}) =>
    AudioOutputInfo(
      deviceName: isBluetooth ? 'BT Headset' : 'USB DAC',
      isUsbDac: !isBluetooth,
      sampleRate: 48000,
      bitDepth: 24,
      isBitPerfectActive: isBitPerfectActive,
      isBitPerfectSupported: isBitPerfectSupported,
      bitPerfectFailureReason: reason,
      isBluetooth: isBluetooth,
    );

void main() {
  group('AudioFeatureInfo.localized', () {
    late AppLocalizationsEn l10n;

    setUp(() {
      l10n = AppLocalizationsEn();
      L10nHolder.current = l10n;
    });

    tearDown(() {
      L10nHolder.current = null;
    });

    test('every registry entry has a unique id and localizes all fields', () {
      final ids = _features.map((f) => f.id).toSet();
      expect(ids.length, _features.length);

      for (final feature in _features) {
        final localized = feature.localized(l10n);
        expect(localized.id, feature.id);
        expect(localized.title, isNotEmpty, reason: '${feature.id}.title');
        expect(localized.subtitle, isNotEmpty,
            reason: '${feature.id}.subtitle');
        expect(
          localized.description,
          isNotEmpty,
          reason: '${feature.id}.description',
        );
        expect(localized.whyDisabledReason, feature.whyDisabledReason);
      }
    });

    test('localized titles match the generated l10n getters', () {
      expect(AudioFeatureRegistry.bitPerfect.localized(l10n).title,
          l10n.featureInfoBitPerfectTitle);
      expect(AudioFeatureRegistry.bypassDsp.localized(l10n).title,
          l10n.featureInfoBypassDspTitle);
      expect(AudioFeatureRegistry.equalizer.localized(l10n).title,
          l10n.featureInfoEqualizerTitle);
      expect(AudioFeatureRegistry.liveProg.localized(l10n).title,
          l10n.featureInfoLiveProgTitle);
      expect(AudioFeatureRegistry.reverb.localized(l10n).subtitle,
          l10n.featureInfoReverbSubtitle);
      expect(AudioFeatureRegistry.dsdNative.localized(l10n).description,
          l10n.featureInfoDsdNativeDescription);
    });

    test('conflictsWith literals map onto generated l10n strings', () {
      expect(
        AudioFeatureRegistry.bitPerfect.localized(l10n).conflictsWith,
        l10n.conflictWithAllDspBypassDsp,
      );
      expect(
        AudioFeatureRegistry.strictBitPerfect.localized(l10n).conflictsWith,
        l10n.conflictWithEqReplayGainEffectsCrossfade,
      );
      expect(
        AudioFeatureRegistry.equalizer.localized(l10n).conflictsWith,
        l10n.conflictWithBitPerfect,
      );
      expect(
        AudioFeatureRegistry.resampler.localized(l10n).conflictsWith,
        l10n.conflictWithResampler,
      );
      expect(
        AudioFeatureRegistry.virtualizer.localized(l10n).conflictsWith,
        l10n.conflictWithVirtualizer,
      );
      expect(
        AudioFeatureRegistry.gapless.localized(l10n).conflictsWith,
        l10n.conflictWithCrossfade,
      );
      expect(
        AudioFeatureRegistry.crossfade.localized(l10n).conflictsWith,
        l10n.conflictWithGapless,
      );
    });

    test('unknown id and conflict literal fall back to the raw values', () {
      const info = AudioFeatureInfo(
        id: 'madeUpFeature',
        title: 'Raw Title',
        subtitle: 'Raw Subtitle',
        description: 'Raw Description',
        conflictsWith: 'Some custom conflict',
        whyDisabledReason: 'Because',
      );

      final localized = info.localized(l10n);
      expect(localized.title, 'Raw Title');
      expect(localized.subtitle, 'Raw Subtitle');
      expect(localized.description, 'Raw Description');
      expect(localized.conflictsWith, 'Some custom conflict');
      expect(localized.whyDisabledReason, 'Because');
    });
  });

  group('AudioConflicts localized messages', () {
    late AppLocalizationsEn l10n;

    setUp(() {
      l10n = AppLocalizationsEn();
      L10nHolder.current = l10n;
    });

    tearDown(() {
      L10nHolder.current = null;
    });

    test('dspBlockedByBitPerfect resolves each l10n branch', () {
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: false,
          device: null,
          aaudioEnabled: true,
        ),
        l10n.conflictAaudioDirect,
      );
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: false,
          device: null,
          dsdDopActive: true,
        ),
        l10n.conflictDsdDop,
      );
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBitPerfectActive: true),
        ),
        l10n.conflictDspBitPerfectBypass,
      );
    });

    test('bitPerfectBlockedReason resolves l10n branches', () {
      expect(
        AudioConflicts.bitPerfectBlockedReason(_device(isBluetooth: true)),
        l10n.conflictBtBitPerfectUnsupported,
      );
      expect(
        AudioConflicts.bitPerfectBlockedReason(
            _device(reason: 'usb_not_supported')),
        l10n.conflictNoMixerAttributes,
      );
      expect(
        AudioConflicts.bitPerfectBlockedReason(
            _device(reason: 'exclusive_requires_usb_dac')),
        l10n.conflictExclusiveRequiresUsbDac,
      );
      expect(
        AudioConflicts.bitPerfectBlockedReason(
            _device(reason: 'no_supported_mixer_attributes')),
        l10n.conflictNoMixerAttributes,
      );
    });

    test('generic guard messages resolve l10n branches', () {
      expect(
        AudioConflicts.gaplessBlockedByCrossfade(2.5),
        l10n.conflictGaplessNeedsZeroCrossfade('2.5'),
      );
      expect(
        AudioConflicts.crossfadeBlockedByGapless(true),
        l10n.conflictCrossfadeNeedsGaplessOff,
      );
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(null),
        l10n.conflictNoDeviceDetected,
      );
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(_device()),
        l10n.conflictNoExclusiveMixer,
      );
      expect(
        AudioConflicts.strictBitPerfectActiveReason(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBitPerfectActive: true),
        ),
        l10n.conflictStrictBitPerfectActive,
      );
      expect(
        AudioConflicts.crossfadeBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: false,
          device: null,
          aaudioEnabled: true,
        ),
        l10n.conflictAaudioDirectCrossfade,
      );
      expect(
        AudioConflicts.crossfadeBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBitPerfectActive: true),
        ),
        l10n.conflictCrossfadeBitPerfectBypass,
      );
      expect(
        AudioConflicts.dspBlockedByAaudioDirect(aaudioEnabled: true),
        l10n.conflictAaudioDirect,
      );
      expect(
        AudioConflicts.oemDoubleProcessingWarning(
            hasOemAudio: true, anyDspEnabled: true),
        l10n.conflictOemDoubleProcessing,
      );
      expect(
        AudioConflicts.volumeBoostClippingWarning(0.8, 2.0),
        l10n.conflictVolumeBoostClipping('2.0', '8.0', '10.0'),
      );
      expect(
        AudioConflicts.volumeBoostClippingWarning(0.7, -1.0),
        l10n.conflictHighBoostDistortion,
      );
    });
  });

  group('AudioConflicts English fallbacks (no l10n holder)', () {
    setUp(() => L10nHolder.current = null);

    test('dspBlockedByBitPerfect fallback strings', () {
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: false,
          device: null,
          aaudioEnabled: true,
        ),
        contains('AAudio Direct'),
      );
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: false,
          device: null,
          dsdDopActive: true,
        ),
        contains('DoP'),
      );
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBitPerfectActive: true),
        ),
        contains('Bit-Perfect bypass'),
      );
    });

    test('bitPerfectBlockedReason and reason codes fall back to English', () {
      expect(
        AudioConflicts.bitPerfectBlockedReason(_device(isBluetooth: true)),
        contains('Bluetooth'),
      );
      expect(
        AudioConflicts.bitPerfectReasonMessage('requires_android_14_for_usb'),
        contains('Android 14'),
      );
      expect(
        AudioConflicts.bitPerfectReasonMessage('exclusive_requires_usb_dac'),
        contains('USB DAC'),
      );
      expect(
        AudioConflicts.bitPerfectReasonMessage('bluetooth_transcoded'),
        contains('Bluetooth'),
      );
      expect(
        AudioConflicts.bitPerfectReasonMessage('no_supported_mixer_attributes'),
        contains('mixer configuration'),
      );
    });

    test('generic guard fallbacks', () {
      expect(
        AudioConflicts.gaplessBlockedByCrossfade(1.25),
        contains('1.3 s'),
      );
      expect(
        AudioConflicts.crossfadeBlockedByGapless(true),
        contains('Gapless is ON'),
      );
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(null),
        contains('no output device'),
      );
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(_device()),
        contains('exclusive bit-perfect'),
      );
      expect(
        AudioConflicts.strictBitPerfectActiveReason(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBitPerfectActive: true),
        ),
        contains('Strict bit-perfect is ON'),
      );
      expect(
        AudioConflicts.crossfadeBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: false,
          device: null,
          aaudioEnabled: true,
        ),
        contains('AAudio Direct'),
      );
      expect(
        AudioConflicts.crossfadeBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBitPerfectActive: true),
        ),
        contains('crossfade overlaps'),
      );
      expect(
        AudioConflicts.dspBlockedByAaudioDirect(aaudioEnabled: true),
        contains('AAudio Direct'),
      );
      expect(
        AudioConflicts.oemDoubleProcessingWarning(
            hasOemAudio: true, anyDspEnabled: true),
        contains('double-processing'),
      );
      expect(
        AudioConflicts.volumeBoostClippingWarning(0.8, 2.0),
        contains('Clipping risk'),
      );
      expect(
        AudioConflicts.volumeBoostClippingWarning(0.7, -1.0),
        contains('High boost'),
      );
    });
  });

  group('AudioConflicts decision table', () {
    setUp(() => L10nHolder.current = null);

    test('dspBlockedByBitPerfect returns null when no block applies', () {
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: true,
          device: _device(isBitPerfectActive: true),
        ),
        isNull,
      );
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: false,
          device: _device(isBitPerfectActive: true),
        ),
        isNull,
      );
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBluetooth: true),
        ),
        isNull,
      );
      expect(
        AudioConflicts.dspBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(),
        ),
        isNull,
      );
    });

    test('replayGainBlockedByBitPerfect mirrors dspBlockedByBitPerfect', () {
      expect(
        AudioConflicts.replayGainBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBitPerfectActive: true),
        ),
        isNotNull,
      );
      expect(
        AudioConflicts.replayGainBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: false,
          device: null,
          dsdDopActive: true,
        ),
        isNotNull,
      );
      expect(
        AudioConflicts.replayGainBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: false,
          device: null,
        ),
        isNull,
      );
    });

    test('bitPerfectBlockedReason handles null and unknown reasons', () {
      expect(AudioConflicts.bitPerfectBlockedReason(null), isNull);
      expect(
        AudioConflicts.bitPerfectBlockedReason(_device(reason: 'mystery')),
        isNull,
      );
      expect(AudioConflicts.bitPerfectReasonMessage(null), isNull);
      expect(AudioConflicts.bitPerfectReasonMessage('mystery'), isNull);
    });

    test('strictBitPerfectBlockedReason distinguishes all three states', () {
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(
            _device(isBluetooth: true)),
        isNotNull,
      );
      expect(AudioConflicts.strictBitPerfectBlockedReason(null), isNotNull);
      expect(
          AudioConflicts.strictBitPerfectBlockedReason(_device()), isNotNull);
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(
            _device(isBitPerfectActive: true, isBitPerfectSupported: true)),
        isNull,
      );
    });

    test('strictBitPerfectActiveReason only fires for active non-BT paths', () {
      expect(
        AudioConflicts.strictBitPerfectActiveReason(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: true,
          device: _device(isBitPerfectActive: true),
        ),
        isNull,
      );
      expect(
        AudioConflicts.strictBitPerfectActiveReason(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: false,
          device: _device(isBitPerfectActive: true),
        ),
        isNull,
      );
      expect(
        AudioConflicts.strictBitPerfectActiveReason(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBluetooth: true),
        ),
        isNull,
      );
      expect(
        AudioConflicts.strictBitPerfectActiveReason(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: null,
        ),
        isNotNull,
      );
    });

    test('reason code mapping table', () {
      expect(AudioConflicts.bitPerfectReasonMessage('requires_android_14'),
          isNotNull);
      expect(
          AudioConflicts.bitPerfectReasonMessage('target_format_unavailable'),
          contains('sample rate'));
      expect(
          AudioConflicts.bitPerfectReasonMessage('set_mixer_attributes_failed'),
          contains('refused'));
      expect(
          AudioConflicts.bitPerfectReasonMessage('reflection_method_not_found'),
          contains('not available'));
      expect(
          AudioConflicts.bitPerfectReasonMessage('audio_mixer_class_not_found'),
          contains('not available'));
    });

    test('crossfade/gapless boundary values', () {
      expect(AudioConflicts.gaplessBlockedByCrossfade(0.0), isNull);
      expect(AudioConflicts.gaplessBlockedByCrossfade(0.01), isNull);
      expect(AudioConflicts.gaplessBlockedByCrossfade(0.011), isNotNull);
      expect(AudioConflicts.crossfadeBlockedByGapless(false), isNull);
      expect(AudioConflicts.crossfadeBlockedByGapless(true), isNotNull);
    });

    test('crossfadeBlockedByBitPerfect returns null when nothing blocks', () {
      expect(
        AudioConflicts.crossfadeBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: true,
          device: _device(isBitPerfectActive: true),
        ),
        isNull,
      );
      expect(
        AudioConflicts.crossfadeBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: false,
          device: _device(isBitPerfectActive: true),
        ),
        isNull,
      );
      expect(
        AudioConflicts.crossfadeBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBluetooth: true),
        ),
        isNull,
      );
    });

    test('dspBlockedByAaudioDirect only fires when AAudio is on', () {
      expect(AudioConflicts.dspBlockedByAaudioDirect(aaudioEnabled: false),
          isNull);
      expect(AudioConflicts.dspBlockedByAaudioDirect(aaudioEnabled: true),
          isNotNull);
    });

    test('oemDoubleProcessingWarning decision table', () {
      expect(
        AudioConflicts.oemDoubleProcessingWarning(
            hasOemAudio: false, anyDspEnabled: true),
        isNull,
      );
      expect(
        AudioConflicts.oemDoubleProcessingWarning(
            hasOemAudio: true, anyDspEnabled: false),
        isNull,
      );
      expect(
        AudioConflicts.oemDoubleProcessingWarning(
            hasOemAudio: false, anyDspEnabled: false),
        isNull,
      );
      expect(
        AudioConflicts.oemDoubleProcessingWarning(
            hasOemAudio: true, anyDspEnabled: true),
        isNotNull,
      );
    });

    test('volumeBoostClippingWarning boundary table', () {
      expect(AudioConflicts.volumeBoostClippingWarning(1.0, 0.0), isNotNull);
      expect(AudioConflicts.volumeBoostClippingWarning(0.61, 0.0), isNotNull);
      expect(AudioConflicts.volumeBoostClippingWarning(0.6, 0.0), isNull);
      expect(AudioConflicts.volumeBoostClippingWarning(0.2, 4.0), isNull);
      expect(AudioConflicts.volumeBoostClippingWarning(0.0, 6.1), isNotNull);
    });
  });
}
