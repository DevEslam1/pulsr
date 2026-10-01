// lib/features/player/presentation/widgets/player_volume_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../cubit/player_cubit.dart';

class PlayerVolumeBar extends StatefulWidget {
  final PlayerCubit cubit;
  final Color activeColor;

  const PlayerVolumeBar({
    super.key,
    required this.cubit,
    required this.activeColor,
  });

  @override
  State<PlayerVolumeBar> createState() => _PlayerVolumeBarState();
}

class _PlayerVolumeBarState extends State<PlayerVolumeBar> {
  double? _dragVolume;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final handler = context.watch<PulsrAudioHandler?>();
    final currentVolume = handler?.volume.clamp(0.0, 1.0) ?? 0.5;
    final effectiveVolume = _dragVolume ?? currentVolume;
    final isMuted = effectiveVolume <= 0.01;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxs,
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              isMuted
                  ? Icons.volume_off_rounded
                  : (effectiveVolume < 0.5
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded),
              size: 20,
              color: p.textSecondary,
            ),
            tooltip: isMuted ? 'Unmute' : 'Mute',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() => _dragVolume = null);
              widget.cubit.toggleMute();
            },
          ),
          Expanded(
            child: PulsrSlider(
              min: 0.0,
              max: 1.0,
              value: effectiveVolume,
              activeColor: widget.activeColor,
              onChangeStart: (v) => setState(() => _dragVolume = v),
              onChanged: (v) {
                setState(() => _dragVolume = v);
                widget.cubit.setVolume(v);
              },
              onChangeEnd: (v) {
                setState(() => _dragVolume = null);
                widget.cubit.setVolume(v);
              },
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.volume_up_rounded,
              size: 20,
              color: p.textSecondary,
            ),
            tooltip: 'Max volume',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() => _dragVolume = null);
              widget.cubit.setVolume(1.0);
            },
          ),
        ],
      ),
    );
  }
}
