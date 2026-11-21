part of '../waveform_player_theme.dart';

// ---------------------------------------------------------------------------
// Waveform Hero Stage: Real Waveform Overview + Sonic Pulse + Floating Art
// ---------------------------------------------------------------------------
class _WaveformHeroStage extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;
  final bool isPlaying;
  final bool isLandscape;
  final bool isTablet;
  final AnimationController waveController;
  final int? audioSessionId;
  final String heroTag;

  const _WaveformHeroStage({
    super.key,
    required this.song,
    required this.activeColor,
    required this.isPlaying,
    required this.isLandscape,
    required this.isTablet,
    required this.waveController,
    this.audioSessionId,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: _buildStage);
  }

  /// Lays the stage out against its own height.
  ///
  /// The overview strip is a preview of the same peaks the seek bar already
  /// draws, so on a stage squeezed to a few dozen pixels by a 200% text-scale
  /// chrome it steps aside instead of reserving 48 dp the stage does not have.
  Widget _buildStage(BuildContext context, BoxConstraints stageConstraints) {
    final song = this.song;
    // The overview gets a lane of its own under the artwork: painted across the
    // cover it would be unreadable, and a streamed row has no peaks at all.
    final SongsTableData? overviewSong =
        _hasLocalAudioPath(song?.path) ? song : null;
    final bool showOverview =
        overviewSong != null && stageConstraints.maxHeight >= 96.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableW =
                  constraints.maxWidth - (isTablet ? 20.0 : 4.0);
              final availableH =
                  constraints.maxHeight - (isTablet ? 16.0 : 2.0);
              final maxDimension = math.min(availableW, availableH);

              final double rawSize = maxDimension;
              final double maxAllowed = isTablet ? 600.0 : 480.0;
              final double artSize = isLandscape
                  ? (constraints.maxHeight * 0.86).clamp(160.0, 360.0)
                  : (rawSize <= 0 ? 0.0 : math.min(rawSize, maxAllowed));

              return Stack(
                alignment: Alignment.center,
                children: [
                  // 1. Live FFT Visualizer Waveform Layer (Isolated in RepaintBoundary)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Builder(
                        builder: (context) {
                          final visualizerStyle = context
                              .select<SettingsCubit, VisualizerStyle>(
                                  (c) => c.state.visualizerStyle);
                          if (visualizerStyle == VisualizerStyle.off) {
                            return const SizedBox.shrink();
                          }
                          return Opacity(
                            opacity: isPlaying ? 0.65 : 0.25,
                            child: AudioVisualizer(
                              style: visualizerStyle,
                              color: activeColor,
                              isPlaying: isPlaying,
                              audioSessionId: audioSessionId,
                              trackId: song?.id,
                              trackPath: song?.path,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // 2. Concentric Sonic Pulse Rings expanding from center
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                          begin: 0.0, end: isPlaying ? 1.0 : 0.0),
                      duration: context.motionMs(320),
                      curve: Curves.easeOutCubic,
                      builder: (context, fadeMultiplier, _) {
                        if (fadeMultiplier <= 0.001) {
                          return const SizedBox.shrink();
                        }
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

                  // 3. Center Floating Artwork Squircle with Neon Shadow,
                  //    Border, and 3D Perspective Tilt (long-press only).
                  Positioned(
                    child: _TiltableArtworkSquircle(
                      size: artSize,
                      child: Hero(
                        tag: heroTag,
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
                              color: AppColors.specularAt(
                                  isPlaying ? 0.34 : 0.22),
                              width: 1.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: PlayerArtworkSemantics(
                            song: song,
                            child: song != null
                                ? CachedArtwork(
                                    id: song.id,
                                    albumId: song.albumId,
                                    remoteUrl: song.remoteArtworkUrl ??
                                        song.artworkUri,
                                    type: ArtworkType.AUDIO,
                                    size: artSize,
                                    borderRadius: 28,
                                    highQuality: true,
                                    fallbackIcon: Icons.music_note_rounded,
                                  )
                                : ExcludeSemantics(
                                    child: Builder(
                                      builder: (context) {
                                        final surface =
                                            context.playerSurfacePalette;
                                        return Container(
                                          color: surface.tapeWindow
                                              .withValues(alpha: 0.45),
                                          child: Icon(
                                            Icons.music_note_rounded,
                                            size: artSize * 0.4,
                                            color: surface.mutedInk,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // 4. Real waveform overview. Static, tinted by playback state, and
        //    only present when there are decoded peaks to show.
        if (showOverview)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: SizedBox(
              height: _kOverviewStripHeight,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: _WaveformOverviewStrip(
                      songId: overviewSong.id,
                      filePath: overviewSong.path,
                      activeColor: activeColor,
                      isPlaying: isPlaying,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
  late AnimationController _springController;
  late Animation<Offset> _tiltAnim;
  Offset _currentTilt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _tiltAnim = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutCubic),
    );
    _springController.addListener(() {
      setState(() {
        _currentTilt = _tiltAnim.value;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce Motion: the release snaps flat instead of tweening back.
    _springController.duration = context.motionMs(320);
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _tiltTo(Offset dragDelta) {
    final half = widget.size / 2;
    if (half <= 0) return;
    final dx = (dragDelta.dx / half).clamp(-1.0, 1.0);
    final dy = (dragDelta.dy / half).clamp(-1.0, 1.0);
    setState(() {
      _currentTilt = Offset(dx, dy);
    });
  }

  void _onLongPressStart(LongPressStartDetails details) {
    // The hold is what confirms the intent, so it gets the confirmation tap; the
    // artwork then tilts with the drag instead of jumping to the finger.
    PulsrHaptics.light();
    setState(() => _currentTilt = Offset.zero);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    _tiltTo(details.offsetFromOrigin);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _springBack();
  }

  void _springBack() {
    _tiltAnim = Tween<Offset>(
      begin: _currentTilt,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _springController,
        curve: context.motionCurve(Curves.easeOutCubic),
      ),
    );
    _springController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final rotX = -_currentTilt.dy * 0.08;
    final rotY = _currentTilt.dx * 0.08;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0015)
      ..rotateX(rotX)
      ..rotateY(rotY);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // A plain pan here fought PlayerGestureScope's horizontal swipe (next /
      // previous) and the tap that toggles lyrics, so a slightly diagonal swipe
      // either skipped a track or killed the tilt. A long press claims the
      // arena only after the finger has held still, which gives each gesture a
      // recogniser of its own: tap = lyrics, swipe = track change, hold + drag
      // = tilt.
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _springBack,
      // The tilt is decoration; the artwork publishes its own image node.
      excludeFromSemantics: true,
      child: Transform(
        alignment: FractionalOffset.center,
        transform: transform,
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
      final alpha = ((math.sin(ringProgress * math.pi) * 0.40) * fadeMultiplier)
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
// Real Waveform Overview Strip
// ---------------------------------------------------------------------------
/// Height of the overview lane under the artwork.
const double _kOverviewStripHeight = 40.0;

/// Dips the playhead through 120 steps, so the strip is not rebuilt on every
/// position tick while still stepping smoothly enough for a thin playhead.
const int _kOverviewSteps = 120;

/// Only a local row has PCM to analyse. [WaveformService.getWaveform] hands back
/// a generated placeholder for anything streamed, so those rows never reach it:
/// an invented graph is the exact defect the fake spectrum HUD had, only quieter.
bool _hasLocalAudioPath(String? path) {
  if (path == null || path.isEmpty) return false;
  if (path.startsWith('http')) return false;
  return !path.startsWith('ytmusic://');
}

/// Peak overview of the current track, drawn from decoded samples.
///
/// [WaveformService.getWaveform] is the only source: it returns the cached
/// native PCM peaks for a local file (the same list the seek bar draws). It is
/// deliberately not seeded with [WaveformService.getInstantWaveform], whose
/// synchronous result is the generator's deterministic placeholder, and the
/// strip renders nothing at all until real peaks exist.
class _WaveformOverviewStrip extends StatefulWidget {
  final int songId;
  final String? filePath;
  final Color activeColor;
  final bool isPlaying;

  const _WaveformOverviewStrip({
    required this.songId,
    required this.filePath,
    required this.activeColor,
    required this.isPlaying,
  });

  @override
  State<_WaveformOverviewStrip> createState() => _WaveformOverviewStripState();
}

class _WaveformOverviewStripState extends State<_WaveformOverviewStrip> {
  Future<List<double>>? _samplesFuture;
  int? _loadedSongId;
  String? _loadedPath;

  Future<List<double>> _samplesForCurrentSong() {
    if (_samplesFuture == null ||
        _loadedSongId != widget.songId ||
        _loadedPath != widget.filePath) {
      _loadedSongId = widget.songId;
      _loadedPath = widget.filePath;
      // Default sample count on purpose: it shares the seek bar's cache entry,
      // so opening Now Playing never decodes the same file twice.
      _samplesFuture = WaveformService.instance.getWaveform(
        songId: widget.songId,
        filePath: widget.filePath,
      );
    }
    return _samplesFuture!;
  }

  static int _playedStep(PlayerState state) {
    final durationMs = state.duration.inMilliseconds;
    if (durationMs <= 0) return 0;
    final step =
        (state.position.inMilliseconds / durationMs) * _kOverviewSteps;
    return step.round().clamp(0, _kOverviewSteps);
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FutureBuilder<List<double>>(
        future: _samplesForCurrentSong(),
        builder: (context, snapshot) {
          final samples = snapshot.data;
          if (samples == null || samples.isEmpty) {
            // Nothing decoded yet (or the file could not be read): show nothing
            // rather than filler that pretends to be this recording.
            return const SizedBox.shrink();
          }
          return RepaintBoundary(
            // Only the strip subscribes to position; the theme itself must not
            // rebuild for a playhead nudge.
            child: BlocSelector<PlayerCubit, PlayerState, int>(
              selector: _playedStep,
              builder: (context, step) => CustomPaint(
                size: const Size(double.infinity, _kOverviewStripHeight),
                painter: _WaveformOverviewPainter(
                  samples: samples,
                  progress: (step / _kOverviewSteps).clamp(0.0, 1.0),
                  activeColor: widget.activeColor,
                  isPlaying: widget.isPlaying,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Mirrored peak bars with the played part in the accent colour. Static apart
/// from the played/unplayed boundary, which steps through [_kOverviewSteps]
/// instead of rebuilding per frame.
class _WaveformOverviewPainter extends CustomPainter {
  final List<double> samples;
  final double progress;
  final Color activeColor;
  final bool isPlaying;

  _WaveformOverviewPainter({
    required this.samples,
    required this.progress,
    required this.activeColor,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;

    final double midY = size.height / 2;
    final int count = samples.length;
    final double slot = size.width / count;
    final double barWidth = math.max(1.0, slot * 0.62);
    final double playedX = size.width * progress;

    final playedPaint = Paint()
      ..color = activeColor.withValues(alpha: isPlaying ? 1.0 : 0.70);
    final unplayedPaint = Paint()
      ..color = activeColor.withValues(alpha: isPlaying ? 0.26 : 0.16);

    for (int i = 0; i < count; i++) {
      final double centerX = slot * (i + 0.5);
      final double barHeight =
          (samples[i].clamp(0.0, 1.0) * size.height).clamp(1.5, size.height);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, midY),
          width: barWidth,
          height: barHeight,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(
        rrect,
        centerX <= playedX ? playedPaint : unplayedPaint,
      );
    }

    // Playhead: a hairline, so the played/unplayed boundary is unambiguous.
    final headPaint = Paint()
      ..color = activeColor.withValues(alpha: isPlaying ? 0.95 : 0.55)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(playedX, 0),
      Offset(playedX, size.height),
      headPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformOverviewPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.isPlaying != isPlaying;
}

