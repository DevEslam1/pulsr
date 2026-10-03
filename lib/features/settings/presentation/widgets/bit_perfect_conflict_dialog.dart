// lib/features/settings/presentation/widgets/bit_perfect_conflict_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/utils/l10n_extensions.dart';
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
Future<void> requestBitPerfectOutput(BuildContext context, bool enable) async {
  final settings = context.read<SettingsCubit>();
  if (!enable) {
    await settings.setBitPerfectOutput(false);
    return;
  }
  // If the device can't do bit-perfect anyway, let the cubit show the reason
  // instead of asking the user to disable things for nothing.
  if (AudioConflicts.bitPerfectBlockedReason(
        settings.state.currentOutputDevice,
      ) !=
      null) {
    await settings.setBitPerfectOutput(true);
    return;
  }

  PlayerCubit? player;
  try {
    player = context.read<PlayerCubit>();
  } catch (_) {}

  final conflicts = <_Conflict>[];
  final s = settings.state;
  if (s.crossfadeSeconds > 0.01) {
    conflicts.add(_Conflict('Crossfade', () => settings.setCrossfade(0.0)));
  }
  if (s.replayGainMode != ReplayGainMode.off) {
    conflicts.add(_Conflict(
      'ReplayGain',
      () => settings.setReplayGainMode(ReplayGainMode.off),
    ));
  }
  final p = player?.state;
  if (player != null && p != null) {
    final pl = player;
    if (p.isEqEnabled) {
      conflicts
          .add(_Conflict('Equalizer', () => pl.setEqualizerEnabled(false)));
    }
    if (p.isReverbEnabled) {
      conflicts.add(_Conflict('Reverb', () => pl.setReverb(false)));
    }
    if (p.isSaturationEnabled) {
      conflicts.add(_Conflict('Saturation', () => pl.setSaturation(false)));
    }
    if (p.isDynamicsEnabled) {
      conflicts.add(_Conflict(
        'Dynamics',
        () => pl.setDynamicsPreset(p.dynamicsPreset, enabled: false),
      ));
    }
    if (p.isCrossfeedEnabled) {
      conflicts.add(_Conflict('Crossfeed', () => pl.setCrossfeed(false)));
    }
    if (p.isStereoWidthEnabled) {
      conflicts.add(_Conflict('Stereo width', () => pl.setStereoWidth(false)));
    }
    if (p.isLoudnessContourEnabled) {
      conflicts.add(
          _Conflict('Loudness contour', () => pl.setLoudnessContour(false)));
    }
    if (p.isVirtualizerEnabled) {
      conflicts
          .add(_Conflict('Virtualizer', () => pl.setVirtualizerEnabled(false)));
    }
    if (p.isSpatializerEnabled) {
      conflicts.add(
          _Conflict('Spatial audio', () => pl.setSpatializerEnabled(false)));
    }
  }

  if (conflicts.isEmpty) {
    await settings.setBitPerfectOutput(true);
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.bitPerfectConflictTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.bitPerfectConflictBody),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(context.l10n.bitPerfectDisableAndEnable),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  for (final c in conflicts) {
    try {
      await c.disable();
    } catch (_) {
      // Keep going: Bit-Perfect's own DSP bypass still covers what we missed.
    }
  }
  await settings.setBitPerfectOutput(true);
}
