part of '../waveform_player_theme.dart';

// ---------------------------------------------------------------------------
// Waveform Hero Stage: Concentric Sonic Pulse + Floating Art + Neon Waves
// ---------------------------------------------------------------------------
class _WaveformHeroStage extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;
  final bool isPlaying;
  final bool isLandscape;
  final bool isTablet;
  final AnimationController waveController;
  final int? audioSessionId;

  const _WaveformHeroStage({
    super.key,
    required this.song,
    required this.activeColor,
    required this.isPlaying,
    required this.isLandscape,
    required this.isTablet,
    required this.waveController,
    this.audioSessionId,
  });

  @override
  Widget build(BuildContext context) {
    final song = this.song;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth - (isTablet ? 40.0 : 16.0);
        final availableH = constraints.maxHeight - (isTablet ? 32.0 : 20.0);
        final maxDimension = math.min(availableW, availableH);

        final double rawSize = maxDimension;
        final double maxAllowed = isTablet ? 560.0 : 420.0;
        final double artSize = isLandscape
            ? (constraints.maxHeight * 0.82).clamp(160.0, 320.0)
            : (rawSize <= 0 ? 0.0 : math.min(rawSize, maxAllowed));

        final double waveBaselineY =
            (constraints.maxHeight / 2) + (artSize * 0.28);

        return Stack(
          alignment: Alignment.center,
          children: [
            // 0. Live FFT Visualizer Waveform Layer
            Positioned.fill(
              child: Opacity(
                opacity: isPlaying ? 0.65 : 0.25,
                child: AudioVisualizer(
                  style: VisualizerStyle.wave,
                  color: activeColor,
                  isPlaying: isPlaying,
                  audioSessionId: audioSessionId,
                  trackId: song?.id,
                  trackPath: song?.path,
                ),
              ),
            ),

            // 1. Concentric Sonic Pulse Rings expanding from center
            Positioned.fill(
              child: AnimatedBuilder(
                animation: waveController,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: _SonicRipplesPainter(
                        color: activeColor,
                        progress: waveController.value,
                        isPlaying: isPlaying,
                        baseRadius: artSize * 0.52,
                      ),
                    ),
                  );
                },
              ),
            ),

            // 2. Full-Width Glowing Fluid Soundwave Spectrum (Spanning Across Stage)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: waveController,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: _FluidAudioWavesPainter(
                        color: activeColor,
                        progress: waveController.value,
                        isPlaying: isPlaying,
                        baselineY: waveBaselineY,
                      ),
                    ),
                  );
                },
              ),
            ),

            // 3. Center Floating Artwork Squircle with Neon Shadow and Border
            Positioned(
              child: Hero(
                tag: 'now_playing_art_full',
                child: Container(
                  width: artSize,
                  height: artSize,
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.circular(
                        resolveCustomRadius(context, AppRadii.r28)),
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withValues(
                            alpha: isPlaying ? 0.42 : 0.22),
                        blurRadius: isPlaying ? 48 : 28,
                        spreadRadius: isPlaying ? 4 : 1,
                        offset: const Offset(0, 12),
                      ),
                      BoxShadow(
                        color: AppColors.scrimAt(0.50),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(
                      color: AppColors.specularAt(0.24),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: song != null
                      ? CachedArtwork(
                          id: song.id,
                          albumId: song.albumId,
                          remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                          type: ArtworkType.AUDIO,
                          size: artSize,
                          borderRadius: 28,
                          highQuality: true,
                          fallbackIcon: Icons.music_note_rounded,
                        )
                      : Container(
                          color: Colors.black26,
                          child: Icon(
                            Icons.music_note_rounded,
                            size: artSize * 0.4,
                            color: Colors.white54,
                          ),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sonic Ripples Painter: Expanding acoustic wavefronts radiating outward
// ---------------------------------------------------------------------------
class _SonicRipplesPainter extends CustomPainter {
  final Color color;
  final double progress;
  final bool isPlaying;
  final double baseRadius;

  _SonicRipplesPainter({
    required this.color,
    required this.progress,
    required this.isPlaying,
    required this.baseRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isPlaying) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxExpansion = math.max(size.width, size.height) * 0.50;

    const ringCount = 3;
    for (int i = 0; i < ringCount; i++) {
      final ringProgress = (progress + (i / ringCount)) % 1.0;
      final currentRadius = baseRadius + (ringProgress * maxExpansion);
      // Smooth bell curve opacity: fades in, glows brightly, fades out gently
      final alpha = (math.sin(ringProgress * math.pi) * 0.40).clamp(0.0, 1.0);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.5 * (1.0 - ringProgress * 0.6)).clamp(1.0, 2.5)
        ..color = color.withValues(alpha: alpha);

      canvas.drawCircle(center, currentRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SonicRipplesPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.color != color ||
        oldDelegate.baseRadius != baseRadius;
  }
}

// ---------------------------------------------------------------------------
// Fluid Audio Waves Painter: Harmonic multi-layer neon waves with gradient fills
// ---------------------------------------------------------------------------
class _FluidAudioWavesPainter extends CustomPainter {
  final Color color;
  final double progress;
  final bool isPlaying;
  final double baselineY;

  _FluidAudioWavesPainter({
    required this.color,
    required this.progress,
    required this.isPlaying,
    required this.baselineY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final phase = progress * 2 * math.pi;

    final double midY = baselineY.clamp(height * 0.45, height * 0.85);
    final double amp1 = isPlaying ? 38.0 : 12.0;
    final double amp2 = isPlaying ? 26.0 : 8.0;

    // --- Wave Layer 1: Ambient Background Sine (Deeper tone, soft fill) ---
    final path1 = Path();
    final fill1 = Path();

    fill1.moveTo(0, height);
    path1.moveTo(0, midY);
    fill1.lineTo(0, midY);

    const int steps = 54;
    for (int i = 0; i <= steps; i++) {
      final x = (i / steps) * width;
      final normalX = (i / steps) * 2 * math.pi;
      final y = midY +
          math.sin(normalX * 1.6 + phase * 0.8) * amp1 +
          math.cos(normalX * 0.8 - phase * 0.4) * (amp1 * 0.45);
      path1.lineTo(x, y);
      fill1.lineTo(x, y);
    }

    fill1.lineTo(width, height);
    fill1.close();

    final fillPaint1 = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: isPlaying ? 0.28 : 0.12),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(
          Rect.fromLTWH(0, midY - amp1, width, height - (midY - amp1)));

    final strokePaint1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withValues(alpha: isPlaying ? 0.50 : 0.22);

    canvas.drawPath(fill1, fillPaint1);
    canvas.drawPath(path1, strokePaint1);

    // --- Wave Layer 2: Foreground Crisp Harmonic (Brighter neon crest) ---
    final path2 = Path();
    final fill2 = Path();

    fill2.moveTo(0, height);
    path2.moveTo(0, midY + 6);
    fill2.lineTo(0, midY + 6);

    for (int i = 0; i <= steps; i++) {
      final x = (i / steps) * width;
      final normalX = (i / steps) * 2 * math.pi;
      final y = (midY + 6) +
          math.sin(normalX * 2.2 - phase * 1.2) * amp2 +
          math.sin(normalX * 1.1 + phase * 0.6) * (amp2 * 0.55);
      path2.lineTo(x, y);
      fill2.lineTo(x, y);
    }

    fill2.lineTo(width, height);
    fill2.close();

    final fillPaint2 = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: isPlaying ? 0.40 : 0.18),
          Colors.transparent,
        ],
      ).createShader(
          Rect.fromLTWH(0, midY - amp2, width, height - (midY - amp2)));

    // Neon glow underneath
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..color = color.withValues(alpha: isPlaying ? 0.35 : 0.12);

    final strokePaint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: isPlaying ? 0.95 : 0.50);

    canvas.drawPath(fill2, fillPaint2);
    canvas.drawPath(path2, glowPaint);
    canvas.drawPath(path2, strokePaint2);

    // Peak sparkling neon dots
    if (isPlaying) {
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white;

      final dotGlow = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.6);

      for (int i = 3; i < steps; i += 6) {
        final x = (i / steps) * width;
        final normalX = (i / steps) * 2 * math.pi;
        final y = (midY + 6) +
            math.sin(normalX * 2.2 - phase * 1.2) * amp2 +
            math.sin(normalX * 1.1 + phase * 0.6) * (amp2 * 0.55);
        canvas.drawCircle(Offset(x, y), 5.0, dotGlow);
        canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FluidAudioWavesPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.color != color ||
        oldDelegate.baselineY != baselineY;
  }
}
