part of '../cd_player_theme.dart';

/// CD Turntable Stage: Rotating iridescent CD disc with song cover,
/// animated tonearm stick, and interactive gestures.
class _CdTurntableStage extends StatefulWidget {
  final PlayerThemeProps props;
  final bool isTablet;
  final bool isLandscape;
  final AnimationController rotationController;
  final Animation<double> tonearmAnimation;

  const _CdTurntableStage({
    required this.props,
    required this.isTablet,
    required this.isLandscape,
    required this.rotationController,
    required this.tonearmAnimation,
  });

  @override
  State<_CdTurntableStage> createState() => _CdTurntableStageState();
}

class _CdTurntableStageState extends State<_CdTurntableStage> {
  double _scrubTurns = 0.0;
  double? _lastDragAngle;
  double _tonearmSway = 0.0;
  bool _isScrubbing = false;

  void _onPlatterPanStart(DragStartDetails details, double cdSize) {
    final center = Offset(cdSize / 2, cdSize / 2);
    _lastDragAngle = math.atan2(
      details.localPosition.dy - center.dy,
      details.localPosition.dx - center.dx,
    );
    setState(() {
      _isScrubbing = true;
      _scrubTurns = 0.0;
      _tonearmSway = 0.0;
    });
  }

  void _onPlatterPanUpdate(DragUpdateDetails details, double cdSize) {
    final center = Offset(cdSize / 2, cdSize / 2);
    final currentAngle = math.atan2(
      details.localPosition.dy - center.dy,
      details.localPosition.dx - center.dx,
    );
    if (_lastDragAngle != null) {
      double delta = currentAngle - _lastDragAngle!;
      if (delta > math.pi) delta -= 2 * math.pi;
      if (delta < -math.pi) delta += 2 * math.pi;

      final prevTurn12 = (_scrubTurns * 12).floor();
      _scrubTurns += delta / (2 * math.pi);
      final newTurn12 = (_scrubTurns * 12).floor();
      if (prevTurn12 != newTurn12) {
        PulsrHaptics.selection();
      }

      setState(() {
        _tonearmSway = (delta * 0.15).clamp(-0.06, 0.06);
      });
    }
    _lastDragAngle = currentAngle;
  }

  void _onPlatterPanEnd(int durationMs, int positionMs) {
    if (_isScrubbing && durationMs > 0) {
      // 1 turn ≈ 4 seconds of playback scrub
      final scrubDeltaMs = (_scrubTurns * 4000).round();
      final targetMs = (positionMs + scrubDeltaMs).clamp(0, durationMs);
      widget.props.cubit.seek(Duration(milliseconds: targetMs));
    }
    setState(() {
      _isScrubbing = false;
      _lastDragAngle = null;
      _scrubTurns = 0.0;
      _tonearmSway = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.props;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final (:nowPlayingDoubleTap, :nowPlayingArtworkSwipe) = context.select<
        SettingsCubit,
        ({
          NowPlayingDoubleTapAction nowPlayingDoubleTap,
          NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
        })>((c) => (
          nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
          nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
        ));

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: context.isLandscape ? 310 : (context.isTablet ? 490 : 400),
          maxWidth: context.isLandscape ? 330 : (context.isTablet ? 510 : 420),
        ),
        child: AspectRatio(
          aspectRatio: 1.02,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;

              // CD disc geometry (positioned slightly left to balance the tonearm on the right)
              final cdSize = w * 0.74;
              final cdLeft = w * 0.05;
              final cdTop = (h - cdSize) / 2;

              // Tonearm stick geometry (pivot at top-right, stick extends down-left onto CD)
              final pivotOffset = Offset(w * 0.83, h * 0.16);
              final armLength = w * 0.48;

              // Cache the disc raster once; rotation only moves the layer.
              final cdDisc = RepaintBoundary(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // CD Optical Substrate Surface & Iridescent Sheen
                    CustomPaint(
                      size: Size(cdSize, cdSize),
                      painter: _CdDiscPainter(activeColor: activeColor),
                    ),

                    // Center Circular Album Artwork Label
                    Container(
                      width: cdSize * 0.44,
                      height: cdSize * 0.44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: -1,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: song != null
                          ? CachedArtwork(
                              id: song.id,
                              albumId: song.albumId,
                              remoteUrl:
                                  song.remoteArtworkUrl ?? song.artworkUri,
                              type: ArtworkType.AUDIO,
                              size: cdSize * 0.44,
                              borderRadius: 999,
                              highQuality: true,
                              fallbackIcon: Icons.music_note_rounded,
                            )
                          : const Icon(
                              Icons.album_rounded,
                              size: 48,
                              color: Colors.white38,
                            ),
                    ),

                    // Inner Translucent Clamping Hub Ring
                    Container(
                      width: cdSize * 0.20,
                      height: cdSize * 0.20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1.0,
                        ),
                      ),
                    ),

                    // Center Metallic Spindle Hub Ring & Spindle Hole
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.grey.shade300,
                            Colors.grey.shade600,
                            const Color(0xFF141720),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Center(
                        // Spindle center hole
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0C0D11),
                            border: Border.all(
                              color: Colors.white24,
                              width: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );

              return Semantics(
                button: true,
                label: state.isPlaying ? context.l10n.pause : context.l10n.play,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => cubit.togglePlayPause(),
                  onDoubleTap: () {
                    switch (nowPlayingDoubleTap) {
                      case NowPlayingDoubleTapAction.toggleFavorite:
                        final s = state.currentSong;
                        if (s != null) cubit.toggleFavorite(s.id);
                        break;
                      case NowPlayingDoubleTapAction.toggleLyrics:
                        cubit.toggleLyricsVisibility();
                        break;
                      case NowPlayingDoubleTapAction.none:
                        break;
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    if (nowPlayingArtworkSwipe ==
                            NowPlayingArtworkSwipeAction.nextPrev &&
                        details.primaryVelocity != null) {
                      if (details.primaryVelocity! < -200) {
                        cubit.next();
                      } else if (details.primaryVelocity! > 200) {
                        cubit.previous();
                      }
                    }
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 0. Fluorescent Retro CD Player VFD/LCD Track HUD Display
                      PositionedDirectional(
                        top: 2,
                        start: 6,
                        child: _CdOpticalDisplayHud(
                          props: props,
                          activeColor: activeColor,
                        ),
                      ),

                      // 1. Soft ambient glow behind the CD disc
                      PositionedDirectional(
                        start: cdLeft - 8,
                        top: cdTop - 8,
                        width: cdSize + 16,
                        height: cdSize + 16,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: activeColor.withValues(alpha: 0.28),
                                blurRadius: 42,
                                spreadRadius: 4,
                              ),
                              BoxShadow(
                                color: AppColors.scrimAt(0.55),
                                blurRadius: 28,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 2. Rotating Compact Disc with central Album Artwork & Platter Scrubbing
                      PositionedDirectional(
                        start: cdLeft,
                        top: cdTop,
                        width: cdSize,
                        height: cdSize,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (d) => _onPlatterPanStart(d, cdSize),
                          onPanUpdate: (d) => _onPlatterPanUpdate(d, cdSize),
                          onPanEnd: (_) {
                            final current = widget.props.cubit.state;
                            _onPlatterPanEnd(
                              current.duration.inMilliseconds,
                              current.position.inMilliseconds,
                            );
                          },
                          onPanCancel: () {
                            setState(() {
                              _isScrubbing = false;
                              _lastDragAngle = null;
                              _scrubTurns = 0.0;
                              _tonearmSway = 0.0;
                            });
                          },
                          child: RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: widget.rotationController,
                              child: cdDisc,
                              builder: (context, child) {
                                final totalPhase =
                                    (widget.rotationController.value +
                                            _scrubTurns) %
                                        1.0;
                                return Transform.rotate(
                                  angle: totalPhase * 2 * math.pi,
                                  child: child,
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      // 2b. Anchored specular flare painted once above the
                      // spinning disc (clipped away from the artwork label).
                      PositionedDirectional(
                        start: cdLeft,
                        top: cdTop,
                        width: cdSize,
                        height: cdSize,
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _CdFlarePainter(labelRatio: 0.44),
                            ),
                          ),
                        ),
                      ),

                      // 3. Animated Tonearm "Stick" Assembly
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: BlocSelector<PlayerCubit, PlayerState, int>(
                              selector: (s) => s.duration.inMilliseconds > 0
                                  ? ((s.position.inMilliseconds /
                                              s.duration.inMilliseconds) *
                                          120)
                                      .round()
                                  : 0,
                              builder: (context, step) {
                                final progress = (step / 120.0).clamp(0.0, 1.0);
                                // When playing: angle tracks from outer track (0.30 rad)
                                // inward to inner track (0.44 rad) across the song duration!
                                final playAngle = 0.30 + (progress * 0.14);
                                const parkedAngle = -0.12;

                                return AnimatedBuilder(
                                  animation: widget.tonearmAnimation,
                                  builder: (context, child) {
                                    final currentAngle = parkedAngle +
                                        ((playAngle - parkedAngle) *
                                            widget.tonearmAnimation.value) +
                                        _tonearmSway;

                                    return CustomPaint(
                                      painter: _CdTonearmPainter(
                                        pivot: pivotOffset,
                                        angle: currentAngle,
                                        activeColor: activeColor,
                                        armLength: armLength,
                                        liftProgress:
                                            widget.tonearmAnimation.value,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fluorescent Retro Optical CD HUD Display
// ---------------------------------------------------------------------------
class _CdOpticalDisplayHud extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;

  const _CdOpticalDisplayHud({
    required this.props,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final trackNum = (state.currentIndex >= 0 ? state.currentIndex + 1 : 1)
        .toString()
        .padLeft(2, '0');
    final isPlaying = state.isPlaying;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF141824).withValues(alpha: 0.92),
            const Color(0xFF0B0E15).withValues(alpha: 0.90),
          ],
        ),
        borderRadius: AppRadii.r8All,
        border: Border.all(
          color: activeColor.withValues(alpha: isPlaying ? 0.48 : 0.30),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Blue optical laser status dot
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPlaying ? Colors.cyanAccent : Colors.white24,
              boxShadow: isPlaying
                  ? [
                      const BoxShadow(
                        color: Colors.cyanAccent,
                        blurRadius: 6,
                        spreadRadius: 1.5,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),

          // Track Number Matrix
          Text(
            context.l10n.cdTrackNumber(trackNum),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: isPlaying ? Colors.cyanAccent : Colors.white70,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 8),

          Container(
            width: 1,
            height: 10,
            color: Colors.white24,
          ),
          const SizedBox(width: 8),

          // AUDIT-FIX: Dynamic audio specs from current song metadata with lossy & CD-DA fallback
          Text(
            _formatAudioSpec(state.currentSong),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.white60,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatAudioSpec(SongsTableData? song) {
    if (song == null) return '44.1kHz • 16-BIT CD-DA';
    final sampleRate = song.sampleRate;
    final bitDepth = song.bitDepth;
    final codec = song.codec?.toUpperCase();
    final bitrate = song.bitrateKbps;

    final isLossy = codec != null &&
        (codec.contains('MP3') ||
            codec.contains('AAC') ||
            codec.contains('OGG') ||
            codec.contains('OPUS') ||
            codec.contains('M4A'));

    if (isLossy && bitrate != null && bitrate > 0) {
      return '$codec • $bitrate kbps';
    } else if (sampleRate != null && bitDepth != null) {
      return '${(sampleRate / 1000).toStringAsFixed(1)}kHz • $bitDepth-BIT';
    } else if (sampleRate != null) {
      return '${(sampleRate / 1000).toStringAsFixed(1)}kHz • CD-DA';
    } else if (codec != null && bitrate != null && bitrate > 0) {
      return '$codec • $bitrate kbps';
    }
    return '44.1kHz • 16-BIT CD-DA';
  }
}
