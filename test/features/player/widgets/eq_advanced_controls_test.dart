// test/features/player/widgets/eq_advanced_controls_test.dart
//
// The advanced EQ controls (`_EqAdvancedControls`) live in a `part of
// equalizer_sheet.dart` extension on the private `_EqualizerSheetState`, and are
// only reachable from the Android-only branch of `EqualizerSheet.build`
// (guarded at `equalizer_sheet.dart:222` by `if (!Platform.isAndroid)`). That
// gate reads `dart:io`'s `Platform` directly and there is no runtime override,
// so the extension body cannot be mounted on the host.
//
// This file instead maximizes host-reachable coverage of the same library by
// exercising the top-level rebuild gate `dspSheetRebuildGate` (and, through it,
// the private `_eqPresetRebuildEquals`) across every DspSlice field. Without
// per-field inputs the `||` chain short-circuits early and most operand lines
// stay uncovered.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/models/quran_mode_profile.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';

const PlayerState _base = PlayerState();

PlayerState _diff(DspSlice Function(DspSlice dsp) f) =>
    _base.copyWith(dsp: f(_base.dsp));

SongsTableData _song(int id) => SongsTableData(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      album: 'Album',
      path: '/path/$id',
      durationMs: 1000,
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );

void main() {
  group('dspSheetRebuildGate identity / non-dsp branches', () {
    test('identical states short-circuit to false (line 63)', () {
      expect(dspSheetRebuildGate(_base, _base), isFalse);
    });

    test('a non-identical copy sharing the same dsp slice returns false',
        () {
      final copy = _base.copyWith();
      expect(dspSheetRebuildGate(_base, copy), isFalse);
    });

    test('errorMessage change forces a rebuild (line 64)', () {
      const withError =
          PlayerState(playback: PlaybackSlice(errorMessage: 'boom'));
      expect(dspSheetRebuildGate(_base, withError), isTrue);
    });

    test('currentSong id change forces a rebuild (line 65)', () {
      final withSong =
          _base.copyWith(playback: PlaybackSlice(currentSong: _song(7)));
      expect(dspSheetRebuildGate(_base, withSong), isTrue);
    });

    test('equal but non-identical eqPreset does not rebuild (lines 143-148)',
        () {
      final equalButNew = _diff(
        (d) => d.copyWith(
          eqPreset: EqPreset(
            name: d.eqPreset.name,
            gains: List<double>.from(d.eqPreset.gains),
          ),
        ),
      );
      expect(dspSheetRebuildGate(_base, equalButNew), isFalse);
    });
  });

  group('dspSheetRebuildGate covers every DspSlice field', () {
    final cases = <String, PlayerState Function()>{
      // eqPreset sub-fields (exercises _eqPresetRebuildEquals).
      'eqPreset.name': () => _diff((d) => d.copyWith(
            eqPreset: EqPreset(name: 'Rock', gains: d.eqPreset.gains),
          )),
      'eqPreset.bassBoost': () => _diff(
            (d) => d.copyWith(eqPreset: d.eqPreset.copyWith(bassBoost: 0.5)),
          ),
      'eqPreset.customFrequencies': () => _diff(
            (d) => d.copyWith(
              eqPreset: d.eqPreset.copyWith(customFrequencies: const [100.0]),
            ),
          ),
      'eqPreset.qFactors': () => _diff(
            (d) => d.copyWith(
              eqPreset: d.eqPreset.copyWith(qFactors: const [1.0]),
            ),
          ),
      'eqPreset.bandsMap': () => _diff(
            (d) => d.copyWith(
              eqPreset: d.eqPreset.copyWith(bandsMap: const {1: [2.0]}),
            ),
          ),
      // Booleans (default false -> true) and inverted defaults.
      'isEqEnabled': () => _diff((d) => d.copyWith(isEqEnabled: true)),
      'isVirtualizerEnabled': () =>
          _diff((d) => d.copyWith(isVirtualizerEnabled: true)),
      'isVirtualizerSupported': () =>
          _diff((d) => d.copyWith(isVirtualizerSupported: true)),
      'isDynamicsEnabled': () =>
          _diff((d) => d.copyWith(isDynamicsEnabled: true)),
      'isDynamicsSupported': () =>
          _diff((d) => d.copyWith(isDynamicsSupported: true)),
      'isSpatializerSupported': () =>
          _diff((d) => d.copyWith(isSpatializerSupported: true)),
      'isSpatializerEnabled': () =>
          _diff((d) => d.copyWith(isSpatializerEnabled: true)),
      'isVolumeBoostSupported': () =>
          _diff((d) => d.copyWith(isVolumeBoostSupported: true)),
      'isBassBoostSupported': () =>
          _diff((d) => d.copyWith(isBassBoostSupported: true)),
      'isCrossfeedEnabled': () =>
          _diff((d) => d.copyWith(isCrossfeedEnabled: true)),
      'isLimiterEnabled': () =>
          _diff((d) => d.copyWith(isLimiterEnabled: true)),
      'isReverbEnabled': () => _diff((d) => d.copyWith(isReverbEnabled: true)),
      'monoMix': () => _diff((d) => d.copyWith(monoMix: true)),
      'isSincResamplerEnabled': () =>
          _diff((d) => d.copyWith(isSincResamplerEnabled: false)),
      'isDitherEnabled': () => _diff((d) => d.copyWith(isDitherEnabled: true)),
      'isSaturationEnabled': () =>
          _diff((d) => d.copyWith(isSaturationEnabled: true)),
      'saturationMultiband': () =>
          _diff((d) => d.copyWith(saturationMultiband: true)),
      'isStereoWidthEnabled': () =>
          _diff((d) => d.copyWith(isStereoWidthEnabled: true)),
      'isLoudnessContourEnabled': () =>
          _diff((d) => d.copyWith(isLoudnessContourEnabled: true)),
      'isSubCrossoverEnabled': () =>
          _diff((d) => d.copyWith(isSubCrossoverEnabled: true)),
      'subCrossoverBassMono': () =>
          _diff((d) => d.copyWith(subCrossoverBassMono: true)),
      'subCrossoverAntiPop': () =>
          _diff((d) => d.copyWith(subCrossoverAntiPop: false)),
      'stereoWidthMultiband': () =>
          _diff((d) => d.copyWith(stereoWidthMultiband: true)),
      'isDynamicEqEnabled': () =>
          _diff((d) => d.copyWith(isDynamicEqEnabled: true)),
      'isViperDdcEnabled': () =>
          _diff((d) => d.copyWith(isViperDdcEnabled: true)),
      'isArbitraryEqEnabled': () =>
          _diff((d) => d.copyWith(isArbitraryEqEnabled: true)),
      'isLiveProgEnabled': () =>
          _diff((d) => d.copyWith(isLiveProgEnabled: true)),
      'isDynamicBassEnabled': () =>
          _diff((d) => d.copyWith(isDynamicBassEnabled: true)),
      'hasOemAudio': () => _diff((d) => d.copyWith(hasOemAudio: true)),
      'isQuranModeEnabled': () =>
          _diff((d) => d.copyWith(isQuranModeEnabled: true)),
      // Doubles / ints.
      'virtualizerStrength': () =>
          _diff((d) => d.copyWith(virtualizerStrength: 1.0)),
      'volumeBoost': () => _diff((d) => d.copyWith(volumeBoost: 1.0)),
      'crossfeedDelayUs': () => _diff((d) => d.copyWith(crossfeedDelayUs: 360)),
      'crossfeedFeedDb': () => _diff((d) => d.copyWith(crossfeedFeedDb: -8)),
      'crossfeedMode': () => _diff((d) => d.copyWith(crossfeedMode: 1)),
      'limiterThresholdDb': () =>
          _diff((d) => d.copyWith(limiterThresholdDb: -0.3)),
      'limiterReleaseMs': () => _diff((d) => d.copyWith(limiterReleaseMs: 60)),
      'reverbPreset': () => _diff((d) => d.copyWith(reverbPreset: 1)),
      'reverbWetDry': () => _diff((d) => d.copyWith(reverbWetDry: 0.3)),
      'stereoBalance': () => _diff((d) => d.copyWith(stereoBalance: 1.0)),
      'ditherTargetBitDepth': () =>
          _diff((d) => d.copyWith(ditherTargetBitDepth: 24)),
      'saturationDrive': () => _diff((d) => d.copyWith(saturationDrive: 0.4)),
      'saturationMix': () => _diff((d) => d.copyWith(saturationMix: 0.6)),
      'saturationTilt': () => _diff((d) => d.copyWith(saturationTilt: 0.4)),
      'stereoWidth': () => _diff((d) => d.copyWith(stereoWidth: 1.5)),
      'loudnessContourIntensity': () =>
          _diff((d) => d.copyWith(loudnessContourIntensity: 1.0)),
      'subCrossoverCornerHz': () =>
          _diff((d) => d.copyWith(subCrossoverCornerHz: 90)),
      'subCrossoverSlopeDbPerOct': () =>
          _diff((d) => d.copyWith(subCrossoverSlopeDbPerOct: 25)),
      'subCrossoverGain': () => _diff((d) => d.copyWith(subCrossoverGain: 0.9)),
      'stereoWidthLow': () => _diff((d) => d.copyWith(stereoWidthLow: 1.5)),
      'stereoWidthMid': () => _diff((d) => d.copyWith(stereoWidthMid: 1.5)),
      'stereoWidthHigh': () => _diff((d) => d.copyWith(stereoWidthHigh: 1.5)),
      'stereoWidthLowCrossoverHz': () =>
          _diff((d) => d.copyWith(stereoWidthLowCrossoverHz: 170)),
      'stereoWidthHighCrossoverHz': () =>
          _diff((d) => d.copyWith(stereoWidthHighCrossoverHz: 2600)),
      'multibandCompressorF0': () =>
          _diff((d) => d.copyWith(multibandCompressorF0: 170)),
      'multibandCompressorF1': () =>
          _diff((d) => d.copyWith(multibandCompressorF1: 1100)),
      'multibandCompressorF2': () =>
          _diff((d) => d.copyWith(multibandCompressorF2: 5100)),
      'dynamicBassStrength': () =>
          _diff((d) => d.copyWith(dynamicBassStrength: 1.5)),
      'dynamicBassPreset': () => _diff((d) => d.copyWith(dynamicBassPreset: 1)),
      // Strings.
      'viperDdcProfileName': () =>
          _diff((d) => d.copyWith(viperDdcProfileName: 'p')),
      'arbitraryEqString': () =>
          _diff((d) => d.copyWith(arbitraryEqString: 'a')),
      'liveProgCode': () => _diff((d) => d.copyWith(liveProgCode: 'c')),
      'liveProgStatus': () => _diff((d) => d.copyWith(liveProgStatus: 's')),
      // Enums / objects / lists.
      'dynamicsPreset': () => _diff(
            (d) => d.copyWith(dynamicsPreset: DynamicsPreset.studioPunch),
          ),
      'quranReciterStyle': () => _diff(
            (d) => d.copyWith(quranReciterStyle: QuranReciterStyle.mujawwad),
          ),
      'selectedHeadphoneProfile': () => _diff(
            (d) => d.copyWith(
              selectedHeadphoneProfile: const HeadphoneProfile(
                id: 'p1',
                name: 'P1',
                brand: 'B',
                model: 'M',
                category: 'C',
                gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
              ),
            ),
          ),
      'dynamicEqBands': () => _diff(
            (d) => d.copyWith(
              dynamicEqBands: const [DynamicEqBandConfig()],
            ),
          ),
      'detectedOemEngines': () =>
          _diff((d) => d.copyWith(detectedOemEngines: const ['oem'])),
    };

    test('every field difference triggers exactly one rebuild', () {
      for (final entry in cases.entries) {
        expect(
          dspSheetRebuildGate(_base, entry.value()),
          isTrue,
          reason: 'gate must rebuild when ${entry.key} changes',
        );
      }
    });

    test('all fields equal -> no rebuild', () {
      // A field-for-field clone (fresh list instances) must not rebuild.
      final clone = _diff(
        (d) => d.copyWith(
          eqPreset: EqPreset(
            name: d.eqPreset.name,
            gains: List<double>.from(d.eqPreset.gains),
            customFrequencies: d.eqPreset.customFrequencies,
            qFactors: d.eqPreset.qFactors,
            bandsMap: d.eqPreset.bandsMap,
          ),
          dynamicEqBands: const [],
          detectedOemEngines: const [],
        ),
      );
      expect(dspSheetRebuildGate(_base, clone), isFalse);
    });
  });
}
