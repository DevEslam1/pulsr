// lib/features/player/presentation/widgets/player_seek_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/services/waveform_service.dart';
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
    this.activeColor = Colors.white,
    this.songId,
    this.filePath,
  });

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  double? _dragValue;
  int? _lastSongId;
  Future<List<double>>? _cachedWaveformFuture;

  @override
  Widget build(BuildContext context) {
    final songId = context.select<PlayerCubit, int?>((c) => c.state.currentSong?.id);
    final songPath = context.select<PlayerCubit, String?>((c) => c.state.currentSong?.path);
    final waveformEnabled = context.select<SettingsCubit, bool>((c) => c.state.waveformSeekBarEnabled);

    final effectiveSongId = widget.songId ?? songId;
    final effectiveFilePath = widget.filePath ?? songPath;

    // Check if Waveform Seek Bar is enabled in settings and song ID is available
    if (waveformEnabled && effectiveSongId != null) {
      if (_lastSongId != effectiveSongId || _cachedWaveformFuture == null) {
        _lastSongId = effectiveSongId;
        _cachedWaveformFuture = WaveformService.instance.getWaveform(
          songId: effectiveSongId,
          filePath: effectiveFilePath,
        );
      }

      return FutureBuilder<List<double>>(
        future: _cachedWaveformFuture,
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

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            // Custom Gesture-driven scrubber track
            LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    if (trackWidth > 0 && maxDuration > 0) {
                      final ratio = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                      setState(() {
                        _dragValue = ratio * maxDuration;
                      });
                    }
                  },
                  onHorizontalDragUpdate: (details) {
                    if (trackWidth > 0 && maxDuration > 0) {
                      final ratio = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
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
                    if (trackWidth > 0 && maxDuration > 0) {
                      final ratio = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
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
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.18)
                                : context.palette.hairline.withValues(alpha: 0.9),
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
                          left: (progressPercent * trackWidth - 7).clamp(0.0, (trackWidth - 14).clamp(0.0, trackWidth)),
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
                );
              },
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
                  style: TextStyle(
                    color: context.palette.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  Formatters.formatDuration(widget.duration),
                  style: TextStyle(
                    color: context.palette.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
