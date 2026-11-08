// lib/features/settings/presentation/widgets/bit_perfect_conflict_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../data/db/tables.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';

class _Conflict {
  const _Conflict(this.label, this.disable);
  final String label;
  final Future<void> Function() disable;
}

/// Entry point for every Bit-Perfect ON toggle.
///
/// Bit-Perfect must hand the DAC an unaltered bitstream, so any active EQ,
/// reverb, crossfade, ReplayGain... would be bypassed or would break it. When
/// such features are on, a popup lists them and offers to turn them off before
/// enabling. Turning Bit-Perfect OFF never needs a prompt.
///
/// Stage names are taken from [AudioFeatureRegistry] so the list speaks the
/// same translated vocabulary as the info popups, instead of a second,
/// English-only one.
///
/// Returns true when the platform round-trip was actually attempted (false
/// when the user cancelled the conflict prompt), so callers outside the
/// Settings screen can surface the cubit's `errorMessage` on refusal.
Future<bool> requestBitPerfectOutput(BuildContext context, bool enable) async {
  final settings = context.read<SettingsCubit>();
  if (!enable) {
    await settings.setBitPerfectOutput(false);
    return true;
  }
  // If the device can't do bit-perfect anyway, let the cubit show the reason
  // instead of asking the user to disable things for nothing.
  if (AudioConflicts.bitPerfectBlockedReason(
        settings.state.currentOutputDevice,
      ) !=
      null) {
    await settings.setBitPerfectOutput(true);
    return true;
  }

  PlayerCubit? player;
  try {
    player = context.read<PlayerCubit>();
  } catch (_) {}

  final currentSong = player?.state.currentSong;
  final sourceBlock = AudioConflicts.bitPerfectSourceBlockedReason(
    path: currentSong?.path,
    bitDepth: currentSong?.bitDepth ?? 0,
    isRadio: currentSong?.source == SongSource.radio,
    codec: currentSong?.codec,
  );
  if (sourceBlock != null) {
    settings.safeEmit(settings.state.copyWith(errorMessage: sourceBlock));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(sourceBlock),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    return false;
  }

  final l = context.l10n;
  final conflicts = <_Conflict>[];
  final s = settings.state;
  if (s.crossfadeSeconds > 0.01) {
    conflicts.add(_Conflict(
      AudioFeatureRegistry.crossfade.localized(l).title,
      () => settings.setCrossfade(0.0),
    ));
  }
  if (s.replayGainMode != ReplayGainMode.off) {
    conflicts.add(_Conflict(
      AudioFeatureRegistry.replayGain.localized(l).title,
      () => settings.setReplayGainMode(ReplayGainMode.off),
    ));
  }
  final p = player?.state;
  if (player != null && p != null) {
    final pl = player;
    // An AutoEQ headphone profile and the bass boost are both fitted into the
    // same biquad cascade, so one EQ entry covers all three.
    if (p.isEqEnabled || p.selectedHeadphoneProfile != null) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.equalizer.localized(l).title,
        () async {
          if (p.selectedHeadphoneProfile != null) {
            await pl.applyHeadphoneProfile(null);
          }
          await pl.setEqualizerEnabled(false);
        },
      ));
    }
    if (p.isLimiterEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.limiter.localized(l).title,
        () => pl.setLookaheadLimiter(false),
      ));
    }
    if (p.isCrossfeedEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.crossfeed.localized(l).title,
        () => pl.setCrossfeed(false),
      ));
    }
    if (p.isReverbEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.reverb.localized(l).title,
        () => pl.setReverb(false),
      ));
    }
    if (p.isSaturationEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.saturation.localized(l).title,
        () => pl.setSaturation(false),
      ));
    }
    if (p.stereoBalance != 0.0 || p.monoMix) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.panner.localized(l).title,
        () async {
          await pl.setStereoBalance(0.0);
          await pl.setMonoMix(false);
        },
      ));
    }
    if (p.isStereoWidthEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.stereoWidth.localized(l).title,
        () => pl.setStereoWidth(false),
      ));
    }
    if (p.isLoudnessContourEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.loudnessContour.localized(l).title,
        () => pl.setLoudnessContour(false),
      ));
    }
    if (p.isSubCrossoverEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.subCrossover.localized(l).title,
        () => pl.setSubCrossover(false),
      ));
    }
    if (p.isDynamicEqEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.dynamicEq.localized(l).title,
        () => pl.setDynamicEq(false),
      ));
    }
    if (p.isDynamicsEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.dynamics.localized(l).title,
        () => pl.setDynamicsPreset(p.dynamicsPreset, enabled: false),
      ));
    }
    if (p.isDynamicBassEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.dynamicBass.localized(l).title,
        () => pl.setDynamicBass(false),
      ));
    }
    if (p.isViperDdcEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.viperDdc.localized(l).title,
        () => pl.setViperDdcEnabled(false),
      ));
    }
    if (p.isArbitraryEqEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.arbitraryEq.localized(l).title,
        () => pl.setArbitraryEqEnabled(false),
      ));
    }
    if (p.isLiveProgEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.liveProg.localized(l).title,
        () => pl.setLiveProgEnabled(false),
      ));
    }
    if (p.isVirtualizerEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.virtualizer.localized(l).title,
        () => pl.setVirtualizerEnabled(false),
      ));
    }
    if (p.isSpatializerEnabled) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.spatializer.localized(l).title,
        () => pl.setSpatializerEnabled(false),
      ));
    }
    if (p.volumeBoost > 0.01) {
      conflicts.add(_Conflict(
        AudioFeatureRegistry.volumeBoost.localized(l).title,
        () => pl.setVolumeBoost(0.0),
      ));
    }
    // The multiband compressor is owned by the effect manager rather than by a
    // per-stage cubit toggle. The master effects switch turns it off, and it
    // also covers any stage added to the engine later, so the list can never
    // claim completeness while something is still processing the signal.
    // By checking isDspEffectsActive, the 'Master DSP' entry never appears when
    // no stage is active.
    if (p.isDspEffectsActive) {
      conflicts.add(_Conflict(
        l.dspStatMasterDsp,
        () => pl.setDspEffectsEnabled(false),
      ));
    }
  }

  if (conflicts.isEmpty) {
    await settings.setBitPerfectOutput(true);
    return true;
  }

  final confirmed = await PulsrDialogHelper.showPulsrDialog<bool>(
    context,
    icon: const Icon(Icons.headphones_rounded),
    title: Text(l.bitPerfectConflictTitle),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.bitPerfectConflictBody),
        const SizedBox(height: 12),
        for (final c in conflicts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const Icon(Icons.block_rounded, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(c.label)),
              ],
            ),
          ),
      ],
    ),
    // These buttons are constructed outside the dialog route, so they have to
    // pop through a context built inside it. Reaching for the caller's context
    // (or naming the root navigator) popped whichever route sat on top of the
    // caller's navigator instead of the dialog.
    actions: [
      Builder(
        builder: (dialogContext) => TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l.cancel),
        ),
      ),
      Builder(
        builder: (dialogContext) => FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l.bitPerfectDisableAndEnable),
        ),
      ),
    ],
  );
  if (confirmed != true) return false;

  // Enable FIRST: the native route may still refuse exclusive output (e.g. the
  // DAC dropped, another app grabbed it, target format unavailable). Disabling
  // the user's DSP stages before that round-trip would leave them with a fully
  // bypassed chain and no bit-perfect — so only tear the conflicts down once
  // Bit-Perfect is actually on. The native DSP bypass already mutes them in
  // the meantime; these calls just make the saved preference match.
  await settings.setBitPerfectOutput(true);
  if (!settings.state.bitPerfectOutput) return true;

  for (final c in conflicts) {
    try {
      await c.disable();
    } catch (_) {
      // Keep going: Bit-Perfect's own DSP bypass still covers what we missed.
    }
  }
  return true;
}
