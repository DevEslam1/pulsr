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
            // 0. Studio Graphic Spectrum EQ HUD Header
            PositionedDirectional(
              top: 4,
              child: _GraphicSpectrumHud(
                activeColor: activeColor,
                isPlaying: isPlaying,
                waveController: waveController,
              ),
            ),

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
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: isPlaying ? 1.0 : 0.0),
                duration: context.motionMs(450),
                curve: Curves.easeOutCubic,
                builder: (context, fadeMultiplier, _) {
                  if (fadeMultiplier <= 0.001) return const SizedBox.shrink();
                  return AnimatedBuilder(
                    animation: waveController,
                    builder: (context, _) {
                      return RepaintBoundary(
                        child: CustomPaint(
                          painter: _SonicRipplesPainter(
                            color: activeColor,
                            progress: waveController.value,
                            isPlaying: isPlaying,
                            baseRadius: artSize * 0.52,
                            fadeMultiplier: fadeMultiplier,
                          ),
                        ),
                      );
                    },
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

            // 3. Center Floating Artwork Squircle with Neon Shadow, Border, and 3D Perspective Tilt
            Positioned(
              child: _TiltableArtworkSquircle(
                size: artSize,
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
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 3D Perspective Tilt Squircle: Touch-responsive Matrix4 perspective rotation
// ---------------------------------------------------------------------------
class _TiltableArtworkSquircle extends StatefulWidget {
  final Widget child;
  final double size;

  const _TiltableArtworkSquircle({
    required this.child,
    required this.size,
  });

  @override
  State<_TiltableArtworkSquircle> createState() =>
      _TiltableArtworkSquircleState();
}

class _TiltableArtworkSquircleState extends State<_TiltableArtworkSquircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _returnController;
  late Animation<Offset> _returnAnimation;
  Offset _tilt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _returnController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _returnController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!mounted) return;
    _returnController.stop();
    final half = widget.size / 2;
    if (half <= 0) return;
    final dx = ((details.localPosition.dx - half) / half).clamp(-1.0, 1.0);
    final dy = ((details.localPosition.dy - half) / half).clamp(-1.0, 1.0);
    setState(() {
      _tilt = Offset(dx, dy);
    });
  }

  void _snapBack() {
    if (!mounted || _tilt == Offset.zero) return;
    final duration = context.motionMs(400);
    _returnController.duration = duration;
    _returnAnimation = Tween<Offset>(
      begin: _tilt,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _returnController,
      curve: context.motionCurve(Curves.easeOutBack),
    ));
    _returnController.forward(from: 0.0);
    _returnAnimation.addListener(() {
      if (mounted) {
        setState(() {
          _tilt = _returnAnimation.value;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const double maxAngle = 0.22; // ~12.6 degrees
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateX(-_tilt.dy * maxAngle)
      ..rotateY(_tilt.dx * maxAngle);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => _onPanUpdate(
        DragUpdateDetails(
          localPosition: d.localPosition,
          globalPosition: d.globalPosition,
        ),
      ),
      onPanUpdate: _onPanUpdate,
      onPanEnd: (_) => _snapBack(),
      onPanCancel: _snapBack,
      child: Transform(
        transform: transform,
        alignment: Alignment.center,
        child: widget.child,
      ),
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
  final double fadeMultiplier;

  _SonicRipplesPainter({
    required this.color,
    required this.progress,
    required this.isPlaying,
    required this.baseRadius,
    this.fadeMultiplier = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fadeMultiplier <= 0.001) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxExpansion = math.max(size.width, size.height) * 0.50;

    const ringCount = 3;
    for (int i = 0; i < ringCount; i++) {
      final ringProgress = (progress + (i / ringCount)) % 1.0;
      final currentRadius = baseRadius + (ringProgress * maxExpansion);
      // Smooth bell curve opacity scaled by graceful fade-out multiplier
      final alpha =
          ((math.sin(ringProgress * math.pi) * 0.40) * fadeMultiplier)
              .clamp(0.0, 1.0);

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
        oldDelegate.baseRadius != baseRadius ||
        oldDelegate.fadeMultiplier != fadeMultiplier;
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

// ---------------------------------------------------------------------------
// 10-Band Graphic Spectrum EQ HUD (Studio Monitoring Aesthetics)
// AUDIT-FIX: Clarify spectrum generation nature
// Synthetic harmonic simulation; not driven by real FFT data.
// ---------------------------------------------------------------------------
class _GraphicSpectrumHud extends StatefulWidget {
  final Color activeColor;
  final bool isPlaying;
  final AnimationController waveController;

  const _GraphicSpectrumHud({
    required this.activeColor,
    required this.isPlaying,
    required this.waveController,
  });

  @override
  State<_GraphicSpectrumHud> createState() => _GraphicSpectrumHudState();
}

class _GraphicSpectrumHudState extends State<_GraphicSpectrumHud> {
  static const List<String> _bandLabels = [
    '32',
    '64',
    '125',
    '250',
    '500',
    '1k',
    '2k',
    '4k',
    '8k',
    '16k',
  ];

  late final List<double> _peaks;
  late final List<int> _peakHoldFrames;

  @override
  void initState() {
    super.initState();
    _peaks = List.filled(_bandLabels.length, 0.0);
    _peakHoldFrames = List.filled(_bandLabels.length, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0C12).withValues(alpha: 0.85),
        borderRadius: AppRadii.r8All,
        border: Border.all(
          color: widget.activeColor.withValues(alpha: 0.28),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: widget.waveController,
        builder: (context, _) {
          final t = widget.waveController.value * 2 * math.pi;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_bandLabels.length, (index) {
              // Synthetic harmonic multi-band visualizer simulation based on audio phase
              final double harmonic = widget.isPlaying
                  ? (math.sin(t * 1.8 + index * 0.9).abs() * 0.65 +
                      math.cos(t * 0.9 - index * 0.4).abs() * 0.35)
                  : 0.12;
              final double currentSegments = harmonic * 6;
              final int activeSegments = currentSegments.clamp(1, 6).round();

              if (widget.isPlaying) {
                if (currentSegments >= _peaks[index]) {
                  _peaks[index] = currentSegments;
                  _peakHoldFrames[index] = 14;
                } else {
                  if (_peakHoldFrames[index] > 0) {
                    _peakHoldFrames[index]--;
                  } else {
                    _peaks[index] = math.max(1.0, _peaks[index] - 0.14);
                  }
                }
              } else {
                _peaks[index] = 1.0;
                _peakHoldFrames[index] = 0;
              }
              final int peakSeg = (_peaks[index] - 0.5).round().clamp(0, 5);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Vertical LED segments
                    for (int seg = 5; seg >= 0; seg--) ...[
                      Builder(builder: (_) {
                        final bool isActive = seg < activeSegments;
                        final bool isPeak = seg == peakSeg && widget.isPlaying;
                        Color segColor;
                        if (isActive || isPeak) {
                          if (seg >= 4) {
                            segColor = Colors.redAccent;
                          } else if (seg >= 3) {
                            segColor = Colors.amberAccent;
                          } else {
                            segColor = widget.activeColor;
                          }
                          if (!isActive && isPeak) {
                            segColor = segColor.withValues(alpha: 0.95);
                          }
                        } else {
                          segColor = Colors.white.withValues(alpha: 0.08);
                        }

                        return Container(
                          width: 8,
                          height: 2.2,
                          margin: const EdgeInsets.symmetric(vertical: 0.6),
                          decoration: BoxDecoration(
                            color: segColor,
                            borderRadius: BorderRadius.circular(0.8),
                            boxShadow: isPeak
                                ? [
                                    BoxShadow(
                                      color: segColor.withValues(alpha: 0.6),
                                      blurRadius: 2,
                                    )
                                  ]
                                : null,
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 2),
                    // Frequency Label
                    Text(
                      _bandLabels[index],
                      style: const TextStyle(
                        fontSize: 6.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white54,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
