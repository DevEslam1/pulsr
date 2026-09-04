// lib/features/player/presentation/themes/cassette_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import 'player_theme.dart';

class CassettePlayerTheme extends StatefulWidget {
  final PlayerThemeProps props;

  const CassettePlayerTheme({super.key, required this.props});

  @override
  State<CassettePlayerTheme> createState() => _CassettePlayerThemeState();
}

class _CassettePlayerThemeState extends State<CassettePlayerTheme>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spoolController;

  @override
  void initState() {
    super.initState();
    _spoolController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.props.state.isPlaying) {
      _spoolController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CassettePlayerTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.isPlaying && !_spoolController.isAnimating) {
      _spoolController.repeat();
    } else if (!widget.props.state.isPlaying && _spoolController.isAnimating) {
      _spoolController.stop();
    }
  }

  @override
  void dispose() {
    _spoolController.dispose();
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
        final isTwoPane = context.isTwoPane || constraints.maxWidth >= 680;

        final cassetteBody = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: isTwoPane ? 240 : 300,
              maxWidth: isTwoPane ? 360 : 420,
            ),
            child: AspectRatio(
              aspectRatio: 1.5,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2028),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF323646), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Cassette Label Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: p.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'SIDE A • TYPE II (CrO2)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            'PULSR TAPE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: p.primary,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Cassette Center Window with Spinning Spools
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1116),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Left Spool
                            _buildSpool(),
                            // Center Tape Window
                            Container(
                              width: 70,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Center(
                                child: Container(
                                  height: 12,
                                  width: 50,
                                  color: const Color(
                                      0xFF5A3825), // Brown tape strip
                                ),
                              ),
                            ),
                            // Right Spool
                            _buildSpool(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Track Title on Cassette Body
                    Text(
                      song?.title ?? 'Tape Loaded',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
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
                  child: cassetteBody,
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
              Expanded(child: cassetteBody),
              const SizedBox(height: 16),
              controlsColumn,
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpool() {
    return RotationTransition(
      turns: _spoolController,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade400, width: 3),
        ),
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Color(0xFF0F1116),
              shape: BoxShape.circle,
            ),
            child: CustomPaint(painter: _SpoolTeethPainter()),
          ),
        ),
      ),
    );
  }
}

class _SpoolTeethPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0;

    for (int i = 0; i < 6; i++) {
      final angle = i * (math.pi / 3);
      final p1 = Offset(
        center.dx + 4 * math.cos(angle),
        center.dy + 4 * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + 10 * math.cos(angle),
        center.dy + 10 * math.sin(angle),
      );
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
