import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import 'player_theme.dart';

class VinylPlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const VinylPlayerTheme({super.key, required this.props});

  @override
  State<VinylPlayerTheme> createState() => _VinylPlayerThemeState();
}

class _VinylPlayerThemeState extends State<VinylPlayerTheme>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (widget.props.state.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant VinylPlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.isPlaying && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!widget.props.state.isPlaying &&
        _rotationController.isAnimating) {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.props.state;
    final cubit = widget.props.cubit;
    final p = context.palette;
    final song = state.currentSong;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTwoPane =
            context.isLandscape && (context.isTwoPane || constraints.maxWidth >= 680);

        final turntableDisc = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: isTwoPane ? 280 : 340,
              maxWidth: isTwoPane ? 280 : 340,
            ),
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Vinyl Grooves Outer Disc
                  RotationTransition(
                    turns: _rotationController,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0F0F12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 30,
                            spreadRadius: 4,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        border: Border.all(
                          color: const Color(0xFF242630),
                          width: 3,
                        ),
                      ),
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _VinylGroovesPainter(),
                        child: Center(
                          // Center Album Art Label
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white24, width: 2),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (song != null)
                                  CachedArtwork(
                                    id: song.id,
                                    type: ArtworkType.AUDIO,
                                    size: 110,
                                    borderRadius: 999,
                                    fallbackIcon: Icons.music_note_rounded,
                                  ),
                                // Center Spindle Hole
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF14172B),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Tonearm
                  Positioned(
                    top: 4,
                    right: 12,
                    child: Transform.rotate(
                      angle: state.isPlaying ? 0.35 : 0.05,
                      alignment: Alignment.topRight,
                      child: Container(
                        width: 80,
                        height: 130,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.grey.shade400,
                              Colors.grey.shade800
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        final controlsColumn = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Track Title & Artist
            Text(
              song?.title ?? 'No Track Playing',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              song?.artist ?? 'Unknown Artist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: p.textSecondary,
              ),
            ),
            const SizedBox(height: 8),

            // Audio Quality & DAC Badge
            if (song != null)
              AudioQualityBadge(
                  song: song, activeColor: widget.props.activeColor),
            const SizedBox(height: 12),

            // Seek Bar
            PlayerSeekBar(
              duration: state.duration,
              activeColor: widget.props.activeColor,
              songId: song?.id,
              filePath: song?.path,
              onSeek: (pos) => cubit.seek(pos),
            ),
            const SizedBox(height: 14),

            // Playback Controls
            PlayerControls(
              isPlaying: state.isPlaying,
              isShuffle: state.isShuffle,
              repeatMode: state.repeatMode,
              primaryColor: widget.props.activeColor,
              mainButtonSize: isTwoPane ? 56 : 64,
              onPlayPause: () => cubit.togglePlayPause(),
              onNext: () => cubit.next(),
              onPrevious: () => cubit.previous(),
              onToggleShuffle: () => cubit.toggleShuffle(),
              onToggleRepeat: () => cubit.toggleRepeat(),
            ),
            const SizedBox(height: 16),
          ],
        );

        if (isTwoPane) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: turntableDisc,
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 6,
                  child: SingleChildScrollView(
                    child: controlsColumn,
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Expanded(child: turntableDisc),
              const SizedBox(height: 16),
              controlsColumn,
            ],
          ),
        );
      },
    );
  }
}

class _VinylGroovesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final groovePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw concentric groove rings
    for (double r = 60; r < radius - 8; r += 12) {
      canvas.drawCircle(center, r, groovePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
