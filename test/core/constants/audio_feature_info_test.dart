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

    test('conflict wording is chosen by key, not by the English text', () {
      // Rephrasing a registry entry used to silently stop translating it.
      const rephrased = AudioFeatureInfo(
        id: 'equalizer',
        title: 'EQ',
        subtitle: 'EQ subtitle',
        description: 'EQ description',
        conflictsWith: 'Exclusive bit-perfect output',
        conflictKey: 'bitPerfectBypass',
      );
      expect(rephrased.localized(l10n).conflictsWith,
          l10n.conflictWithBitPerfect);
      // Every registry entry with a conflict names a key, so none of them can
      // regress into untranslated English.
      for (final feature in _features) {
        if (feature.conflictsWith != null) {
          expect(feature.conflictKey, isNotNull,
              reason: '${feature.id} has conflictsWith without a conflictKey');
        }
      }
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
        // Android having no exclusive mixer for the DAC is exactly the case
        // the direct UAC2 sink exists for; hard-blocking it disabled the only
        // remaining bit-perfect path.
        AudioConflicts.bitPerfectBlockedReason(
            _device(reason: 'usb_not_supported')),
        isNull,
      );
      expect(
        AudioConflicts.bitPerfectBlockedReason(
            _device(reason: 'exclusive_requires_usb_dac')),
        l10n.conflictExclusiveRequiresUsbDac,
      );
      // No mixer attributes is attemptable (direct USB fallback); it must not
      // hard-disable the switch.
      expect(
        AudioConflicts.bitPerfectBlockedReason(
            _device(reason: 'no_supported_mixer_attributes')),
        isNull,
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
      // A USB DAC without platform mixer support is attemptable via the direct
      // sink, so strict is not hard-blocked there.
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(_device()),
        isNull,
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
      // Total gain at or below 0 dBFS cannot clip: only then is "high boost"
      // the right warning.
      expect(
        AudioConflicts.volumeBoostClippingWarning(0.7, -8.0),
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
      // The route-only fallback used to have no message at all, so the sheet
      // printed the raw reason code with no sentence explaining it.
      expect(
        AudioConflicts.bitPerfectReasonMessage(
            'mixer_attributes_unavailable_fallback_route_only'),
        contains('bit-perfect'),
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
      // Mixer-less USB DACs are attemptable (direct USB fallback).
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(_device()),
        isNull,
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
        AudioConflicts.volumeBoostClippingWarning(0.8, 2.0),
        contains('0 dBFS'),
      );
      expect(
        AudioConflicts.volumeBoostClippingWarning(0.7, -8.0),
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
        isNotNull,
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

    test('strictBitPerfectBlockedReason only hard-blocks BT and no device', () {
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(
            _device(isBluetooth: true)),
        isNotNull,
      );
      expect(AudioConflicts.strictBitPerfectBlockedReason(null), isNotNull);
      expect(AudioConflicts.strictBitPerfectBlockedReason(_device()), isNull);
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
          strictBitPerfect: false,
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBitPerfectActive: true),
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

    test('bitPerfectSourceBlockedReason accurately identifies lossy, radio, and 32-bit formats', () {
      // Radio blocked: explicit flag or radio:// scheme
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(isRadio: true),
        contains('Live radio and lossy streams'),
      );
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(path: 'radio://live-stream'),
        contains('Live radio and lossy streams'),
      );
      // A normal HTTP URL that merely contains "radio" in its path is NOT blocked
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(path: 'https://example.com/radio/track.flac', bitDepth: 16),
        isNull,
      );
      // Lossy files with 16-bit or unknown depth blocked
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(path: '/music/track.mp3', bitDepth: 16),
        contains('Live radio and lossy streams'),
      );
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(path: '/music/track.aac', bitDepth: 0),
        contains('Live radio and lossy streams'),
      );
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(path: '/music/stream.ogg', isLossy: true),
        contains('Live radio and lossy streams'),
      );
      // ALAC in .m4a container with codec='alac' is allowed
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(
          path: '/music/track.m4a',
          codec: 'alac',
          bitDepth: 24,
        ),
        isNull,
      );
      // 32-bit float audio rejected with dedicated 32-bit conversion code
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(path: '/music/track.flac', bitDepth: 32),
        contains('32-bit floating point audio requires lossy conversion'),
      );
      // MediaStore content:// URI with isLossy=false is NOT falsely flagged as lossy
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(
          path: 'content://media/external/audio/media/12345',
          isLossy: false,
          bitDepth: 24,
        ),
        isNull,
      );
      // Complete lossless extensions whitelist pass
      for (final ext in ['.flac', '.wav', '.wave', '.alac', '.aiff', '.aif', '.dsf', '.dff', '.wv', '.ape', '.tta', '.mka']) {
        expect(
          AudioConflicts.bitPerfectSourceBlockedReason(path: '/music/track$ext', bitDepth: 24),
          isNull,
          reason: 'Extension $ext should be recognized as lossless',
        );
      }
    });

    test('AudioConflicts.classifySourceCodec prefix, MIME normalization and ambiguous containers', () {
      // Prefix matching for pcm_ and dsd
      expect(AudioConflicts.classifySourceCodec(codec: 'pcm_s16be'), AudioSourceCodecState.lossless);
      expect(AudioConflicts.classifySourceCodec(codec: 'pcm_s24be'), AudioSourceCodecState.lossless);
      expect(AudioConflicts.classifySourceCodec(codec: 'pcm_f32le'), AudioSourceCodecState.lossless);
      expect(AudioConflicts.classifySourceCodec(codec: 'dsd_lsbf_planar'), AudioSourceCodecState.lossless);
      expect(AudioConflicts.classifySourceCodec(codec: 'dsd_msbf'), AudioSourceCodecState.lossless);

      // Companding PCM is lossy
      expect(AudioConflicts.classifySourceCodec(codec: 'pcm_alaw'), AudioSourceCodecState.lossy);
      expect(AudioConflicts.classifySourceCodec(codec: 'pcm_mulaw'), AudioSourceCodecState.lossy);

      // Explicit lossy codecs
      expect(AudioConflicts.classifySourceCodec(codec: 'mp3'), AudioSourceCodecState.lossy);
      expect(AudioConflicts.classifySourceCodec(codec: 'aac'), AudioSourceCodecState.lossy);
      expect(AudioConflicts.classifySourceCodec(codec: 'mp4a.40.2'), AudioSourceCodecState.lossy);
      expect(AudioConflicts.classifySourceCodec(codec: 'opus'), AudioSourceCodecState.lossy);
      expect(AudioConflicts.classifySourceCodec(codec: 'vorbis'), AudioSourceCodecState.lossy);

      // Explicit lossless codecs
      for (final c in ['flac', 'alac', 'wavpack', 'ape', 'tta', 'wav', 'aiff']) {
        expect(AudioConflicts.classifySourceCodec(codec: c), AudioSourceCodecState.lossless);
      }

      // MIME types
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/vnd.wave'), AudioSourceCodecState.lossless);
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/l16'), AudioSourceCodecState.lossless);
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/l24'), AudioSourceCodecState.lossless);
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/flac'), AudioSourceCodecState.lossless);

      // MIME normalization: trimming, case insensitivity, stripping parameters after semicolon
      expect(AudioConflicts.classifySourceCodec(mimeType: ' Audio/VND.WAVE ; rate=48000 '), AudioSourceCodecState.lossless);
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/mp4; codecs="mp4a.40.2"'), AudioSourceCodecState.lossy);

      // Section 1.1 codecs= extraction from MIME string without character truncation
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/ogg; codecs="opus"'), AudioSourceCodecState.lossy);
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/mp4; codecs=alac'), AudioSourceCodecState.lossless);
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/ogg; codecs=vorbis'), AudioSourceCodecState.lossy);
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/x-dsd; codecs=dsd_lsbf_planar'), AudioSourceCodecState.lossless);

      // Ambiguous containers without codec / MIME return unknown
      for (final ext in ['.m4a', '.mp4', '.ogg', '.oga', '.mka', '.webm']) {
        expect(AudioConflicts.classifySourceCodec(path: 'track$ext'), AudioSourceCodecState.unknown);
      }
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/mp4'), AudioSourceCodecState.unknown);
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/x-m4a'), AudioSourceCodecState.unknown);
      expect(AudioConflicts.classifySourceCodec(mimeType: 'audio/ogg'), AudioSourceCodecState.unknown);

      // bitPerfectSourceBlockedReason handles codecs and 32-bit correctly
      expect(AudioConflicts.bitPerfectSourceBlockedReason(codec: 'pcm_s16be', bitDepth: 16), isNull);
      expect(AudioConflicts.bitPerfectSourceBlockedReason(codec: 'pcm_s24be', bitDepth: 24), isNull);
      expect(
        AudioConflicts.bitPerfectSourceBlockedReason(codec: 'pcm_f32le', bitDepth: 32),
        contains('32-bit floating point audio requires lossy conversion'),
      );
      expect(AudioConflicts.bitPerfectSourceBlockedReason(codec: 'dsd_lsbf_planar'), isNull);
      expect(AudioConflicts.bitPerfectSourceBlockedReason(codec: 'dsd_msbf'), isNull);
      expect(AudioConflicts.bitPerfectSourceBlockedReason(codec: 'mp3'), contains('Live radio and lossy streams'));
      expect(AudioConflicts.bitPerfectSourceBlockedReason(codec: 'aac'), contains('Live radio and lossy streams'));
      expect(AudioConflicts.bitPerfectSourceBlockedReason(codec: 'mp4a.40.2'), contains('Live radio and lossy streams'));
      expect(AudioConflicts.bitPerfectSourceBlockedReason(codec: 'opus'), contains('Live radio and lossy streams'));
      expect(AudioConflicts.bitPerfectSourceBlockedReason(codec: 'vorbis'), contains('Live radio and lossy streams'));
      expect(AudioConflicts.bitPerfectSourceBlockedReason(codec: 'pcm_alaw'), contains('Live radio and lossy streams'));
      expect(AudioConflicts.bitPerfectSourceBlockedReason(codec: 'pcm_mulaw'), contains('Live radio and lossy streams'));

      // Ambiguous container without codec is NOT blocked by bitPerfectSourceBlockedReason
      expect(AudioConflicts.bitPerfectSourceBlockedReason(path: '/storage/music/track.m4a', bitDepth: 16), isNull);
      expect(AudioConflicts.bitPerfectSourceBlockedReason(path: '/storage/music/track.ogg', bitDepth: 16), isNull);
      expect(AudioConflicts.bitPerfectSourceBlockedReason(mimeType: 'audio/mp4', bitDepth: 16), isNull);
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
      expect(
          AudioConflicts.bitPerfectReasonMessage('uac3_unsupported'),
          contains('UAC3'));
      expect(
          AudioConflicts.bitPerfectReasonMessage('source_32bit_float_conversion_not_lossless'),
          contains('32-bit floating point audio requires lossy conversion'));
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

    test('speed and silence-skip obey the same armed bypass rule', () {
      const wired = AudioOutputInfo(
        deviceName: 'Wired',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
      );
      expect(
        AudioConflicts.speedBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: wired,
        ),
        isNotNull,
      );
      expect(
        AudioConflicts.speedBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: false,
          device: wired,
        ),
        isNull,
      );
      expect(
        AudioConflicts.speedBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: true,
          device: wired,
        ),
        isNull,
      );
      expect(
        AudioConflicts.silenceSkipBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: _device(isBluetooth: true),
        ),
        isNull,
      );
      expect(
        AudioConflicts.silenceSkipBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: wired,
        ),
        isNotNull,
      );
    });

    test('only BT or a missing USB DAC hard-locks the Bit-Perfect switch', () {
      for (final reason in const [
        'target_format_unavailable',
        'set_mixer_attributes_failed',
        'clear_mixer_attributes_failed',
        'unknown_error_boom',
        'channel_error',
        'requires_android_14_for_usb',
        'no_supported_mixer_attributes',
        'usb_not_supported',
        'reflection_method_not_found',
        'audio_mixer_class_not_found',
      ]) {
        expect(
          AudioConflicts.bitPerfectBlockedReason(_device(reason: reason)),
          isNull,
          reason: '$reason must stay attemptable (direct USB fallback)',
        );
      }
      for (final reason in const [
        'exclusive_requires_usb_dac',
      ]) {
        expect(
          AudioConflicts.bitPerfectBlockedReason(_device(reason: reason)),
          isNotNull,
          reason: '$reason means no usable USB path',
        );
      }
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

    test('volumeBoostClippingWarning boundary table (0 dBFS full scale)', () {
      expect(AudioConflicts.volumeBoostClippingWarning(1.0, 0.0), isNotNull);
      expect(AudioConflicts.volumeBoostClippingWarning(0.61, 0.0), isNotNull);
      // Anything above full scale is already clipping, however small.
      expect(AudioConflicts.volumeBoostClippingWarning(0.2, 4.0), isNotNull);
      expect(AudioConflicts.volumeBoostClippingWarning(0.0, 0.1), isNotNull);
      // At or below 0 dBFS nothing clips...
      expect(AudioConflicts.volumeBoostClippingWarning(0.0, 0.0), isNull);
      expect(AudioConflicts.volumeBoostClippingWarning(0.05, -0.5), isNull);
      // ...and below the high-boost threshold no warning is shown at all.
      expect(AudioConflicts.volumeBoostClippingWarning(0.06, -1.0), isNull);
      expect(
        AudioConflicts.volumeBoostClippingWarning(0.7, -8.0),
        isNot(contains('Clipping risk')),
      );
    });
  });
}
