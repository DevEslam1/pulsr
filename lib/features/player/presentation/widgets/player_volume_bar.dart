// lib/features/player/presentation/widgets/player_volume_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_slider.dart';
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
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final currentVolume = () {
      try {
        return context.select<PlayerCubit, double>((c) => c.state.volume).clamp(0.0, 1.0);
      } catch (_) {
        return widget.cubit.state.volume.clamp(0.0, 1.0);
      }
    }();
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
            tooltip: isMuted ? context.l10n.unmute : context.l10n.mute,
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() => _dragVolume = null);
              widget.cubit.toggleMute();
            },
          ),
          Expanded(
            child: AnimatedContainer(
              duration: context.motionMs(150),
              curve: Curves.easeOutCubic,
              height: _isDragging ? 36.0 : 30.0,
              alignment: Alignment.center,
              child: PulsrSlider(
                min: 0.0,
                max: 1.0,
                value: effectiveVolume,
                semanticLabel: context.l10n.volume,
                semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                activeColor: widget.activeColor,
                onChangeStart: (v) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _isDragging = true;
                    _dragVolume = v;
                  });
                },
                onChanged: (v) {
                  final prev = _dragVolume ?? currentVolume;
                  if ((prev > 0.02 && v <= 0.02) || (prev < 0.98 && v >= 0.98)) {
                    HapticFeedback.selectionClick();
                  }
                  setState(() => _dragVolume = v);
                  widget.cubit.setVolume(v);
                },
                onChangeEnd: (v) {
                  setState(() {
                    _isDragging = false;
                    _dragVolume = null;
                  });
                  widget.cubit.setVolume(v);
                },
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.volume_up_rounded,
              size: 20,
              color: p.textSecondary,
            ),
            tooltip: context.l10n.maxVolume,
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
