// test/features/player/cubit/phase_3_architecture_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/features/player/cubit/controllers/dsp_effect_applier.dart';
import 'package:pulsr/features/player/cubit/controllers/dsp_slice_descriptors.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';

void main() {
  group('Phase 3 Architecture — DspSlice Table-Driven Descriptors & Rollback Policy', () {
    test('dspSliceFields contains complete descriptors for all DSP effect fields', () {
      expect(dspSliceFields, isNotEmpty);
      expect(dspSliceFields.length, greaterThanOrEqualTo(25));

      final names = dspSliceFields.map((f) => f.name).toSet();
      expect(names.length, equals(dspSliceFields.length),
          reason: 'Every descriptor must have a unique name');

      // Core DSP fields verified
      expect(names, containsAll([
        'isEqEnabled',
        'eqPreset',
        'isVirtualizerEnabled',
        'virtualizerStrength',
        'isDynamicsEnabled',
        'dynamicsPreset',
        'selectedHeadphoneProfile',
        'volumeBoost',
        'effectiveVolumeBoost',
        'effectiveBassBoost',
        'isReverbEnabled',
        'reverbPreset',
        'isLimiterEnabled',
        'isSaturationEnabled',
        'isCrossfeedEnabled',
        'isStereoWidthEnabled',
      ]));
    });

    test('Property test: DspRollbackPolicy.merge reverts exactly the attempted fields without clobbering concurrent current values', () {
      const previous = DspSlice();

      // For every descriptor in dspSliceFields:
      for (final descriptor in dspSliceFields) {
        // Set a sentinel on current state to represent a concurrent mutation
        final bool isVirtualizer = descriptor.name == 'virtualizerStrength';
        final DspSlice current = isVirtualizer
            ? const DspSlice().copyWith(preampDb: -3.5)
            : const DspSlice().copyWith(virtualizerStrength: 0.95);

        // Build an attempted state by changing only this descriptor away from previous
        DspSlice attempted;
        switch (descriptor.name) {
          case 'isEqEnabled':
            attempted = previous.copyWith(isEqEnabled: !previous.isEqEnabled);
            break;
          case 'eqPreset':
            attempted = previous.copyWith(
              eqPreset: const EqPreset(name: 'TestPreset', gains: [1, 2, 3, 4, 5]),
            );
            break;
          case 'isVirtualizerEnabled':
            attempted = previous.copyWith(isVirtualizerEnabled: !previous.isVirtualizerEnabled);
            break;
          case 'virtualizerStrength':
            attempted = previous.copyWith(virtualizerStrength: 0.65);
            break;
          case 'volumeBoost':
            attempted = previous.copyWith(volumeBoost: 6.0);
            break;
          case 'effectiveVolumeBoost':
            attempted = previous.copyWith(effectiveVolumeBoost: 4.5);
            break;
          case 'isReverbEnabled':
            attempted = previous.copyWith(isReverbEnabled: !previous.isReverbEnabled);
            break;
          case 'isLimiterEnabled':
            attempted = previous.copyWith(isLimiterEnabled: !previous.isLimiterEnabled);
            break;
          case 'isSaturationEnabled':
            attempted = previous.copyWith(isSaturationEnabled: !previous.isSaturationEnabled);
            break;
          case 'isCrossfeedEnabled':
            attempted = previous.copyWith(isCrossfeedEnabled: !previous.isCrossfeedEnabled);
            break;
          case 'isStereoWidthEnabled':
            attempted = previous.copyWith(isStereoWidthEnabled: !previous.isStereoWidthEnabled);
            break;
          default:
            // For any other descriptor, skip
            continue;
        }

        // Verify that attempted differs from previous
        expect(descriptor.valuesEqual(previous, attempted), isFalse,
            reason: '${descriptor.name} must differ in attempted state');

        // Roll back the attempted operation
        final merged = DspRollbackPolicy.merge(current, previous, attempted);

        // The field modified by attempted must be reverted to previous
        expect(
          descriptor.valuesEqual(merged, previous),
          isTrue,
          reason: 'Field "${descriptor.name}" should revert to previous value in merged state',
        );

        // The sentinel field present on current must NOT be clobbered
        if (!isVirtualizer) {
          expect(merged.virtualizerStrength, equals(0.95),
              reason: 'Concurrent current field virtualizerStrength must be preserved');
        } else {
          expect(merged.preampDb, equals(-3.5),
              reason: 'Concurrent current field preampDb must be preserved');
        }
      }
    });

    test('dspSheetRebuildGate ignores playback position ticks and triggers on DSP changes', () {
      const baseState = PlayerState(
        playback: PlaybackSlice(
          position: Duration(seconds: 10),
          duration: Duration(minutes: 3),
          isPlaying: true,
        ),
      );

      // Position change only -> must NOT rebuild
      final tickedState = baseState.copyWith(
        playback: baseState.playback.copyWith(position: const Duration(seconds: 11)),
      );
      expect(dspSheetRebuildGate(baseState, tickedState), isFalse);

      // Duration change -> must NOT rebuild
      final durationState = baseState.copyWith(
        playback: baseState.playback.copyWith(duration: const Duration(minutes: 4)),
      );
      expect(dspSheetRebuildGate(baseState, durationState), isFalse);

      // DSP effect toggle -> MUST rebuild
      final dspChangedState = baseState.copyWith(
        dsp: baseState.dsp.copyWith(isEqEnabled: !baseState.dsp.isEqEnabled),
      );
      expect(dspSheetRebuildGate(baseState, dspChangedState), isTrue);

      // Headroom clamping change -> MUST rebuild
      final headroomState = baseState.copyWith(
        dsp: baseState.dsp.copyWith(effectiveVolumeBoost: 2.5),
      );
      expect(dspSheetRebuildGate(baseState, headroomState), isTrue);
    });

    test('AudioOutputInfo type flags accurately identify USB, Bluetooth, Headphones, and Speakers', () {
      const usbDac = AudioOutputInfo(
        deviceName: 'FiiO KA13',
        isUsbDac: true,
        activeDeviceType: 'usb',
        sampleRate: 48000,
        bitDepth: 24,
        isBitPerfectActive: true,
      );
      expect(usbDac.isUsb, isTrue);
      expect(usbDac.isBt, isFalse);
      expect(usbDac.isHeadphones, isFalse);
      expect(usbDac.isSpeaker, isFalse);

      const btDevice = AudioOutputInfo(
        deviceName: 'Sony WH-1000XM5',
        isUsbDac: false,
        activeDeviceType: 'bluetooth',
        isBluetooth: true,
        sampleRate: 48000,
        bitDepth: 24,
        isBitPerfectActive: false,
      );
      expect(btDevice.isUsb, isFalse);
      expect(btDevice.isBt, isTrue);
      expect(btDevice.isHeadphones, isFalse);
      expect(btDevice.isSpeaker, isFalse);

      const wiredHeadphones = AudioOutputInfo(
        deviceName: '3.5mm Headset',
        isUsbDac: false,
        activeDeviceType: 'wired_headset',
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
      );
      expect(wiredHeadphones.isUsb, isFalse);
      expect(wiredHeadphones.isBt, isFalse);
      expect(wiredHeadphones.isHeadphones, isTrue);
      expect(wiredHeadphones.isSpeaker, isFalse);

      const builtinSpeaker = AudioOutputInfo(
        deviceName: 'Phone Speaker',
        isUsbDac: false,
        activeDeviceType: 'speaker',
        sampleRate: 48000,
        bitDepth: 16,
        isBitPerfectActive: false,
      );
      expect(builtinSpeaker.isUsb, isFalse);
      expect(builtinSpeaker.isBt, isFalse);
      expect(builtinSpeaker.isHeadphones, isFalse);
      expect(builtinSpeaker.isSpeaker, isTrue);
    });
  });
}
