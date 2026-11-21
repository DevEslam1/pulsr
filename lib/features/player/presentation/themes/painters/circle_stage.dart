part of '../circle_player_theme.dart';

/// Luxury Rotary Dial Audio Stage (Bang & Olufsen / Dieter Rams aesthetic):
/// Features a precision knurled aluminum bezel, circumferential neon progress arc,
/// orbiting luminous position bead, interactive rotary dial scrubbing, and central rotating disc with metallic spindle.
class _CircleArtwork extends StatefulWidget {
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
  State<_CircleArtwork> createState() => _CircleArtworkState();
}

class _CircleArtworkState extends State<_CircleArtwork>
    with SingleTickerProviderStateMixin {
  /// Turns the finger has added to the platter. Never reset on release, so the
  /// record keeps the angle the hand left it at instead of snapping back to the
  /// playback-only angle.
  final ValueNotifier<double> _rotationOffset = ValueNotifier<double>(0.0);

  /// Live scrub progress while a drag is in flight, `null` when idle. Held in a
  /// notifier rather than setState: a pointer move only has to repaint one arc,
  /// not rebuild the bezel, the hero artwork and the spindle.
  final ValueNotifier<double?> _dragProgress = ValueNotifier<double?>(null);

  late final AnimationController _grabController;
  late final Listenable _arcRepaint;

  /// Playback rotation with the finger's own turns folded in (see
  /// [_OffsetRotation]). Built once because the parent owns the controller.
  late final _OffsetRotation _discTurns;

  /// Progress at the previous pointer sample. The delta between samples is what
  /// turns the disc, which is also what lets the 12 o'clock seam be unwrapped.
  double? _lastDragProgress;
  int _lastTickIndex = -1;

  @override
  void initState() {
    super.initState();
    _grabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _arcRepaint = Listenable.merge([_dragProgress, _grabController]);
    _discTurns = _OffsetRotation(widget.rotationController, _rotationOffset);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce Motion collapses this to zero, so the bead snaps to its grabbed
    // size instead of tweening.
    _grabController.duration = context.motionMs(200);
  }

  @override
  void didUpdateWidget(covariant _CircleArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new track is a new groove: carrying the previous angle over would show
    // the record already turned for music that has not started.
    if (oldWidget.props.state.currentSong?.id !=
        widget.props.state.currentSong?.id) {
      _rotationOffset.value = 0.0;
      _resetScrub();
    }
  }

  @override
  void dispose() {
    _grabController.dispose();
    _rotationOffset.dispose();
    _dragProgress.dispose();
    super.dispose();
  }

  double _angleToProgress(Offset localPos, double size) {
    final center = Offset(size / 2, size / 2);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;
    final angle = math.atan2(dy, dx);
    // Arc starts at 12 o'clock (-pi/2) and sweeps clockwise
    double normalized = (angle + math.pi / 2) % (2 * math.pi);
    if (normalized < 0) normalized += 2 * math.pi;
    return (normalized / (2 * math.pi)).clamp(0.0, 1.0);
  }

  /// Relative seek clamped to the track bounds, for the semantic +-10 s steps
  /// (same increment as the other seek surfaces).
  Duration _clampSeek(Duration delta) {
    final duration = widget.props.state.duration;
    final target = widget.props.state.position + delta;
    if (target < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && target > duration) return duration;
    return target;
  }

  String _seekValue(Duration position) =>
      '${Formatters.formatDuration(position)} / '
      '${Formatters.formatDuration(widget.props.state.duration)}';

  void _handlePanStart(Offset localPos, double dialSize) {
    final startProgress = _angleToProgress(localPos, dialSize);
    _lastDragProgress = startProgress;
    _dragProgress.value = startProgress;
    _grabController.forward();
    _notifyTick(startProgress);
  }

  void _handlePanUpdate(Offset localPos, double dialSize) {
    final newProgress = _angleToProgress(localPos, dialSize);
    final previous = _lastDragProgress;
    if (previous != null) {
      var delta = newProgress - previous;
      // 12 o'clock is the seam of the angle mapping: a finger crossing it reads
      // as a near-full reverse jump in raw progress. Unwrap the difference, or
      // the disc spins backwards under a forward-dragging finger.
      if (delta > 0.5) delta -= 1.0;
      if (delta < -0.5) delta += 1.0;
      // One full turn around the dial is one full turn of the disc, so the
      // record stays pinned under the finger that is turning it.
      _rotationOffset.value += delta;
    }
    _lastDragProgress = newProgress;
    _dragProgress.value = newProgress;
    _notifyTick(newProgress);
  }

  /// One haptic per 1/72 of the dial turn; every sixth tick (12, 3, 6 and 9
  /// o'clock) is a major one. Unchanged tick logic, just callable from the drag
  /// start so the dial still clicks under the first touch.
  void _notifyTick(double progress) {
    final tick = (progress * 72).floor();
    if (tick == _lastTickIndex) return;
    if (tick % 6 == 0) {
      PulsrHaptics.selection();
    } else {
      PulsrHaptics.light();
    }
    _lastTickIndex = tick;
  }

  void _handlePanEnd() {
    final target = _dragProgress.value;
    final durationMs = widget.props.state.duration.inMilliseconds;
    if (target != null && durationMs > 0) {
      widget.props.cubit.seek(
        Duration(milliseconds: (target * durationMs).round()),
      );
    }
    _resetScrub();
  }

  void _resetScrub() {
    _dragProgress.value = null;
    _lastDragProgress = null;
    _lastTickIndex = -1;
    _grabController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final surface = context.playerSurfacePalette;
    final state = widget.props.state;
    final currentSong = state.currentSong;
    final durationMs = state.duration.inMilliseconds;
    final positionMs = state.position.inMilliseconds;
    final progress =
        durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;
    final activeColor = widget.activeColor;
    final isLandscape = widget.isLandscape;
    final isTablet = widget.isTablet;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDimension = isLandscape ? 310.0 : (isTablet ? 550.0 : 420.0);
        final dialSize = math.min(
          math.min(constraints.maxWidth, constraints.maxHeight) * 0.95,
          maxDimension,
        );

        // The scrub band is centred on the painted arc and is never narrower
        // than the 48 dp minimum touch target: a 4 dp line is a hit target no
        // thumb can find.
        final double dialRadius = dialSize / 2;
        final double bandOuter =
            math.min((dialRadius - 18.0) + 24.0, dialRadius - 1.0);
        final double bandInner = math.max(bandOuter - 48.0, 0.0);
        final bool canSeek = durationMs > 0;

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

                // 2. Precision Knurled Bezel
                CustomPaint(
                  size: Size(dialSize, dialSize),
                  painter: _RotaryBezelPainter(
                    palette: p,
                    surface: surface,
                    activeColor: activeColor,
                  ),
                ),

                // 3. Neon Progress Arc & Orbiting Bead. It listens to the drag
                //    notifier and the grab tween itself, inside its own repaint
                //    boundary, so a scrub repaints one arc instead of rebuilding
                //    the jewellery around it.
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _arcRepaint,
                    builder: (context, _) => CustomPaint(
                      size: Size(dialSize, dialSize),
                      painter: _CircularProgressArcPainter(
                        activeColor: activeColor,
                        progress: _dragProgress.value ?? progress,
                        isPlaying: state.isPlaying,
                        grab: _grabController.value,
                        surface: surface,
                      ),
                    ),
                  ),
                ),

                // 4. Center Rotating Album Core (Isolated in outer + inner RepaintBoundary for 120fps)
                RepaintBoundary(
                  child: RotationTransition(
                    turns: _discTurns,
                    child: RepaintBoundary(
                      child: Container(
                        width: dialSize * 0.68,
                        height: dialSize * 0.68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: surface.vinylGroove,
                          border: Border.all(
                            color: surface.specularAt(0.32),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: surface.shadowAt(0.87),
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
                              painter: _InnerGroovesPainter(surface: surface),
                            ),

                            // Album Artwork Label
                            Container(
                              width: dialSize * 0.50,
                              height: dialSize * 0.50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: surface.specularAt(0.24),
                                  width: 1.5,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: currentSong != null
                                  ? PlayerArtworkSemantics(
                                      song: currentSong,
                                      child: CachedArtwork(
                                        id: currentSong.id,
                                        albumId: currentSong.albumId,
                                        remoteUrl:
                                            currentSong.remoteArtworkUrl ??
                                                currentSong.artworkUri,
                                        type: ArtworkType.AUDIO,
                                        size: dialSize * 0.50,
                                        borderRadius: 999,
                                        highQuality: true,
                                      ),
                                    )
                                  : ExcludeSemantics(
                                      child: Icon(
                                        Icons.album_rounded,
                                        size: dialSize * 0.22,
                                        color: surface.mutedInk,
                                      ),
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
                                    surface.platterMetalHighlight,
                                    surface.platterMetalDeep,
                                    PlayerMaterialColors.headshellShadow,
                                  ],
                                  stops: const [0.0, 0.6, 1.0],
                                ),
                                border: Border.all(
                                  color: surface.specularAt(0.38),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: surface.shadowAt(0.54),
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
                  ),
                ),

                // 5. Rotary scrub band. It sits above the disc so the whole
                //    48 dp band stays live even on the small landscape dial,
                //    and it only claims drags: a tap (no movement) still falls
                //    through to PlayerGestureScope and toggles lyrics. The disc
                //    itself is never a scrub target.
                Positioned.fill(
                  child: Semantics(
                    container: true,
                    slider: true,
                    label: context.l10n.seekLabel,
                    value: _seekValue(state.position),
                    // A live stream has no duration to seek within, so the
                    // adjustable actions stay off rather than promising a jump
                    // that cannot be honoured.
                    increasedValue: canSeek
                        ? _seekValue(_clampSeek(const Duration(seconds: 10)))
                        : null,
                    decreasedValue: canSeek
                        ? _seekValue(_clampSeek(const Duration(seconds: -10)))
                        : null,
                    onIncrease: canSeek
                        ? () => widget.props.cubit
                            .seek(_clampSeek(const Duration(seconds: 10)))
                        : null,
                    onDecrease: canSeek
                        ? () => widget.props.cubit
                            .seek(_clampSeek(const Duration(seconds: -10)))
                        : null,
                    // The dial publishes its own slider node; the raw pan
                    // gesture underneath must not add a second control node.
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.deferToChild,
                      onPanStart: (details) =>
                          _handlePanStart(details.localPosition, dialSize),
                      onPanUpdate: (details) =>
                          _handlePanUpdate(details.localPosition, dialSize),
                      onPanEnd: (_) => _handlePanEnd(),
                      onPanCancel: _resetScrub,
                      child: CustomPaint(
                        painter: _RingScrubHitArea(
                          center: Offset(dialRadius, dialRadius),
                          innerRadius: bandInner,
                          outerRadius: bandOuter,
                        ),
                      ),
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
  final PlayerSurfacePalette surface;
  final Color activeColor;

  _RotaryBezelPainter({
    required this.palette,
    required this.surface,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;

    // 1. Dark titanium outer housing
    final housingPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          surface.cassetteShell,
          PlayerMaterialColors.headshellShadow,
          surface.vinylGroove,
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
          surface.specularAt(0.25),
          surface.specularAt(0.05),
          surface.specularAt(0.25),
          surface.specularAt(0.05),
        ],
        stops: const [0.0, 0.45, 0.70, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));
    canvas.drawCircle(center, outerRadius - 1.0, borderPaint);

    // 3. Precision Swiss/Rotary knurling ticks around the perimeter
    final tickPaint = Paint()
      ..color = surface.specularAt(0.22)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final majorTickPaint = Paint()
      ..color = surface.specularAt(0.55)
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

    // 4. 12 o'clock Swiss zero-index jewel dot
    final zeroDotPos = Offset(center.dx, center.dy - (outerRadius - 9.0));
    final zeroDotPaint = Paint()..color = activeColor;
    canvas.drawCircle(zeroDotPos, 2.2, zeroDotPaint);
  }

  @override
  bool shouldRepaint(covariant _RotaryBezelPainter oldDelegate) =>
      oldDelegate.activeColor != activeColor || oldDelegate.surface != surface;
}

// ---------------------------------------------------------------------------
// Circumferential Neon Progress Arc & Orbiting Bead
// ---------------------------------------------------------------------------
class _CircularProgressArcPainter extends CustomPainter {
  final Color activeColor;
  final double progress;
  final bool isPlaying;

  /// 0 when idle, 1 when the finger is holding the scrub band. Drives the bead
  /// swell and halo: the grab affordance that says the ring can be turned.
  final double grab;
  final PlayerSurfacePalette surface;

  _CircularProgressArcPainter({
    required this.activeColor,
    required this.progress,
    required this.isPlaying,
    required this.surface,
    this.grab = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final arcRadius = (size.width / 2) - 18.0;

    // 1. Recessed background guide track
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = surface.specularAt(0.08);
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
      ..color = activeColor.withValues(alpha: 0.75 + (0.20 * grab))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6.0 + (4.0 * grab));
    canvas.drawCircle(beadPos, 6.0 + (4.5 * grab), beadGlowPaint);

    final beadPaint = Paint()..color = surface.highContrastInk;
    canvas.drawCircle(beadPos, 3.5 + (3.0 * grab), beadPaint);

    // A thin grip ring only while pressed, so the bead reads as a knob the
    // finger has hold of rather than an ornament that happens to glow.
    if (grab > 0.01) {
      final gripPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = activeColor.withValues(alpha: 0.55 * grab);
      canvas.drawCircle(beadPos, 9.5 + (4.5 * grab), gripPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CircularProgressArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.isPlaying != isPlaying ||
      oldDelegate.grab != grab ||
      oldDelegate.surface != surface;
}

// ---------------------------------------------------------------------------
// Rotary Scrub Band Hit Area
// ---------------------------------------------------------------------------
/// Paints nothing. It exists so the ring around the dial is the only part of
/// the stage that answers a drag: the artwork in the middle stays a plain tap
/// target (lyrics), and the band can be widened to the 48 dp touch minimum
/// without moving a single pixel of the drawing.
class _RingScrubHitArea extends CustomPainter {
  final Offset center;
  final double innerRadius;
  final double outerRadius;

  _RingScrubHitArea({
    required this.center,
    required this.innerRadius,
    required this.outerRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool hitTest(Offset position) {
    final distance = (position - center).distance;
    return distance >= innerRadius && distance <= outerRadius;
  }

  @override
  bool shouldRepaint(covariant _RingScrubHitArea oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.innerRadius != innerRadius ||
      oldDelegate.outerRadius != outerRadius;
}

// ---------------------------------------------------------------------------
// Inner Disc Micro-Grooves Painter
// ---------------------------------------------------------------------------
class _InnerGroovesPainter extends CustomPainter {
  final PlayerSurfacePalette surface;

  _InnerGroovesPainter({required this.surface});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = surface.specularAt(0.04);

    for (double r = radius * 0.40; r < radius - 4; r += 5.5) {
      canvas.drawCircle(center, r, groovePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _InnerGroovesPainter oldDelegate) =>
      oldDelegate.surface != surface;
}

// ---------------------------------------------------------------------------
// Playback Rotation + Finger Offset
// ---------------------------------------------------------------------------
/// Playback rotation with the finger's own turns folded in.
///
/// This is an [Animation] on purpose: [RotationTransition] only marks its own
/// render object dirty on a tick, so playback keeps the cheap repaint-only path
/// while a drag contributes extra turns through the offset notifier. A
/// ValueListenableBuilder around the disc would have rebuilt a widget every
/// frame for the same pixels.
class _OffsetRotation extends Animation<double>
    with AnimationWithParentMixin<double> {
  _OffsetRotation(this.parent, this.offset);

  @override
  final Animation<double> parent;
  final ValueNotifier<double> offset;

  @override
  double get value => parent.value + offset.value;

  @override
  void addListener(VoidCallback listener) {
    parent.addListener(listener);
    offset.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    parent.removeListener(listener);
    offset.removeListener(listener);
  }
}
