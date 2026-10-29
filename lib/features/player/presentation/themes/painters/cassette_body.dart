part of '../cassette_player_theme.dart';

/// Ultra-detailed skeuomorphic cassette shell with dynamic magnetic tape transfer,
/// 3-digit mechanical rolling counter, stereo VU level meters, and acrylic glass sheen.
class _CassetteBody extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final state = props.state;
    final song = state.currentSong;
    final durationMs = state.duration.inMilliseconds;
    final positionMs = state.position.inMilliseconds;
    final progress =
        durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

    return MediaQuery.withNoTextScaling(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: isLandscape ? 270 : (isTablet ? 380 : 310),
            maxWidth: isLandscape ? 410 : (isTablet ? 560 : 450),
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
                        Color(0xFF1E212B),
                        Color(0xFF15171F),
                        Color(0xFF101218),
                      ],
                    ),
                    borderRadius: AppRadii.r20All,
                    border: Border.all(
                      color: const Color(0xFF343848),
                      width: 3.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.scrimAt(0.6),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.08),
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
                            // Cassette Label Header with Stereo VU Meters
                            _buildCassetteHeader(context, state.isPlaying),

                            const SizedBox(height: AppSpacing.s8),

                            // Center Acrylic Window with Tape Pack and Reels
                            Expanded(
                              child: _buildCenterTapeWindow(
                                context,
                                progress,
                                state.isPlaying,
                              ),
                            ),

                            const SizedBox(height: AppSpacing.s8),

                            // Bottom Label & Mechanical Head Notch
                            _buildBottomSection(context, song),
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
        color: activeColor.withValues(alpha: 0.16),
        borderRadius: AppRadii.r8All,
        border: Border.all(
          color: activeColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Side & Tape Formulation
          Column(
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
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white60,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),

          // Center: Stereo Dancing VU Meters (Isolated in RepaintBoundary for 120fps)
          RepaintBoundary(
            child: _CassetteStereoVuMeter(
              activeColor: activeColor,
              isPlaying: isPlaying,
            ),
          ),

          // Right: Pulsr Branding & EQ Specs
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.cassettePulsrTape,
                style: TextStyle(
                  fontSize: AppFontSize.tiny,
                  fontWeight: FontWeight.w900,
                  color: activeColor,
                  letterSpacing: AppTracking.wide,
                ),
              ),
              Text(
                context.l10n.cassetteEqSpec,
                style: const TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white60,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
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
    final leftTapeRadius = maxR - (progress * (maxR - minR));
    final rightTapeRadius = minR + (progress * (maxR - minR));

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0E14),
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
                color: const Color(0xFF1B1D25),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                border: Border.all(color: const Color(0xFF383C4E), width: 1.5),
              ),
              child: Center(
                child: Container(
                  width: 26,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4C526A),
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
                  Color(0xFF4A2F21),
                  Color(0xFF321D14),
                  Color(0xFF22130C),
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
              turns: spoolController,
              child: RepaintBoundary(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF0F1F5),
                    border:
                        Border.all(color: const Color(0xFFB0B4C4), width: 3),
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
                        color: Color(0xFF0C0E14),
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

  /// Bottom section: Printed track title, artist, and trapezoidal deck housing notch
  Widget _buildBottomSection(BuildContext context, SongsTableData? song) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1E212B),
        borderRadius: AppRadii.r8All,
        border: Border.all(color: const Color(0xFF2F3445), width: 1),
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
                    fontSize: 10,
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
            child: const Text(
              'NR • OFF',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                color: Colors.white54,
                letterSpacing: 0.6,
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
        border: Border.all(color: const Color(0xFF383C48), width: 1.2),
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
                color: const Color(0xFF14161C),
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
                child: Text(
                  digits[i],
                  key: ValueKey<String>('counter_${i}_${digits[i]}'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
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
    } else if (_vuController.isAnimating) {
      _vuController.stop();
      if (context.motionEnabled) {
        _vuController.animateTo(0.0, duration: context.motionMs(300));
      } else {
        _vuController.value = 0.0;
      }
    }
  }

  @override
  void didUpdateWidget(covariant _CassetteStereoVuMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      _syncVu();
    }
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
        Text(
          channel,
          style: const TextStyle(
            fontSize: 7.5,
            fontWeight: FontWeight.w800,
            color: Colors.white54,
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
                  ? const Color(0xFFFF1744)
                  : (idx >= 6
                      ? const Color(0xFFFFD600)
                      : const Color(0xFF00E676));

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
          color: const Color(0xFF1E2028),
        ),
      ),
    );
  }
}

class _AcrylicReflectionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
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

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TapePackRingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.07);

    for (double r = 26; r < radius - 2; r += 2.4) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
      ..color = const Color(0xFFC89E48)
      ..style = PaintingStyle.fill;

    final rollerRimPaint = Paint()
      ..color = const Color(0xFF4A4E62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final rollerAxlePaint = Paint()
      ..color = const Color(0xFF14161F)
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
          Color(0xFF382015),
          Color(0xFF4A2B1D),
          Color(0xFF26140D),
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
