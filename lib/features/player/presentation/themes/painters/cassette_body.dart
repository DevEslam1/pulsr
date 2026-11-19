part of '../cassette_player_theme.dart';

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
      // Detents are counted from the drag origin, so the first click lands
      // after 5 s of scrub in either direction rather than on an arbitrary
      // multiple of five seconds in the track's timeline.
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
    final state = widget.props.state;
    final song = state.currentSong;
    final durationMs = state.duration.inMilliseconds;
    final progress = durationMs > 0
        ? (state.position.inMilliseconds / durationMs).clamp(0.0, 1.0)
        : 0.0;
    // While the finger is down the tape packs and the mechanical counter must
    // show where the seek will land, not where playback currently is.
    final displayProgress = _isScrubbing && durationMs > 0
        ? (_scrubTargetMs! / durationMs).clamp(0.0, 1.0)
        : progress;

    // The shell is decorative: it prints no information that is not already
    // in the chrome (PlayerTrackHeader announces title, artist and transport
    // state), so the fixed 450x296 artwork box may legitimately ignore text
    // scaling. The scrub pill is transient feedback mirrored by the slider
    // node below, not a reading surface.
    return MediaQuery.withNoTextScaling(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: widget.isLandscape ? 270 : (widget.isTablet ? 380 : 310),
            maxWidth: widget.isLandscape ? 410 : (widget.isTablet ? 560 : 450),
          ),
          child: AspectRatio(
            aspectRatio: 1.52,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 450,
                height: 450 / 1.52,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        PlayerMaterialColors.cassetteBodyTop,
                        PlayerMaterialColors.cassetteBodyMid,
                        PlayerMaterialColors.circleSpindle,
                      ],
                    ),
                    borderRadius: AppRadii.r20All,
                    border: Border.all(
                      color: PlayerMaterialColors.cassetteBodyBorder,
                      width: 3.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.scrimAt(0.6),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                      BoxShadow(
                        color: widget.activeColor.withValues(alpha: 0.08),
                        blurRadius: 36,
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
                            // Cassette Label Header with Stereo VU Meters.
                            // Label print is decorative: the deck's semantics
                            // node already announces the track and its state.
                            ExcludeSemantics(
                              child:
                                  _buildCassetteHeader(context, state.isPlaying),
                            ),

                            const SizedBox(height: AppSpacing.s8),

                            // Center Acrylic Window with Tape Pack and Reels
                            Expanded(
                              child: _buildScrubSurface(
                                progress: displayProgress,
                                isPlaying: state.isPlaying,
                              ),
                            ),

                            const SizedBox(height: AppSpacing.s8),

                            // Bottom Label & Mechanical Head Notch (decorative
                            // print - excluded from semantics, see above).
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
    );
  }

  /// Upper label band with tape format badges and dual stereo dancing VU meters
  Widget _buildCassetteHeader(BuildContext context, bool isPlaying) {
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
                    style: const TextStyle(
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: AppTracking.wide,
                    ),
                  ),
                  Text(
                    context.l10n.cassetteTapeType,
                    style: const TextStyle(
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w700,
                      color: Colors.white60,
                      letterSpacing: 0.8,
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
                    style: const TextStyle(
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w700,
                      color: Colors.white60,
                      letterSpacing: 0.8,
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
  ///
  /// The shell used to be dead decoration: progress only moved tape-pack radii
  /// and a three-digit counter, so there was no way to seek from the stage.
  /// The well is the one wide, flat surface on the cassette, which makes it the
  /// natural scrub strip. It competes with the stage's next/previous swipe only
  /// for horizontal pointers, and the inner recognizer wins that arena.
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
          // Keeps the tape well its own node. Without the boundary the shell's
          // "Now playing …" description merges into the slider, and the reader
          // announces a seek bar whose label is the whole deck.
          container: true,
          slider: true,
          label: context.l10n.seekLabel,
          value: seekLabel(state.position),
          increasedValue: seekLabel(clampSeek(const Duration(seconds: 10))),
          decreasedValue: seekLabel(clampSeek(const Duration(seconds: -10))),
          onIncrease: () => _seekBy(const Duration(seconds: 10)),
          onDecrease: () => _seekBy(const Duration(seconds: -10)),
          // The well's painted internals (counter digits, ruler ticks) are
          // decoration; this is the only node assistive tech should reach.
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
                  Center(child: IgnorePointer(child: _buildScrubDeltaPill())),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Delta read-out while scrubbing, reusing the rounded dark pill with an
  /// active-colour rim that the vinyl and CD platters show, so all the
  /// skeuomorphic themes speak the same scrub language.
  Widget _buildScrubDeltaPill() {
    // Rounded to tenths first so a backwards drag reads "-12.3s" and never
    // "-0.0s" when the finger barely moves.
    final deltaTenths = ((_scrubTargetMs! - _scrubBaseMs) / 100).round();
    final deltaText = (deltaTenths / 10).toStringAsFixed(1);
    final label = deltaTenths > 0 ? '+${deltaText}s' : '${deltaText}s';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
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
        style: const TextStyle(
          fontSize: AppFontSize.label,
          fontWeight: FontWeight.w800,
          color: Colors.white,
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
    // Tape pack radius calculation (Tape transfers smoothly from Left to Right)
    // Left spool starts full (r=42) and drains to empty hub (r=26)
    // Right spool starts empty hub (r=26) and fills to full (r=42)
    const double minR = 26.0;
    const double maxR = 43.0;
    final leftTapeRadius =
        math.sqrt(maxR * maxR * (1.0 - progress) + minR * minR * progress);
    final rightTapeRadius =
        math.sqrt(minR * minR * (1.0 - progress) + maxR * maxR * progress);

    return Container(
      decoration: BoxDecoration(
        color: PlayerMaterialColors.cassetteWell,
        borderRadius: AppRadii.r14All,
        border: Border.all(color: Colors.white24, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 8,
            offset: Offset(0, 3),
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
              painter: _AcrylicReflectionPainter(),
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
                    width: 1.5),
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
                // Left Spool Pack (Draining)
                _buildReelPack(
                  tapeRadius: leftTapeRadius,
                  isLeft: true,
                ),

                // Center Ruler Markings on Acrylic
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    7,
                    (i) => Container(
                      width: i == 3 ? 24 : 14,
                      height: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 2.2),
                      color: i == 3 ? Colors.white54 : Colors.white24,
                    ),
                  ),
                ),

                // Right Spool Pack (Accumulating)
                _buildReelPack(
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
              gradient: RadialGradient(
                colors: const [
                  PlayerMaterialColors.cassetteTapeOuter,
                  PlayerMaterialColors.cassetteTapeMid,
                  PlayerMaterialColors.cassetteTapeInner,
                ],
                stops: const [0.35, 0.75, 1.0],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black87,
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: CustomPaint(
              painter: _TapePackRingsPainter(),
            ),
          ),

          // Rotating White Spool Hub with Teeth (Isolated in outer + inner RepaintBoundary)
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
                        color: PlayerMaterialColors.cassetteReelRim, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: PlayerMaterialColors.cassetteWell,
                        shape: BoxShape.circle,
                      ),
                      child: CustomPaint(painter: _SpoolTeethPainter()),
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
  ///
  /// The title/artist line is the sticker a listener would have written on the
  /// shell, so it stays purely cosmetic: the call site wraps this whole section
  /// in [ExcludeSemantics] and PlayerTrackHeader already announces the same
  /// track. That is also why the live song text is allowed to sit inside the
  /// shell's no-text-scaling MediaQuery - nothing here is the only copy of a
  /// piece of information.
  Widget _buildBottomSection(BuildContext context, SongsTableData? song) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: PlayerMaterialColors.cassetteBodyTop,
        borderRadius: AppRadii.r8All,
        border: Border.all(
            color: PlayerMaterialColors.cassetteCapstanBorder, width: 1),
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
                  style: const TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  song?.artist ?? 'ANALOG MASTER AUDIO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: Colors.white60,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: AppRadii.r4All,
              border: Border.all(color: Colors.white12),
            ),
            child: const ExcludeSemantics(
              child: Text(
                'NR • OFF',
                style: TextStyle(
                  fontSize: AppFontSize.tiny,
                  fontWeight: FontWeight.w800,
                  color: Colors.white54,
                  letterSpacing: 0.6,
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
    // AUDIT-FIX: Map progress to full 3-digit counter range 0..999
    final count = (progress * 999).clamp(0, 999).toInt();
    final digits = count.toString().padLeft(3, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: AppRadii.r4All,
        border: Border.all(
            color: PlayerMaterialColors.cassetteHeadBorder, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 4,
            offset: Offset(0, 1),
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
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncVu();
  }

  void _syncVu() {
    final shouldSpin = widget.isPlaying && context.motionEnabled;
    if (shouldSpin) {
      if (!_vuController.isAnimating) {
        _vuController.repeat(reverse: true);
      }
    } else {
      if (_vuController.isAnimating) {
        _vuController.stop();
      }
      if (!context.motionEnabled) {
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
    return AnimatedBuilder(
      animation: _vuController,
      builder: (context, _) {
        final val = _vuController.value;
        final theta = val * 2 * math.pi;

        // Common rhythmic beat foundation (L and R pulse together)
        final beatBase =
            math.sin(theta).abs() * 0.45 + (math.sin(theta * 2.0).abs() * 0.22);

        // Independent harmonic stereo components at prime ratios
        final leftHarmonic = math.sin(theta * 3.0 + 0.4).abs() * 0.18 +
            math.cos(theta * 7.0).abs() * 0.08;
        final rightHarmonic = math.cos(theta * 5.0 - 0.5).abs() * 0.18 +
            math.sin(theta * 11.0).abs() * 0.08;

        final leftLevel = widget.isPlaying
            ? (0.16 + beatBase + leftHarmonic).clamp(0.08, 0.98)
            : 0.08;
        final rightLevel = widget.isPlaying
            ? (0.16 + beatBase + rightHarmonic).clamp(0.08, 0.98)
            : 0.08;

        _updatePeaks(leftLevel, rightLevel);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildVuBar('L', leftLevel, _leftPeak),
            const SizedBox(height: 2.5),
            _buildVuBar('R', rightLevel, _rightPeak),
          ],
        );
      },
    );
  }

  Widget _buildVuBar(String channel, double level, double peak) {
    const int totalSegments = 10;
    final int activeSegCount =
        (level * totalSegments).clamp(0, totalSegments).round();
    final int peakSegIndex =
        (peak * totalSegments).clamp(1, totalSegments).round() - 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Text(
            channel,
            style: const TextStyle(
              fontSize: AppFontSize.nano,
              fontWeight: FontWeight.w800,
              color: Colors.white54,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 1.0),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: AppRadii.circular(2),
            border: Border.all(color: Colors.white12, width: 0.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(totalSegments, (idx) {
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
                      : Colors.white.withValues(alpha: 0.08));

              return Container(
                width: 4.2,
                height: 4.0,
                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                decoration: BoxDecoration(
                  color: segColor,
                  borderRadius: AppRadii.circular(0.8),
                  boxShadow: (isLit || isPeak)
                      ? [
                          BoxShadow(
                            color: baseColor.withValues(alpha: 0.65),
                            blurRadius: 2.5,
                          ),
                        ]
                      : null,
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Custom Painters for Cassette Aesthetics
// ---------------------------------------------------------------------------
class _CassetteScrew extends StatelessWidget {
  const _CassetteScrew();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.grey.shade400,
            Colors.grey.shade700,
            Colors.grey.shade900,
          ],
        ),
        border: Border.all(color: Colors.black87, width: 0.8),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 1.2,
          color: PlayerMaterialColors.cassetteShell,
        ),
      ),
    );
  }
}

class _AcrylicReflectionPainter extends CustomPainter {
  Paint? _cachedPaint;
  Size? _lastSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (_cachedPaint == null || _lastSize != size) {
      _lastSize = size;
      _cachedPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.02),
            Colors.transparent,
            Colors.white.withValues(alpha: 0.06),
            Colors.transparent,
          ],
          stops: const [0.0, 0.25, 0.45, 0.65, 1.0],
        ).createShader(Offset.zero & size);
    }
    canvas.drawRect(Offset.zero & size, _cachedPaint!);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TapePackRingsPainter extends CustomPainter {
  static final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6
    ..color = Colors.white.withValues(alpha: 0.07);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    for (double r = 26; r < radius - 2; r += 2.4) {
      canvas.drawCircle(center, r, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SpoolTeethPainter extends CustomPainter {
  static final Paint _paint = Paint()
    ..color = Colors.white
    ..strokeWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
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
      canvas.drawLine(p1, p2, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MagneticTapePathPainter extends CustomPainter {
  final double leftTapeRadius;
  final double rightTapeRadius;

  _MagneticTapePathPainter({
    required this.leftTapeRadius,
    required this.rightTapeRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Spool centers (matching Row padding 28 + spool radius 45)
    final leftCenter = Offset(73.0, h / 2);
    final rightCenter = Offset(w - 73.0, h / 2);

    // Guide roller centers near lower corners
    final leftRoller = Offset(44.0, h - 22.0);
    final rightRoller = Offset(w - 44.0, h - 22.0);
    const rollerRadius = 5.5;

    // Outer tangent start on left tape pack
    final leftTangent = Offset(
      leftCenter.dx - leftTapeRadius * 0.96,
      leftCenter.dy + leftTapeRadius * 0.28,
    );

    // Outer tangent end on right tape pack
    final rightTangent = Offset(
      rightCenter.dx + rightTapeRadius * 0.96,
      rightCenter.dy + rightTapeRadius * 0.28,
    );

    // --- 1. Guide Rollers (Metallic Bushings & Pins) ---
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

    // --- 2. Magnetic Tape Ribbon Path ---
    final tapePath = Path();
    tapePath.moveTo(leftTangent.dx, leftTangent.dy);
    // Line down to left guide roller outer edge
    tapePath.lineTo(leftRoller.dx - rollerRadius + 1.0, leftRoller.dy);
    // Wrap around bottom of left roller
    tapePath.quadraticBezierTo(
      leftRoller.dx,
      leftRoller.dy + rollerRadius,
      leftRoller.dx + rollerRadius + 4.0,
      leftRoller.dy + rollerRadius - 1.0,
    );
    // Straight across the bottom read-head aperture notch
    tapePath.lineTo(
      rightRoller.dx - rollerRadius - 4.0,
      rightRoller.dy + rollerRadius - 1.0,
    );
    // Wrap around bottom of right roller
    tapePath.quadraticBezierTo(
      rightRoller.dx,
      rightRoller.dy + rollerRadius,
      rightRoller.dx + rollerRadius - 1.0,
      rightRoller.dy,
    );
    // Angled up to right tape pack outer tangent
    tapePath.lineTo(rightTangent.dx, rightTangent.dy);

    // Ferric oxide dark magnetic tape body
    final tapePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          PlayerMaterialColors.cassetteRibbonStart,
          PlayerMaterialColors.cassetteRibbonMid,
          PlayerMaterialColors.cassetteRibbonEnd,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Specular sheen highlight along the tape edge
    final sheenPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(tapePath, tapePaint);
    canvas.drawPath(tapePath, sheenPaint);
  }

  @override
  bool shouldRepaint(covariant _MagneticTapePathPainter oldDelegate) =>
      oldDelegate.leftTapeRadius != leftTapeRadius ||
      oldDelegate.rightTapeRadius != rightTapeRadius;
}
