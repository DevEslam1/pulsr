part of '../circle_player_theme.dart';

/// Luxury Rotary Dial Audio Stage (Bang & Olufsen / Dieter Rams aesthetic):
/// Features a precision knurled aluminum bezel, circumferential neon progress arc,
/// orbiting luminous position bead, and central rotating disc with metallic spindle.
class _CircleArtwork extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final AnimationController rotationController;
  final bool isTablet;
  final bool isLandscape;

  const _CircleArtwork({
    required this.props,
    required this.activeColor,
    required this.rotationController,
    required this.isTablet,
    required this.isLandscape,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final currentSong = state.currentSong;
    final durationMs = state.duration.inMilliseconds;
    final positionMs = state.position.inMilliseconds;
    final progress =
        durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDimension = isLandscape ? 310.0 : (isTablet ? 550.0 : 420.0);
        final dialSize = math.min(
          math.min(constraints.maxWidth, constraints.maxHeight) * 0.95,
          maxDimension,
        );

        return Center(
          child: SizedBox(
            width: dialSize,
            height: dialSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Ambient Dynamic Glow Halo
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withValues(
                          alpha: state.isPlaying ? 0.32 : 0.16,
                        ),
                        blurRadius: state.isPlaying ? 46 : 28,
                        spreadRadius: state.isPlaying ? 6 : 2,
                      ),
                      BoxShadow(
                        color: AppColors.scrimAt(0.6),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: SizedBox(width: dialSize, height: dialSize),
                ),

                // 2. Precision Knurled Outer Bezel & Circumference Track
                CustomPaint(
                  size: Size(dialSize, dialSize),
                  painter: _RotaryBezelPainter(
                    palette: p,
                    activeColor: activeColor,
                  ),
                ),

                // 3. Glowing Circumferential Progress Arc & Orbiting Bead
                CustomPaint(
                  size: Size(dialSize, dialSize),
                  painter: _CircularProgressArcPainter(
                    activeColor: activeColor,
                    progress: progress,
                    isPlaying: state.isPlaying,
                  ),
                ),

                // 4. Center Rotating Album Core
                RotationTransition(
                  turns: rotationController,
                  child: Container(
                    width: dialSize * 0.68,
                    height: dialSize * 0.68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF101218),
                      border: Border.all(
                        color: AppColors.specularAt(0.28),
                        width: 2.5,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black87,
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Micro-Grooves on inner disc
                        CustomPaint(
                          size: Size(dialSize * 0.68, dialSize * 0.68),
                          painter: _InnerGroovesPainter(),
                        ),

                        // Album Artwork Label
                        Container(
                          width: dialSize * 0.50,
                          height: dialSize * 0.50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white24,
                              width: 1.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: currentSong != null
                              ? CachedArtwork(
                                  id: currentSong.id,
                                  albumId: currentSong.albumId,
                                  remoteUrl: currentSong.remoteArtworkUrl ??
                                      currentSong.artworkUri,
                                  type: ArtworkType.AUDIO,
                                  size: dialSize * 0.50,
                                  borderRadius: 999,
                                  highQuality: true,
                                )
                              : Icon(
                                  Icons.album_rounded,
                                  size: dialSize * 0.22,
                                  color: Colors.white54,
                                ),
                        ),

                        // Luxury Brushed Spindle Cap
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.grey.shade300,
                                Colors.grey.shade700,
                                const Color(0xFF161820),
                              ],
                              stops: const [0.0, 0.6, 1.0],
                            ),
                            border: Border.all(
                              color: Colors.white38,
                              width: 1.2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: activeColor,
                              ),
                            ),
                          ),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Precision Knurled Bezel Painter
// ---------------------------------------------------------------------------
class _RotaryBezelPainter extends CustomPainter {
  final PulsrPalette palette;
  final Color activeColor;

  _RotaryBezelPainter({
    required this.palette,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;

    // 1. Dark titanium outer housing
    final housingPaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFF222632),
          Color(0xFF161820),
          Color(0xFF0E1015),
        ],
        stops: const [0.82, 0.94, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));
    canvas.drawCircle(center, outerRadius, housingPaint);

    // 2. Beveled border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0.25),
          Colors.white.withValues(alpha: 0.05),
          Colors.white.withValues(alpha: 0.25),
          Colors.white.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.45, 0.70, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));
    canvas.drawCircle(center, outerRadius - 1.0, borderPaint);

    // 3. Precision Swiss/Rotary knurling ticks around the perimeter
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final majorTickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    const int totalTicks = 72;
    for (int i = 0; i < totalTicks; i++) {
      final angle = (i / totalTicks) * 2 * math.pi;
      final isMajor = i % 18 == 0; // 12, 3, 6, 9 o'clock
      final isSemiMajor = i % 6 == 0;

      final innerR = isMajor
          ? outerRadius - 14
          : (isSemiMajor ? outerRadius - 10 : outerRadius - 7);
      final outerR = outerRadius - 3.5;

      final p1 = Offset(
        center.dx + innerR * math.cos(angle),
        center.dy + innerR * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + outerR * math.cos(angle),
        center.dy + outerR * math.sin(angle),
      );

      canvas.drawLine(p1, p2, isMajor ? majorTickPaint : tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RotaryBezelPainter oldDelegate) =>
      oldDelegate.activeColor != activeColor;
}

// ---------------------------------------------------------------------------
// Circumferential Neon Progress Arc & Orbiting Bead
// ---------------------------------------------------------------------------
class _CircularProgressArcPainter extends CustomPainter {
  final Color activeColor;
  final double progress;
  final bool isPlaying;

  _CircularProgressArcPainter({
    required this.activeColor,
    required this.progress,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final arcRadius = (size.width / 2) - 18.0;

    // 1. Recessed background guide track
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawCircle(center, arcRadius, trackPaint);

    if (progress <= 0.001) return;

    // 2. Active glowing arc (starts at 12 o'clock, sweeps clockwise)
    const startAngle = -math.pi / 2;
    final sweepAngle = (progress * 2 * math.pi).clamp(0.01, 2 * math.pi);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round
      ..color = activeColor.withValues(alpha: isPlaying ? 0.35 : 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: arcRadius),
      startAngle,
      sweepAngle,
      false,
      glowPaint,
    );

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..color = activeColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: arcRadius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );

    // 3. Orbiting illuminated bead at the tip
    final beadAngle = startAngle + sweepAngle;
    final beadPos = Offset(
      center.dx + arcRadius * math.cos(beadAngle),
      center.dy + arcRadius * math.sin(beadAngle),
    );

    final beadGlowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.75)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(beadPos, 6.0, beadGlowPaint);

    final beadPaint = Paint()..color = Colors.white;
    canvas.drawCircle(beadPos, 3.5, beadPaint);
  }

  @override
  bool shouldRepaint(covariant _CircularProgressArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.isPlaying != isPlaying;
}

// ---------------------------------------------------------------------------
// Inner Disc Micro-Grooves Painter
// ---------------------------------------------------------------------------
class _InnerGroovesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.04);

    for (double r = radius * 0.40; r < radius - 4; r += 5.5) {
      canvas.drawCircle(center, r, groovePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
