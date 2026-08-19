// lib/features/player/presentation/widgets/player_seek_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/waveform_generator.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';
import 'waveform_seek_bar.dart';

class PlayerSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final Color activeColor;
  final int? songId;
  final String? filePath;

  const PlayerSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.activeColor = AppColors.primary,
    this.songId,
    this.filePath,
  });

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final settingsState = context.watch<SettingsCubit>().state;
    final currentSong = context.watch<PlayerCubit>().state.currentSong;

    final effectiveSongId = widget.songId ?? currentSong?.id;
    final effectiveFilePath = widget.filePath ?? currentSong?.path;

    // Check if Waveform Seek Bar is enabled in settings and song ID is available
    if (settingsState.waveformSeekBarEnabled && effectiveSongId != null) {
      return FutureBuilder<List<double>>(
        future: WaveformGenerator().generateWaveform(
          songId: effectiveSongId,
          filePath: effectiveFilePath,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            return WaveformSeekBar(
              position: widget.position,
              duration: widget.duration,
              onSeek: widget.onSeek,
              samples: snapshot.data!,
              activeColor: widget.activeColor,
            );
          }
          // Smooth fallback to standard seek bar while loading waveform
          return _buildStandardSeekBar(context);
        },
      );
    }

    return _buildStandardSeekBar(context);
  }

  Widget _buildStandardSeekBar(BuildContext context) {
    final double maxDuration = widget.duration.inMilliseconds.toDouble();
    final double currentPos = widget.position.inMilliseconds.toDouble();
    final double effectiveValue = (_dragValue ?? currentPos).clamp(0.0, maxDuration > 0 ? maxDuration : 1.0);
    final double progressPercent = maxDuration > 0 ? (effectiveValue / maxDuration).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Custom Gesture-driven scrubber track
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null && maxDuration > 0) {
                final localX = details.localPosition.dx.clamp(0.0, box.size.width);
                final ratio = localX / box.size.width;
                setState(() {
                  _dragValue = ratio * maxDuration;
                });
              }
            },
            onHorizontalDragUpdate: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null && maxDuration > 0) {
                final localX = details.localPosition.dx.clamp(0.0, box.size.width);
                final ratio = localX / box.size.width;
                setState(() {
                  _dragValue = ratio * maxDuration;
                });
              }
            },
            onHorizontalDragEnd: (details) {
              if (_dragValue != null) {
                widget.onSeek(Duration(milliseconds: _dragValue!.round()));
                setState(() {
                  _dragValue = null;
                });
              }
            },
            onTapDown: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null && maxDuration > 0) {
                final localX = details.localPosition.dx.clamp(0.0, box.size.width);
                final ratio = localX / box.size.width;
                final seekMs = ratio * maxDuration;
                widget.onSeek(Duration(milliseconds: seekMs.round()));
              }
            },
            child: SizedBox(
              height: 28,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Inactive Track
                  Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Active Progress Track
                  FractionallySizedBox(
                    widthFactor: progressPercent,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            widget.activeColor.withValues(alpha: 0.8),
                            widget.activeColor,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: widget.activeColor.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Scrubber Thumb
                  Positioned(
                    left: (progressPercent * (MediaQuery.of(context).size.width - 48) - 7).clamp(0.0, MediaQuery.of(context).size.width - 48),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Timestamps
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                Formatters.formatDuration(
                  _dragValue != null ? Duration(milliseconds: _dragValue!.round()) : widget.position,
                ),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                Formatters.formatDuration(widget.duration),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
