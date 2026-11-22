part of '../cassette_player_theme.dart';

/// Full-screen anodized brushed-aluminum Walkman chassis painter with machined
/// horizontal panel seams, brushed grain, corner screws, and subtle ambient glow.
/// Strictly zero raw hex literals and zero `Colors.*` references.
class _AnodizedDeckChassisPainter extends CustomPainter {
  final Color topColor;
  final Color midColor;
  final Color bottomColor;
  final Color seamHighlight;
  final Color seamShadow;
  final Color screwColor;
  final Color glowColor;

  _AnodizedDeckChassisPainter({
    required this.topColor,
    required this.midColor,
    required this.bottomColor,
    required this.seamHighlight,
    required this.seamShadow,
    required this.screwColor,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Anodized metal base gradient
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [topColor, midColor, bottomColor],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    // 2. Subtle radial glow behind cassette bay
    final bayCenter = Offset(size.width * 0.5, size.height * 0.32);
    final haloRadius = math.max(size.width, size.height) * 0.55;
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [glowColor, glowColor.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: bayCenter, radius: haloRadius));
    canvas.drawRect(rect, haloPaint);

    // 3. Fine horizontal brushed anodized aluminum texture
    final isGpuSaver = GpuBudget.isGpuSaverActive;
    final step = isGpuSaver ? 14.0 : 6.0;
    final grainPaint = Paint()
      ..color = seamHighlight
      ..strokeWidth = 0.7;
    for (double y = 0; y < size.height; y += step) {
      if ((y ~/ step).isEven) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grainPaint);
      }
    }

    // 4. Machined chassis panel seam grooves (separating bay / meter / keybank)
    final seamShadowPaint = Paint()
      ..color = seamShadow
      ..strokeWidth = 1.2;
    final seamLightPaint = Paint()
      ..color = seamHighlight
      ..strokeWidth = 1.0;

    for (final ratio in const [0.54, 0.78]) {
      final y = size.height * ratio;
      canvas.drawLine(Offset(14, y), Offset(size.width - 14, y), seamShadowPaint);
      canvas.drawLine(
        Offset(14, y + 1.2),
        Offset(size.width - 14, y + 1.2),
        seamLightPaint,
      );
    }

    // 5. Outer chassis inset bezel hairline
    final bezelRect = RRect.fromRectAndRadius(
      rect.deflate(6),
      const Radius.circular(AppRadii.r16),
    );
    canvas.drawRRect(
      bezelRect,
      Paint()
        ..color = seamHighlight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // 6. Machined corner chassis screws
    const double margin = 16.0;
    final corners = [
      const Offset(margin, margin),
      Offset(size.width - margin, margin),
      Offset(margin, size.height - margin),
      Offset(size.width - margin, size.height - margin),
    ];
    final screwFill = Paint()
      ..color = screwColor.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    final screwRim = Paint()
      ..color = seamShadow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final screwSlot = Paint()
      ..color = seamShadow
      ..strokeWidth = 1.1;

    for (final c in corners) {
      canvas.drawCircle(c, 3.6, screwFill);
      canvas.drawCircle(c, 3.6, screwRim);
      canvas.drawLine(
        Offset(c.dx - 2.2, c.dy - 1.2),
        Offset(c.dx + 2.2, c.dy + 1.2),
        screwSlot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnodizedDeckChassisPainter oldDelegate) =>
      oldDelegate.topColor != topColor ||
      oldDelegate.midColor != midColor ||
      oldDelegate.bottomColor != bottomColor ||
      oldDelegate.seamHighlight != seamHighlight ||
      oldDelegate.seamShadow != seamShadow ||
      oldDelegate.screwColor != screwColor ||
      oldDelegate.glowColor != glowColor;
}

/// Ultra-detailed skeuomorphic cassette shell with dynamic magnetic tape transfer,
/// 3-digit mechanical rolling counter, stereo VU level meters, and acrylic glass sheen.
class _CassetteBody extends StatefulWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final AnimationController spoolController;
  final bool isLandscape;
  final bool isTablet;

  const _CassetteBody({
    required this.props,
    required this.activeColor,
    required this.spoolController,
    required this.isLandscape,
    required this.isTablet,
  });

  @override
  State<_CassetteBody> createState() => _CassetteBodyState();
}

class _CassetteBodyState extends State<_CassetteBody> {
  /// One full left-to-right pass over the acrylic well is worth this much
  /// audio. Expressing the ratio per well width (rather than per pixel) keeps
  /// the feel identical at every viewport: the shell is a fixed 450x296 box
  /// rendered through a FittedBox, so raw pixel deltas change meaning with the
  /// scale while a fraction of the surface does not.
  static const double _scrubRangeSeconds = 60.0;

  /// Coarse tactile detents, spaced like the vinyl platter's selection clicks.
  static const int _scrubDetentMs = 5000;

  /// Drags shorter than this are finger jitter on a tap, not a seek: the stage
  /// should keep toggling lyrics rather than nudging the playhead 60 ms.
  static const int _scrubCommitFloorMs = 400;

  /// Frozen at drag start so the target cannot drift while the player keeps
  /// running underneath the finger.
  int _scrubBaseMs = 0;
  int? _scrubTargetMs;
  double _scrubTravelPx = 0.0;
  int _detentIndex = 0;

  bool get _isScrubbing => _scrubTargetMs != null;

  @override
  void didUpdateWidget(covariant _CassetteBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching track mid-drag invalidates both the base position and the
    // duration the delta was clamped against.
    if (oldWidget.props.state.currentSong?.id !=
        widget.props.state.currentSong?.id) {
      _scrubTargetMs = null;
      _scrubTravelPx = 0.0;
    }
  }

  void _onScrubStart(DragStartDetails _) {
    final state = widget.props.state;
    final durationMs = state.duration.inMilliseconds;
    if (durationMs <= 0) return;
    final baseMs = state.position.inMilliseconds.clamp(0, durationMs);
    setState(() {
      _scrubBaseMs = baseMs;
      _scrubTargetMs = baseMs;
      _scrubTravelPx = 0.0;
      _detentIndex = 0;
    });
  }

  void _onScrubUpdate(double deltaDx, double wellWidth) {
    final target = _scrubTargetMs;
    final durationMs = widget.props.state.duration.inMilliseconds;
    if (target == null || wellWidth <= 0 || durationMs <= 0) return;

    _scrubTravelPx += deltaDx;
    final deltaMs = (_scrubTravelPx / wellWidth) * _scrubRangeSeconds * 1000.0;
    final nextMs = (_scrubBaseMs + deltaMs.round()).clamp(0, durationMs);
    final detentIndex = (nextMs - _scrubBaseMs) ~/ _scrubDetentMs;
    if (detentIndex != _detentIndex) {
      _detentIndex = detentIndex;
      PulsrHaptics.selection();
    }
    if (nextMs != target) {
      setState(() => _scrubTargetMs = nextMs);
    }
  }

  void _commitScrub() {
    final target = _scrubTargetMs;
    if (target == null) return;
    if ((target - _scrubBaseMs).abs() >= _scrubCommitFloorMs) {
      PulsrHaptics.selection();
      widget.props.cubit.seek(Duration(milliseconds: target));
    }
    setState(() {
      _scrubTargetMs = null;
      _scrubTravelPx = 0.0;
    });
  }

  void _cancelScrub() {
    if (_scrubTargetMs == null) return;
    setState(() {
      _scrubTargetMs = null;
      _scrubTravelPx = 0.0;
    });
  }

  /// Screen-reader seeking: ±10 s from the live position, clamped to the track.
  void _seekBy(Duration delta) {
    final state = widget.props.state;
    final durationMs = state.duration.inMilliseconds;
    if (durationMs <= 0) return;
    final nextMs = (state.position + delta).inMilliseconds.clamp(0, durationMs);
    PulsrHaptics.selection();
    widget.props.cubit.seek(Duration(milliseconds: nextMs));
  }

  @override
  Widget build(BuildContext context) {
    final surface = context.playerSurfacePalette;
    final state = widget.props.state;
    final song = state.currentSong;
    final durationMs = state.duration.inMilliseconds;
    final progress = durationMs > 0
        ? (state.position.inMilliseconds / durationMs).clamp(0.0, 1.0)
        : 0.0;
    final displayProgress = _isScrubbing && durationMs > 0
        ? (_scrubTargetMs! / durationMs).clamp(0.0, 1.0)
        : progress;

    return MediaQuery.withNoTextScaling(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: widget.isLandscape ? 260 : (widget.isTablet ? 360 : 285),
            maxWidth: widget.isLandscape ? 400 : (widget.isTablet ? 540 : 440),
          ),
          child: AspectRatio(
            aspectRatio: 1.52,
            child: PlayerGestureScope(
              behavior: HitTestBehavior.deferToChild,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 450,
                  height: 450 / 1.52,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          surface.cassetteShell,
                          PlayerMaterialColors.cassetteBodyMid,
                          surface.tapeWindow,
                        ],
                      ),
                      borderRadius: AppRadii.r20All,
                      border: Border.all(
                        color: PlayerMaterialColors.cassetteBodyBorder,
                        width: 3.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: surface.shadowAt(0.6),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: widget.activeColor.withValues(alpha: 0.08),
                          blurRadius: 30,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // 1. Four Corner Screws
                        const PositionedDirectional(
                            top: 4, start: 4, child: _CassetteScrew()),
                        const PositionedDirectional(
                            top: 4, end: 4, child: _CassetteScrew()),
                        const PositionedDirectional(
                            bottom: 4, start: 4, child: _CassetteScrew()),
                        const PositionedDirectional(
                            bottom: 4, end: 4, child: _CassetteScrew()),

                        // 2. Main Cassette Body Layout
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s8,
                            vertical: AppSpacing.xxs,
                          ),
                          child: Column(
                            children: [
                              ExcludeSemantics(
                                child: _buildCassetteHeader(
                                    context, state.isPlaying),
                              ),
                              const SizedBox(height: AppSpacing.s8),
                              Expanded(
                                child: _buildScrubSurface(
                                  progress: displayProgress,
                                  isPlaying: state.isPlaying,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s8),
                              ExcludeSemantics(
                                child: _buildBottomSection(context, song),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Upper label band with tape format badges and dual stereo dancing VU meters
  Widget _buildCassetteHeader(BuildContext context, bool isPlaying) {
    final surface = context.playerSurfacePalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: widget.activeColor.withValues(alpha: 0.16),
        borderRadius: AppRadii.r8All,
        border: Border.all(
          color: widget.activeColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left: Side & Tape Formulation
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.cassetteSideA,
                    style: TextStyle(
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w800,
                      color: surface.highContrastInk,
                      letterSpacing: AppTracking.wide,
                    ),
                  ),
                  Text(
                    context.l10n.cassetteTapeType,
                    style: TextStyle(
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w700,
                      color: surface.mutedInk,
                      letterSpacing: AppTracking.overline,
                    ),
                  ),
                ],
              ),
            ),

            // Center: Stereo Dancing VU Meters (Isolated in RepaintBoundary for 120fps)
            RepaintBoundary(
              child: _CassetteStereoVuMeter(
                activeColor: widget.activeColor,
                isPlaying: isPlaying,
              ),
            ),

            // Right: Pulsr Branding & EQ Specs
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.cassettePulsrTape,
                    style: TextStyle(
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w900,
                      color: widget.activeColor,
                      letterSpacing: AppTracking.wide,
                    ),
                  ),
                  Text(
                    context.l10n.cassetteEqSpec,
                    style: TextStyle(
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w700,
                      color: surface.mutedInk,
                      letterSpacing: AppTracking.overline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Horizontal scrub surface over the acrylic well.
  Widget _buildScrubSurface({
    required double progress,
    required bool isPlaying,
  }) {
    final state = widget.props.state;
    final durationMs = state.duration.inMilliseconds;

    Duration clampSeek(Duration delta) {
      final nextMs = (state.position + delta).inMilliseconds;
      return Duration(milliseconds: nextMs.clamp(0, math.max(0, durationMs)));
    }

    String seekLabel(Duration value) =>
        '${Formatters.formatDuration(value)} / '
        '${Formatters.formatDuration(state.duration)}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wellWidth = constraints.maxWidth;
        return Semantics(
          container: true,
          slider: true,
          label: context.l10n.seekLabel,
          value: seekLabel(state.position),
          increasedValue: seekLabel(clampSeek(const Duration(seconds: 10))),
          decreasedValue: seekLabel(clampSeek(const Duration(seconds: -10))),
          onIncrease: () => _seekBy(const Duration(seconds: 10)),
          onDecrease: () => _seekBy(const Duration(seconds: -10)),
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onScrubStart,
            onHorizontalDragUpdate: (details) =>
                _onScrubUpdate(details.delta.dx, wellWidth),
            onHorizontalDragEnd: (_) => _commitScrub(),
            onHorizontalDragCancel: _cancelScrub,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildCenterTapeWindow(context, progress, isPlaying),
                if (_isScrubbing)
                  Center(
                    child: IgnorePointer(child: _buildScrubDeltaPill(context)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Delta read-out while scrubbing.
  Widget _buildScrubDeltaPill(BuildContext context) {
    final surface = context.playerSurfacePalette;
    final deltaTenths = ((_scrubTargetMs! - _scrubBaseMs) / 100).round();
    final deltaText = (deltaTenths / 10).toStringAsFixed(1);
    final label = deltaTenths > 0 ? '+${deltaText}s' : '${deltaText}s';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: surface.tapeWindow.withValues(alpha: 0.90),
        borderRadius: AppRadii.full,
        border: Border.all(
          color: widget.activeColor.withValues(alpha: 0.65),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.activeColor.withValues(alpha: 0.40),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppFontSize.label,
          fontWeight: FontWeight.w800,
          color: surface.highContrastInk,
          letterSpacing: AppTracking.label,
        ),
      ),
    );
  }

  /// Center acrylic window with dynamic tape packs, tape path, and rolling counter
  Widget _buildCenterTapeWindow(
    BuildContext context,
    double progress,
    bool isPlaying,
  ) {
    final surface = context.playerSurfacePalette;
    const double minR = 26.0;
    const double maxR = 43.0;
    final leftTapeRadius =
        math.sqrt(maxR * maxR * (1.0 - progress) + minR * minR * progress);
    final rightTapeRadius =
        math.sqrt(minR * minR * (1.0 - progress) + maxR * maxR * progress);

    return Container(
      decoration: BoxDecoration(
        color: surface.tapeWindow,
        borderRadius: AppRadii.r14All,
        border: Border.all(color: surface.specularAt(0.24), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: surface.shadowAt(0.54),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Diagonal Acrylic Reflection Flare
          Positioned.fill(
            child: CustomPaint(
              painter: _AcrylicReflectionPainter(surface: surface),
            ),
          ),

          // 2. Center Bridge with Mechanical 3-Digit Rolling Tape Counter
          Positioned(
            top: 10,
            child: _CassetteTapeCounter(progress: progress),
          ),

          // 3. Tangent Magnetic Tape Ribbon Path & Corner Guide Rollers
          Positioned.fill(
            child: CustomPaint(
              painter: _MagneticTapePathPainter(
                leftTapeRadius: leftTapeRadius,
                rightTapeRadius: rightTapeRadius,
                surface: surface,
              ),
            ),
          ),

          // 4. Center Read Head Aperture Notch
          Positioned(
            bottom: 12,
            child: Container(
              width: 58,
              height: 22,
              decoration: BoxDecoration(
                color: PlayerMaterialColors.cassetteBridge,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                border: Border.all(
                  color: PlayerMaterialColors.cassetteBridgeBorder,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Container(
                  width: 26,
                  height: 6,
                  decoration: BoxDecoration(
                    color: PlayerMaterialColors.cassetteScrew,
                    borderRadius: AppRadii.r4All,
                  ),
                ),
              ),
            ),
          ),

          // 5. The Left & Right Reels with Dynamic Tape Packs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s28),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildReelPack(
                  surface: surface,
                  tapeRadius: leftTapeRadius,
                  isLeft: true,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    7,
                    (i) => Container(
                      width: i == 3 ? 24 : 14,
                      height: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 2.2),
                      color: i == 3
                          ? surface.specularAt(0.54)
                          : surface.specularAt(0.24),
                    ),
                  ),
                ),
                _buildReelPack(
                  surface: surface,
                  tapeRadius: rightTapeRadius,
                  isLeft: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a tape reel with its dynamic dark oxide tape pack and rotating notched hub
  Widget _buildReelPack({
    required PlayerSurfacePalette surface,
    required double tapeRadius,
    required bool isLeft,
  }) {
    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Dark Ferric-Oxide Tape Roll
          Container(
            width: tapeRadius * 2,
            height: tapeRadius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  PlayerMaterialColors.cassetteTapeOuter,
                  PlayerMaterialColors.cassetteTapeMid,
                  PlayerMaterialColors.cassetteTapeInner,
                ],
                stops: [0.35, 0.75, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: surface.shadowAt(0.87),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: CustomPaint(
              painter: _TapePackRingsPainter(surface: surface),
            ),
          ),

          // Rotating White Spool Hub with Teeth
          RepaintBoundary(
            child: RotationTransition(
              turns: widget.spoolController,
              child: RepaintBoundary(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PlayerMaterialColors.cassetteReelHub,
                    border: Border.all(
                      color: PlayerMaterialColors.cassetteReelRim,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: surface.shadowAt(0.45),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: surface.tapeWindow,
                        shape: BoxShape.circle,
                      ),
                      child: CustomPaint(
                        painter: _SpoolTeethPainter(surface: surface),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom section: printed label and trapezoidal deck housing notch.
  Widget _buildBottomSection(BuildContext context, SongsTableData? song) {
    final surface = context.playerSurfacePalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: surface.cassetteShell,
        borderRadius: AppRadii.r8All,
        border: Border.all(
          color: PlayerMaterialColors.cassetteCapstanBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song?.title ?? context.l10n.dspTapeLoaded,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                    color: surface.highContrastInk,
                    letterSpacing: AppTracking.label,
                  ),
                ),
                Text(
                  song?.artist ?? 'ANALOG MASTER AUDIO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: surface.mutedInk,
                    letterSpacing: AppTracking.medium,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: surface.shadowAt(0.45),
              borderRadius: AppRadii.r4All,
              border: Border.all(color: surface.specularAt(0.12)),
            ),
            child: ExcludeSemantics(
              child: Text(
                'NR • OFF',
                style: TextStyle(
                  fontSize: AppFontSize.tiny,
                  fontWeight: FontWeight.w800,
                  color: surface.mutedInk,
                  letterSpacing: AppTracking.medium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3-Digit Mechanical Tape Counter
// ---------------------------------------------------------------------------
class _CassetteTapeCounter extends StatelessWidget {
  final double progress;

  const _CassetteTapeCounter({required this.progress});

  @override
  Widget build(BuildContext context) {
    final surface = context.playerSurfacePalette;
    final count = (progress * 999).clamp(0, 999).toInt();
    final digits = count.toString().padLeft(3, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: surface.vinylGroove,
        borderRadius: AppRadii.r4All,
        border: Border.all(
          color: PlayerMaterialColors.cassetteHeadBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: surface.shadowAt(0.87),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < 3; i++)
            Container(
              width: 14,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: PlayerMaterialColors.cassetteHeadFill,
                borderRadius: AppRadii.circular(2),
              ),
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: context.motionMs(200),
                transitionBuilder: (child, animation) {
                  return SlideTransition(
                    position: animation.drive(
                      Tween<Offset>(
                        begin: const Offset(0.0, -1.0),
                        end: Offset.zero,
                      ).chain(
                        CurveTween(
                          curve: context.motionCurve(Curves.easeOutCubic),
                        ),
                      ),
                    ),
                    child: child,
                  );
                },
                child: ExcludeSemantics(
                  child: Text(
                    digits[i],
                    key: ValueKey<String>('counter_${i}_${digits[i]}'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w900,
                      color: surface.highContrastInk,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stereo Dancing VU Meter for Cassette Label (Segmented LEDs & Peak-Hold Dot)
// ---------------------------------------------------------------------------
class _CassetteStereoVuMeter extends StatefulWidget {
  final Color activeColor;
  final bool isPlaying;

  const _CassetteStereoVuMeter({
    required this.activeColor,
    required this.isPlaying,
  });

  @override
  State<_CassetteStereoVuMeter> createState() => _CassetteStereoVuMeterState();
}

class _CassetteStereoVuMeterState extends State<_CassetteStereoVuMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _vuController;
  double _leftPeak = 0.08;
  double _rightPeak = 0.08;
  int _leftPeakHold = 0;
  int _rightPeakHold = 0;

  @override
  void initState() {
    super.initState();
    _vuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  bool _allowMotion(BuildContext context) =>
      !PlayerThemePreviewScope.of(context) &&
      PulsrMotion.shouldAnimate(context) &&
      context.motionEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncVu();
  }

  void _syncVu() {
    final allowMotion = _allowMotion(context);
    final shouldSpin = widget.isPlaying && allowMotion;
    if (shouldSpin) {
      if (!_vuController.isAnimating) {
        _vuController.repeat(reverse: true);
      }
    } else {
      if (_vuController.isAnimating) {
        _vuController.stop();
      }
      if (!allowMotion) {
        _vuController.value = 0.0;
      } else if (_vuController.value > 0.0) {
        _vuController.animateTo(0.0, duration: context.motionMs(260));
      }
    }
  }

  @override
  void didUpdateWidget(covariant _CassetteStereoVuMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncVu();
  }

  @override
  void dispose() {
    _vuController.dispose();
    super.dispose();
  }

  void _updatePeaks(double leftLevel, double rightLevel) {
    if (leftLevel >= _leftPeak) {
      _leftPeak = leftLevel;
      _leftPeakHold = 14;
    } else if (_leftPeakHold > 0) {
      _leftPeakHold--;
    } else {
      _leftPeak = math.max(0.08, _leftPeak - 0.035);
    }

    if (rightLevel >= _rightPeak) {
      _rightPeak = rightLevel;
      _rightPeakHold = 14;
    } else if (_rightPeakHold > 0) {
      _rightPeakHold--;
    } else {
      _rightPeak = math.max(0.08, _rightPeak - 0.035);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowMotion = _allowMotion(context);
    final surface = context.playerSurfacePalette;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              height: 6.0,
              child: Center(
                child: ExcludeSemantics(
                  child: Text(
                    'L',
                    style: TextStyle(
                      fontSize: AppFontSize.nano,
                      fontWeight: FontWeight.w800,
                      color: surface.mutedInk,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2.5),
            SizedBox(
              height: 6.0,
              child: Center(
                child: ExcludeSemantics(
                  child: Text(
                    'R',
                    style: TextStyle(
                      fontSize: AppFontSize.nano,
                      fontWeight: FontWeight.w800,
                      color: surface.mutedInk,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
        CustomPaint(
          size: const Size(56.0, 14.5),
          painter: _CassetteStereoVuMeterPainter(
            controller: _vuController,
            isPlaying: widget.isPlaying,
            allowMotion: allowMotion,
            surface: surface,
            state: this,
          ),
        ),
      ],
    );
  }
}

class _CassetteStereoVuMeterPainter extends CustomPainter {
  static final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6;
  static final Paint _shadowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
  static final Paint _segPaint = Paint()..style = PaintingStyle.fill;

  final AnimationController controller;
  final bool isPlaying;
  final bool allowMotion;
  final PlayerSurfacePalette surface;
  final _CassetteStereoVuMeterState state;

  _CassetteStereoVuMeterPainter({
    required this.controller,
    required this.isPlaying,
    required this.allowMotion,
    required this.surface,
    required this.state,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final double leftLevel;
    final double rightLevel;
    if (!isPlaying) {
      leftLevel = 0.08;
      rightLevel = 0.08;
    } else if (!allowMotion) {
      leftLevel = 0.58;
      rightLevel = 0.48;
      state._leftPeak = 0.72;
      state._rightPeak = 0.64;
    } else {
      final val = controller.value;
      final theta = val * 2 * math.pi;

      final beatBase = math.sin(theta).abs() * 0.45 +
          (math.sin(theta * 2.0).abs() * 0.22);

      final leftHarmonic = math.sin(theta * 3.0 + 0.4).abs() * 0.18 +
          math.cos(theta * 7.0).abs() * 0.08;
      final rightHarmonic = math.cos(theta * 5.0 - 0.5).abs() * 0.18 +
          math.sin(theta * 11.0).abs() * 0.08;

      leftLevel = (0.16 + beatBase + leftHarmonic).clamp(0.08, 0.98);
      rightLevel = (0.16 + beatBase + rightHarmonic).clamp(0.08, 0.98);
      state._updatePeaks(leftLevel, rightLevel);
    }

    _paintChannel(canvas, 0.0, leftLevel, state._leftPeak);
    _paintChannel(canvas, 8.5, rightLevel, state._rightPeak);
  }

  void _paintChannel(Canvas canvas, double top, double level, double peak) {
    const int totalSegments = 10;
    const double barWidth = 56.0;
    const double barHeight = 6.0;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, barWidth, barHeight),
      const Radius.circular(2),
    );
    final bgPaint = _bgPaint..color = surface.tapeWindow;
    final borderPaint = _borderPaint..color = surface.specularAt(0.12);
    canvas.drawRRect(bgRect, bgPaint);
    canvas.drawRRect(bgRect, borderPaint);

    final int activeSegCount =
        (level * totalSegments).clamp(0, totalSegments).round();
    final int peakSegIndex =
        (peak * totalSegments).clamp(1, totalSegments).round() - 1;

    for (int idx = 0; idx < totalSegments; idx++) {
      final isLit = idx < activeSegCount;
      final isPeak = idx == peakSegIndex && idx >= activeSegCount;
      final Color baseColor = idx >= 8
          ? PlayerMaterialColors.cassetteVuPeak
          : (idx >= 6
              ? PlayerMaterialColors.cassetteVuWarn
              : PlayerMaterialColors.cassetteVuNormal);

      final Color segColor = isLit
          ? baseColor
          : (isPeak
              ? baseColor.withValues(alpha: 0.95)
              : surface.specularAt(0.08));

      final segX = 2.5 + idx * 5.2;
      final segY = top + 1.0;
      final segRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(segX, segY, 4.2, 4.0),
        const Radius.circular(0.8),
      );

      if ((isLit || isPeak) && !GpuBudget.isGpuSaverActive) {
        final shadowPaint = _shadowPaint
          ..color = baseColor.withValues(alpha: 0.65);
        canvas.drawRRect(segRect, shadowPaint);
      }

      final segPaint = _segPaint..color = segColor;
      canvas.drawRRect(segRect, segPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CassetteStereoVuMeterPainter oldDelegate) {
    return oldDelegate.isPlaying != isPlaying ||
        oldDelegate.allowMotion != allowMotion ||
        oldDelegate.surface != surface;
  }
}

// ---------------------------------------------------------------------------
// Custom Painters for Cassette Aesthetics
// ---------------------------------------------------------------------------
class _CassetteScrew extends StatelessWidget {
  const _CassetteScrew();

  @override
  Widget build(BuildContext context) {
    final surface = context.playerSurfacePalette;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            surface.platterMetal,
            surface.platterMetalDeep,
            surface.platterMetalShadow,
          ],
        ),
        border: Border.all(color: surface.shadowAt(0.87), width: 0.8),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 1.2,
          color: surface.cassetteShell,
        ),
      ),
    );
  }
}

class _AcrylicReflectionPainter extends CustomPainter {
  final PlayerSurfacePalette surface;
  Paint? _cachedPaint;
  Size? _lastSize;

  _AcrylicReflectionPainter({required this.surface});

  @override
  void paint(Canvas canvas, Size size) {
    if (_cachedPaint == null || _lastSize != size) {
      _lastSize = size;
      _cachedPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surface.specularAt(0.10),
            surface.specularAt(0.02),
            surface.specularAt(0.0),
            surface.specularAt(0.06),
            surface.specularAt(0.0),
          ],
          stops: const [0.0, 0.25, 0.45, 0.65, 1.0],
        ).createShader(Offset.zero & size);
    }
    canvas.drawRect(Offset.zero & size, _cachedPaint!);
  }

  @override
  bool shouldRepaint(covariant _AcrylicReflectionPainter oldDelegate) =>
      oldDelegate.surface != surface;
}

class _TapePackRingsPainter extends CustomPainter {
  final PlayerSurfacePalette surface;

  _TapePackRingsPainter({required this.surface});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = surface.specularAt(0.07);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    for (double r = 26; r < radius - 2; r += 2.4) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TapePackRingsPainter oldDelegate) =>
      oldDelegate.surface != surface;
}

class _SpoolTeethPainter extends CustomPainter {
  final PlayerSurfacePalette surface;

  _SpoolTeethPainter({required this.surface});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = surface.highContrastInk
      ..strokeWidth = 2.0;
    final center = Offset(size.width / 2, size.height / 2);

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
  bool shouldRepaint(covariant _SpoolTeethPainter oldDelegate) =>
      oldDelegate.surface != surface;
}

class _MagneticTapePathPainter extends CustomPainter {
  final double leftTapeRadius;
  final double rightTapeRadius;
  final PlayerSurfacePalette surface;

  _MagneticTapePathPainter({
    required this.leftTapeRadius,
    required this.rightTapeRadius,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final leftCenter = Offset(73.0, h / 2);
    final rightCenter = Offset(w - 73.0, h / 2);

    final leftRoller = Offset(44.0, h - 22.0);
    final rightRoller = Offset(w - 44.0, h - 22.0);
    const rollerRadius = 5.5;

    final leftTangent = Offset(
      leftCenter.dx - leftTapeRadius * 0.96,
      leftCenter.dy + leftTapeRadius * 0.28,
    );
    final rightTangent = Offset(
      rightCenter.dx + rightTapeRadius * 0.96,
      rightCenter.dy + rightTapeRadius * 0.28,
    );

    final rollerBushingPaint = Paint()
      ..color = PlayerMaterialColors.cassettePinchGold
      ..style = PaintingStyle.fill;

    final rollerRimPaint = Paint()
      ..color = PlayerMaterialColors.cassettePinchRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final rollerAxlePaint = Paint()
      ..color = PlayerMaterialColors.cassettePinchCore
      ..style = PaintingStyle.fill;

    for (final roller in [leftRoller, rightRoller]) {
      canvas.drawCircle(roller, rollerRadius, rollerBushingPaint);
      canvas.drawCircle(roller, rollerRadius, rollerRimPaint);
      canvas.drawCircle(roller, 2.0, rollerAxlePaint);
    }

    final tapePath = Path();
    tapePath.moveTo(leftTangent.dx, leftTangent.dy);
    tapePath.lineTo(leftRoller.dx - rollerRadius + 1.0, leftRoller.dy);
    tapePath.quadraticBezierTo(
      leftRoller.dx,
      leftRoller.dy + rollerRadius,
      leftRoller.dx + rollerRadius + 4.0,
      leftRoller.dy + rollerRadius - 1.0,
    );
    tapePath.lineTo(
      rightRoller.dx - rollerRadius - 4.0,
      rightRoller.dy + rollerRadius - 1.0,
    );
    tapePath.quadraticBezierTo(
      rightRoller.dx,
      rightRoller.dy + rollerRadius,
      rightRoller.dx + rollerRadius - 1.0,
      rightRoller.dy,
    );
    tapePath.lineTo(rightTangent.dx, rightTangent.dy);

    final tapePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          PlayerMaterialColors.cassetteRibbonStart,
          PlayerMaterialColors.cassetteRibbonMid,
          PlayerMaterialColors.cassetteRibbonEnd,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final sheenPaint = Paint()
      ..color = surface.specularAt(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(tapePath, tapePaint);
    canvas.drawPath(tapePath, sheenPaint);
  }

  @override
  bool shouldRepaint(covariant _MagneticTapePathPainter oldDelegate) =>
      oldDelegate.leftTapeRadius != leftTapeRadius ||
      oldDelegate.rightTapeRadius != rightTapeRadius ||
      oldDelegate.surface != surface;
}
