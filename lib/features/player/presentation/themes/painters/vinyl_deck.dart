part of '../vinyl_player_theme.dart';

/// Turntable hero stage: platter, spinning record, tonearm and RPM badge.
class _VinylTurntableDeck extends StatefulWidget {
  final PlayerThemeProps props;
  final bool isTablet;
  final bool isLandscape;
  final AnimationController rotationController;
  final Animation<double> tonearmAnimation;

  const _VinylTurntableDeck({
    required this.props,
    required this.isTablet,
    required this.isLandscape,
    required this.rotationController,
    required this.tonearmAnimation,
  });

  @override
  State<_VinylTurntableDeck> createState() => _VinylTurntableDeckState();
}

class _VinylTurntableDeckState extends State<_VinylTurntableDeck> {
  // One revolution of the record carries 1.8 s at 33 1/3 RPM, so the platter is
  // dragged at the speed the disc actually spins.
  final PlatterScrubController _scrub = PlatterScrubController(
    secondsPerTurn: PlatterScrubController.vinylSecondsPerTurn,
  );

  @override
  void dispose() {
    _scrub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.props;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    // The record label and the ring framing it must share one radius, or a
    // Theme Studio radius would round the clip but leave the frame circular.
    final artRadius = resolveCustomRadius(context, 999);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: context.isLandscape ? 300 : (context.isTablet ? 480 : 390),
          maxWidth: context.isLandscape ? 320 : (context.isTablet ? 500 : 410),
        ),
        child: AspectRatio(
          aspectRatio: 1.04,
          child: LayoutBuilder(
            builder: (context, deckConstraints) {
              final w = deckConstraints.maxWidth;
              final h = deckConstraints.maxHeight;

              // Vinyl record geometry
              final vinylSize = w * 0.70;
              final vinylLeft = w * 0.05;
              final vinylTop = (h - vinylSize) / 2;

              // Tonearm geometry
              final pivotOffset = Offset(w * 0.81, h * 0.19);
              final armLength = w * 0.46;

              // The disc content never changes while spinning, so build it once
              // and let the compositor rotate a cached layer instead of
              // repainting grooves and artwork on every animation tick.
              final vinylDisc = RepaintBoundary(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PlayerMaterialColors.recordBase,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.scrimAt(0.5),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: _VinylGroovesPainter(activeColor: activeColor),
                    child: Center(
                      // Center Album Artwork
                      child: Container(
                        width: vinylSize * 0.44,
                        height: vinylSize * 0.44,
                        decoration: BoxDecoration(
                          borderRadius: AppRadii.circular(artRadius),
                          border: Border.all(
                            color: AppColors.specularAt(0.3),
                            width: 1.5,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (song != null)
                              CachedArtwork(
                                id: song.id,
                                albumId: song.albumId,
                                remoteUrl:
                                    song.remoteArtworkUrl ?? song.artworkUri,
                                type: ArtworkType.AUDIO,
                                size: vinylSize * 0.44,
                                borderRadius: artRadius,
                                highQuality: true,
                                fallbackIcon: Icons.music_note_rounded,
                              ),
                            // Center Spindle Hole
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.grey.shade400,
                                    Colors.grey.shade800,
                                    AppColors.darkSurface,
                                  ],
                                  stops: const [0.0, 0.6, 1.0],
                                ),
                                border: Border.all(
                                  color: Colors.white30,
                                  width: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );

              // A tap on the deck toggles lyrics like every other theme — the
              // transport owns play/pause — so the stage describes itself as an
              // image instead of posing as a button. The platter below is the
              // deck's single control: an analog scrub published as a slider.
              return Semantics(
                container: true,
                image: true,
                label: playerArtworkSemanticLabel(context, song),
                hint: '${context.l10n.gestureArtworkDoubleTapTitle} — '
                    '${context.l10n.lyrics}',
                child: PlayerGestureScope(
                  behavior: HitTestBehavior.deferToChild,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          PlayerMaterialColors.deckGradStart,
                          PlayerMaterialColors.deckGradMid,
                          PlayerMaterialColors.deckGradEnd,
                        ],
                      ),
                      borderRadius: AppRadii.r22All,
                      border: Border.all(
                        color: PlayerMaterialColors.cassetteShellBorder,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.scrim,
                          blurRadius: 28,
                          spreadRadius: 2,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.08),
                          blurRadius: 32,
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 1. Plinth Studio Branding & Active Status
                        PositionedDirectional(
                          top: 14,
                          start: 16,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: state.isPlaying
                                      ? activeColor
                                      : Colors.white24,
                                  boxShadow: state.isPlaying
                                      ? [
                                          BoxShadow(
                                            color: activeColor.withValues(
                                                alpha: 0.8),
                                            blurRadius: 6,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s6),
                              ExcludeSemantics(
                                child: Text(
                                  context.l10n.vinylDirectDrive,
                                  style: const TextStyle(
                                    fontSize: AppFontSize.micro,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: AppTracking.wide,
                                    color: Colors.white38,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 2. Platter Strobe Rim
                        PositionedDirectional(
                          start: vinylLeft - 4,
                          top: vinylTop - 4,
                          width: vinylSize + 8,
                          height: vinylSize + 8,
                          child: CustomPaint(
                            painter: _PlatterStrobePainter(
                              activeColor: activeColor,
                              isPlaying: state.isPlaying,
                            ),
                          ),
                        ),

                        // 3. Spinning Vinyl Record & Platter Scrubbing
                        PositionedDirectional(
                          start: vinylLeft,
                          top: vinylTop,
                          width: vinylSize,
                          height: vinylSize,
                          child: PlatterScrubSemantics(
                            cubit: cubit,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (d) =>
                                  _scrub.start(d.localPosition, vinylSize),
                              onPanUpdate: (d) =>
                                  _scrub.update(d.localPosition, vinylSize),
                              onPanEnd: (_) {
                                final current = widget.props.cubit.state;
                                _scrub.end(
                                  position: current.position,
                                  duration: current.duration,
                                  onSeek: widget.props.cubit.seek,
                                );
                              },
                              onPanCancel: _scrub.cancel,
                              child: RepaintBoundary(
                                child: AnimatedBuilder(
                                  // The drag phase and the spin phase are one
                                  // transform, so both are merged listenables.
                                  animation: Listenable.merge(
                                    [widget.rotationController, _scrub],
                                  ),
                                  child: vinylDisc,
                                  builder: (context, child) {
                                    final totalPhase =
                                        (widget.rotationController.value +
                                                _scrub.turnOffset) %
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
                        ),

                        // 3b. Anchored specular sheen (does not spin with the
                        // record; painted once instead of every frame).
                        PositionedDirectional(
                          start: vinylLeft,
                          top: vinylTop,
                          width: vinylSize,
                          height: vinylSize,
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _VinylSheenPainter(
                                  labelRatio: 0.44,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 3c. Real-time analog scrub delta pill indicator
                        PositionedDirectional(
                          start: vinylLeft,
                          top: vinylTop,
                          width: vinylSize,
                          height: vinylSize,
                          child: IgnorePointer(
                            child: Center(
                              child: PlatterScrubPill(
                                controller: _scrub,
                                activeColor: activeColor,
                              ),
                            ),
                          ),
                        ),

                        // 4. Animated Tonearm Assembly Layer
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child:
                                  BlocSelector<PlayerCubit, PlayerState, int>(
                                selector: (s) => s.duration.inMilliseconds > 0
                                    ? ((s.position.inMilliseconds /
                                                s.duration.inMilliseconds) *
                                            120)
                                        .round()
                                    : 0,
                                builder: (context, step) {
                                  final progress =
                                      (step / 120.0).clamp(0.0, 1.0);
                                  final playAngle = 0.35 + (progress * 0.14);
                                  return AnimatedBuilder(
                                    animation: widget.tonearmAnimation,
                                    builder: (context, child) {
                                      final currentAngle = -0.06 +
                                          ((playAngle - (-0.06)) *
                                              widget.tonearmAnimation.value) +
                                          _scrub.tonearmSway;

                                      return CustomPaint(
                                        painter: _TonearmPainter(
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

                        // 5. Bottom Plinth RPM Badge (33⅓ RPM / Standby - Interactive)
                        PositionedDirectional(
                          bottom: 12,
                          start: 14,
                          // A printed badge, not a hidden shortcut: tapping the
                          // deck means lyrics on every theme, and the speed
                          // picker lives in the dock where it has a label and a
                          // 48 dp target. A tap handler here swallowed the
                          // corner of the stage without advertising itself.
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s8,
                                  vertical: AppSpacing.xxs),
                              decoration: BoxDecoration(
                                color: state.isPlaying
                                    ? activeColor.withValues(alpha: 0.15)
                                    : PlayerMaterialColors.recordSheenCenter,
                                borderRadius: AppRadii.r6All,
                                border: Border.all(
                                  color: state.isPlaying
                                      ? activeColor.withValues(alpha: 0.5)
                                      : PlayerMaterialColors.recordRim,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    state.isPlaying
                                        ? Icons.speed_rounded
                                        : Icons.pause_circle_outline_rounded,
                                    size: 11,
                                    color: state.isPlaying
                                        ? activeColor
                                        : Colors.white38,
                                  ),
                                  const SizedBox(width: AppSpacing.xxs),
                                  // Painted plinth legends stay out of the
                                  // accessibility tree: the stage node names the
                                  // track, and "STANDBY" bleeding into it made
                                  // the deck read as a second status line.
                                  ExcludeSemantics(
                                    child: Text(
                                      state.isPlaying
                                          ? context.l10n.vinylSpeedRpm
                                          : context.l10n.dspStandby,
                                      style: TextStyle(
                                        fontSize: AppFontSize.caption,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: AppTracking.overline,
                                        color: state.isPlaying
                                            ? activeColor
                                            : Colors.white38,
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
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
