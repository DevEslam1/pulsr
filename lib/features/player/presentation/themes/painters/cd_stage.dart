part of '../cd_player_theme.dart';

/// CD hero stage: a compact disc seated in a translucent jewel case, read by an
/// optical pickup sled instead of a tonearm.
///
/// The case — clear lid edge, hinge spine, recessed tray, clamping hub and a
/// gloss sweep when playback starts or stops — is the identity that separates
/// this deck from the vinyl turntable, which keeps its plinth, strobe rim,
/// tonearm and RPM badge. The VFD read-out stays: it is the deck's best idea.
class _CdJewelStage extends StatefulWidget {
  final PlayerThemeProps props;
  final bool isTablet;
  final bool isLandscape;
  final AnimationController rotationController;
  final Animation<double> pickupAnimation;
  final Animation<double> glossAnimation;

  const _CdJewelStage({
    required this.props,
    required this.isTablet,
    required this.isLandscape,
    required this.rotationController,
    required this.pickupAnimation,
    required this.glossAnimation,
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
    final props = widget.props;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    // Disc label and the ring framing it must share one radius, or a Theme
    // Studio radius would round the clip but leave the frame circular.
    final artRadius = resolveCustomRadius(context, 999);

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

              // Jewel-case geometry: the hinge spine takes the leading edge, the
              // tray fills the rest, and the pickup rail runs along the tray lip
              // below the disc.
              final spineWidth = math.min(w * 0.07, 28.0);
              final trayRect = Rect.fromLTRB(
                spineWidth + w * 0.03,
                h * 0.05,
                w - w * 0.035,
                h * 0.90,
              );
              final cdSize = math.min(trayRect.width * 0.92, trayRect.height * 0.84);
              final cdLeft = trayRect.left + (trayRect.width - cdSize) / 2;
              final cdTop = trayRect.top + (trayRect.height - cdSize) / 2;
              final cdCenter = Offset(cdLeft + cdSize / 2, cdTop + cdSize / 2);

              // The sled travels from the disc's outer edge towards its centre,
              // mirroring the read direction of a real disc.
              final lensOuterX = cdCenter.dx + cdSize * 0.40;
              final lensInnerX = cdCenter.dx - cdSize * 0.14;
              final railLeft = lensInnerX - 12;
              final railRight = lensOuterX + 12;
              final railY = h * 0.945;

              // Cache the disc raster once; rotation only moves the layer.
              final Widget cdDisc = RepaintBoundary(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // CD optical substrate surface and iridescent sheen.
                    CustomPaint(
                      size: Size(cdSize, cdSize),
                      painter: _CdDiscPainter(
                        activeColor: activeColor,
                        surface: surface,
                      ),
                    ),

                    // Circular album artwork printed onto the disc label.
                    Container(
                      width: cdSize * 0.44,
                      height: cdSize * 0.44,
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.circular(artRadius),
                        border: Border.all(
                          color: surface.specularAt(0.28),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: surface.shadowAt(0.40),
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
                              borderRadius: artRadius,
                              highQuality: true,
                              fallbackIcon: Icons.music_note_rounded,
                            )
                          : ExcludeSemantics(
                              child: Icon(
                                Icons.album_rounded,
                                size: 48,
                                color: surface.mutedInk,
                              ),
                            ),
                    ),

                    // Clear clamping band, then the tray's spider hub gripping
                    // the disc through its centre hole.
                    _JewelSpiderHub(diameter: cdSize * 0.20),
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
                      // 0. The jewel case itself: lid, hinge spine, tray recess
                      // and the gloss sweep that follows play/pause.
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _CdJewelCasePainter(
                              spineWidth: spineWidth,
                              trayRect: trayRect,
                              discCenter: cdCenter,
                              discRadius: cdSize / 2,
                              activeColor: activeColor,
                              isPlaying: state.isPlaying,
                              surface: surface,
                            ),
                          ),
                        ),
                      ),

                      // 1. Fluorescent retro VFD tray read-out. The read-out
                      // needs roughly 110 dp to say "TRK 01" without clipping,
                      // and a stage squeezed by a short window can hand the
                      // deck a tray narrower than that. Below 150 dp the text
                      // would only render as a truncated fragment, so the
                      // display is dropped instead of overflowing the case.
                      // It also stays readable to assistive tech: the VFD is
                      // the only place the disc's track number and file spec
                      // are printed, and excluding it left screen-reader users
                      // with just the artwork title.
                      if (trayRect.width >= 150)
                        PositionedDirectional(
                          top: h * 0.022,
                          start: trayRect.left,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: trayRect.right - trayRect.left,
                            ),
                            child: _CdOpticalDisplayHud(
                              props: props,
                              activeColor: activeColor,
                            ),
                          ),
                        ),

                      // 2. Rotating compact disc, dragged to scrub like a platter.
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
                                // Drag phase and spin phase drive one transform,
                                // so both listenables are merged here.
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

                      // 2c. Analog scrub delta pill.
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

                      // 3. Optical pickup sled: the lens rides the rail inward as
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
                                    final engage =
                                        widget.pickupAnimation.value;
                                    return CustomPaint(
                                      painter: _CdPickupSledPainter(
                                        railLeft: railLeft,
                                        railRight: railRight,
                                        railY: railY,
                                        lensX: lensOuterX +
                                            (lensInnerX - lensOuterX) * progress,
                                        engage: engage,
                                        activeColor: activeColor,
                                        discCenter: cdCenter,
                                        discRadius: cdSize / 2,
                                        surface: surface,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      // 4. Lid gloss: light sweeping over the closed case. It is
                      // painted above the disc so it reads as clear plastic.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _CdLidGlossPainter(
                                gloss: widget.glossAnimation,
                                surface: surface,
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
    final hubDiameter = math.max(diameter * 0.42, 18.0);
    return ExcludeSemantics(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Translucent clamping band of the tray hub.
            Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: surface.specularAt(0.06),
                border: Border.all(
                  color: surface.specularAt(0.30),
                  width: 1.0,
                ),
              ),
            ),
            // Three flexible teeth gripping the disc.
            for (int i = 0; i < 3; i++)
              Transform.rotate(
                angle: (i * 2 * math.pi) / 3,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: hubDiameter * 0.30,
                    height: diameter * 0.26,
                    margin: EdgeInsets.only(top: diameter * 0.06),
                    decoration: BoxDecoration(
                      color: surface.specularAt(0.12),
                      borderRadius: AppRadii.circular(hubDiameter * 0.15),
                      border: Border.all(
                        color: surface.specularAt(0.26),
                        width: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            // Metallic hub cap with the spindle hole through it.
            Container(
              width: hubDiameter,
              height: hubDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    surface.platterMetalHighlight,
                    surface.platterMetalDeep,
                    PlayerMaterialColors.cdPivotLow,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
                border: Border.all(
                  color: surface.specularAt(0.50),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: surface.shadowAt(0.55),
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
                      color: surface.specularAt(0.24),
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
    final surface = context.playerSurfacePalette;
    final state = props.state;
    final trackNum = (state.currentIndex >= 0 ? state.currentIndex + 1 : 1)
        .toString()
        .padLeft(2, '0');
    final isPlaying = state.isPlaying;
    // The spec segment only exists when the file actually reports one; the HUD
    // never falls back to a "CD-DA" default it cannot vouch for.
    final audioSpec = _formatAudioSpec(state.currentSong);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            surface.tapeWindow.withValues(alpha: 0.94),
            surface.vinylGroove.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: AppRadii.r8All,
        border: Border.all(
          color: activeColor.withValues(alpha: isPlaying ? 0.48 : 0.30),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: surface.shadowAt(0.50),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Optical laser status dot.
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPlaying ? surface.ledGlow : surface.specularAt(0.24),
              boxShadow: isPlaying
                  ? [
                      BoxShadow(
                        color: surface.ledGlow,
                        blurRadius: 6,
                        spreadRadius: 1.5,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),

          // Track number matrix. Flexible keeps the read-out inside a tray
          // that is only just wide enough: the number ellipsises before the
          // row is allowed to paint past the case edge.
          Flexible(
            child: Text(
              context.l10n.cdTrackNumber(trackNum),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w900,
                color: isPlaying ? surface.ledGlow : surface.highContrastInk,
                letterSpacing: 1.0,
              ),
            ),
          ),

          if (audioSpec.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 10,
              color: surface.specularAt(0.24),
            ),
            const SizedBox(width: 8),
            // Shrinks and ellipsises at large text scales instead of pushing
            // the read-out past the case edge.
            Flexible(
              child: Text(
                audioSpec,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                  color: surface.mutedInk,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Formats only the audio facts this file actually reports.
  ///
  /// The previous implementation printed a CD-DA default whenever metadata was
  /// missing, which invented a 44.1 kHz / 16-bit claim for lossy or untagged
  /// files. Missing halves are now omitted rather than filled in, and the whole
  /// segment disappears when nothing is known.
  static String _formatAudioSpec(SongsTableData? song) {
    if (song == null) return '';
    final codec = (song.codec ?? '').trim().toUpperCase();
    final bitrate = song.bitrateKbps;
    final isLossy = codec.contains('MP3') ||
        codec.contains('AAC') ||
        codec.contains('OGG') ||
        codec.contains('OPUS') ||
        codec.contains('M4A') ||
        codec.contains('VORBIS');

    // Lossy sources are best described by codec and bitrate; lossless ones by
    // the rate and depth that the decoder chain will actually use.
    if (isLossy) {
      final parts = <String>[
        if (codec.isNotEmpty) codec,
        if (bitrate != null && bitrate > 0) '$bitrate kbps',
      ];
      if (parts.isNotEmpty) return parts.join(' • ');
    }

    final parts = <String>[
      if (song.sampleRate != null && song.sampleRate! > 0)
        '${(song.sampleRate! / 1000).toStringAsFixed(1)} kHz',
      if (song.bitDepth != null && song.bitDepth! > 0) '${song.bitDepth}-BIT',
      // A lossless container can still be described by bitrate alone when only
      // that column is populated.
      if ((song.sampleRate == null || song.sampleRate! <= 0) &&
          (song.bitDepth == null || song.bitDepth! <= 0) &&
          bitrate != null &&
          bitrate > 0)
        '$bitrate kbps',
      if ((song.sampleRate == null || song.sampleRate! <= 0) &&
          (song.bitDepth == null || song.bitDepth! <= 0) &&
          (bitrate == null || bitrate <= 0) &&
          codec.isNotEmpty)
        codec,
    ];
    return parts.join(' • ');
  }
}
