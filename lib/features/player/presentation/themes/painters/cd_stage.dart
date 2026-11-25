part of '../cd_player_theme.dart';

/// CD hero stage: an iridescent compact disc seated inside a Y2K transparent
/// polycarbonate jewel case with a vertical ribbed acrylic hinge spine, molded
/// booklet clips, spider hub, and an optical pickup sled that glides along the
/// bottom rail.
class _CdJewelStage extends StatefulWidget {
  final PlayerThemeProps props;
  final bool isTablet;
  final bool isLandscape;
  final AnimationController rotationController;
  final Animation<double> pickupAnimation;
  final Animation<double> glossAnimation;
  final bool customGlow;

  const _CdJewelStage({
    required this.props,
    required this.isTablet,
    required this.isLandscape,
    required this.rotationController,
    required this.pickupAnimation,
    required this.glossAnimation,
    this.customGlow = false,
  });

  @override
  State<_CdJewelStage> createState() => _CdJewelStageState();
}

class _CdJewelStageState extends State<_CdJewelStage> {
  // The CD deck scrubs coarser than the record: one revolution carries 4 s.
  final PlatterScrubController _scrub = PlatterScrubController(
    secondsPerTurn: PlatterScrubController.cdSecondsPerTurn,
  );

  @override
  void didUpdateWidget(covariant _CdJewelStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.props.state.currentSong?.id !=
        widget.props.state.currentSong?.id) {
      _scrub.cancel();
    }
  }

  @override
  void dispose() {
    _scrub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = context.playerSurfacePalette;
    final p = context.palette;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final props = widget.props;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;

    // Disc label and the ring framing it share one radius; jewel case corners
    // also honour Theme Studio custom radius within realistic acrylic bounds.
    final artRadius = resolveCustomRadius(context, 999);
    final caseRadius = resolveCustomRadius(context, AppRadii.r14).clamp(
      AppRadii.r4,
      AppRadii.r28,
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: widget.isLandscape ? 300 : (widget.isTablet ? 460 : 380),
          maxWidth: widget.isLandscape ? 330 : (widget.isTablet ? 500 : 410),
        ),
        child: AspectRatio(
          aspectRatio: 1.08,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;

              // Authentic CD jewel-case geometry: translucent ribbed hinge spine
              // occupies ~10.5% on the leading edge, recessed polycarbonate tray
              // fills the remaining body, and optical pickup sled rides along
              // the tray lip below the disc.
              final spineWidth = (w * 0.105).clamp(18.0, 38.0);
              final trayRect = Rect.fromLTRB(
                spineWidth + w * 0.025,
                h * 0.045,
                w - w * 0.035,
                h * 0.905,
              );
              final cdSize =
                  math.min(trayRect.width * 0.90, trayRect.height * 0.88);
              final cdLeft = trayRect.left + (trayRect.width - cdSize) / 2;
              final cdTop = trayRect.top + (trayRect.height - cdSize) / 2;
              final cdCenter = Offset(cdLeft + cdSize / 2, cdTop + cdSize / 2);

              // The sled travels from the disc's outer edge towards its centre.
              final lensOuterX = cdCenter.dx + cdSize * 0.40;
              final lensInnerX = cdCenter.dx - cdSize * 0.14;
              final railLeft = lensInnerX - 10;
              final railRight = lensOuterX + 10;
              final railY = h * 0.95;

              // Cache the disc raster once; rotation only moves the layer.
              final Widget cdDisc = RepaintBoundary(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // CD optical substrate surface and prismatic diffraction sheen.
                    CustomPaint(
                      size: Size(cdSize, cdSize),
                      painter: _CdDiscPainter(
                        activeColor: activeColor,
                        surface: surface,
                      ),
                    ),

                    // Circular album artwork printed onto the disc label.
                    Container(
                      width: cdSize * 0.45,
                      height: cdSize * 0.45,
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.circular(artRadius),
                        border: Border.all(
                          color: surface.specularAt(0.32),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: surface.shadowAt(0.38),
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
                              size: cdSize * 0.45,
                              borderRadius: artRadius,
                              highQuality: true,
                              fallbackIcon: Icons.music_note_rounded,
                            )
                          : ExcludeSemantics(
                              child: Icon(
                                Icons.album_rounded,
                                size: math.min(48.0, cdSize * 0.24),
                                color: surface.mutedInk,
                              ),
                            ),
                    ),

                    // Clear clamping band, then the tray's spider hub gripping
                    // the disc through its centre hole.
                    _JewelSpiderHub(diameter: cdSize * 0.21),
                  ],
                ),
              );

              return Semantics(
                container: true,
                image: true,
                label: playerArtworkSemanticLabel(context, song),
                hint: '${context.l10n.gestureArtworkDoubleTapTitle} — '
                    '${context.l10n.lyrics}',
                child: PlayerGestureScope(
                  behavior: HitTestBehavior.deferToChild,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 0. Y2K transparent acrylic jewel case: ribbed left spine,
                      // molded tray teeth, booklet clips & recessed disc well.
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _CdJewelCasePainter(
                              spineWidth: spineWidth,
                              trayRect: trayRect,
                              discCenter: cdCenter,
                              discRadius: cdSize / 2,
                              caseRadius: caseRadius,
                              activeColor: activeColor,
                              isPlaying: state.isPlaying,
                              isDark: p.isDark,
                              customGlow: widget.customGlow,
                              surface: surface,
                              isRtl: isRtl,
                            ),
                          ),
                        ),
                      ),

                      // 1. Rotating compact disc, dragged to scrub like a platter.
                      PositionedDirectional(
                        start: cdLeft,
                        top: cdTop,
                        width: cdSize,
                        height: cdSize,
                        child: PlatterScrubSemantics(
                          cubit: cubit,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (d) =>
                                _scrub.start(d.localPosition, cdSize),
                            onPanUpdate: (d) =>
                                _scrub.update(d.localPosition, cdSize),
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
                                animation: Listenable.merge(
                                  [widget.rotationController, _scrub],
                                ),
                                child: cdDisc,
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

                      // 1b. Anchored specular flare painted once above the
                      // spinning disc (clipped away from the artwork label).
                      PositionedDirectional(
                        start: cdLeft,
                        top: cdTop,
                        width: cdSize,
                        height: cdSize,
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _CdFlarePainter(labelRatio: 0.45),
                            ),
                          ),
                        ),
                      ),

                      // 1c. Analog scrub delta pill.
                      PositionedDirectional(
                        start: cdLeft,
                        top: cdTop,
                        width: cdSize,
                        height: cdSize,
                        child: IgnorePointer(
                          child: Center(
                            child: PlatterScrubPill(
                              controller: _scrub,
                              activeColor: activeColor,
                            ),
                          ),
                        ),
                      ),

                      // 2. Optical pickup sled: the lens rides the rail inward as
                      // the track advances, and only lights up while engaged.
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
                                return AnimatedBuilder(
                                  animation: widget.pickupAnimation,
                                  builder: (context, child) {
                                    final engage = widget.pickupAnimation.value;
                                    return CustomPaint(
                                      painter: _CdPickupSledPainter(
                                        railLeft: railLeft,
                                        railRight: railRight,
                                        railY: railY,
                                        lensX: lensOuterX +
                                            (lensInnerX - lensOuterX) *
                                                progress,
                                        engage: engage,
                                        activeColor: activeColor,
                                        discCenter: cdCenter,
                                        discRadius: cdSize / 2,
                                        surface: surface,
                                        isRtl: isRtl,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      // 3. Translucent acrylic lid reflection + play/pause gloss
                      // sweep painted above the disc so it reads as clear plastic.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _CdLidGlossPainter(
                                gloss: widget.glossAnimation,
                                caseRadius: caseRadius,
                                spineWidth: spineWidth,
                                surface: surface,
                                isRtl: isRtl,
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
          ),
        ),
      ),
    );
  }
}

/// Tray spider hub: the translucent clamping band plus the metallic hub whose
/// teeth grip the disc through its centre hole.
class _JewelSpiderHub extends StatelessWidget {
  final double diameter;

  const _JewelSpiderHub({required this.diameter});

  @override
  Widget build(BuildContext context) {
    final surface = context.playerSurfacePalette;
    final hubDiameter = math.max(diameter * 0.44, 16.0);
    return ExcludeSemantics(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Translucent polycarbonate clamping band of the tray hub.
            Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.specularAt(0.08),
                border: Border.all(
                  color: AppColors.specularAt(0.36),
                  width: 1.0,
                ),
              ),
            ),
            // Six radial flexible rosette teeth gripping the disc.
            for (int i = 0; i < 6; i++)
              Transform.rotate(
                angle: (i * 2 * math.pi) / 6,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: math.max(hubDiameter * 0.16, 2.4),
                    height: diameter * 0.24,
                    margin: EdgeInsets.only(top: diameter * 0.05),
                    decoration: BoxDecoration(
                      color: AppColors.specularAt(0.16),
                      borderRadius: AppRadii.circular(hubDiameter * 0.10),
                      border: Border.all(
                        color: AppColors.specularAt(0.30),
                        width: 0.7,
                      ),
                    ),
                  ),
                ),
              ),
            // Brushed metallic center spindle cap with center hole.
            Container(
              width: hubDiameter,
              height: hubDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.surfaceGreyLight,
                    AppColors.discSilver,
                    PlayerMaterialColors.cdPivotMid,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
                border: Border.all(
                  color: AppColors.specularAt(0.55),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: surface.shadowAt(0.50),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: hubDiameter * 0.36,
                  height: hubDiameter * 0.36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: surface.vinylGroove,
                    border: Border.all(
                      color: AppColors.specularAt(0.28),
                      width: 0.6,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
