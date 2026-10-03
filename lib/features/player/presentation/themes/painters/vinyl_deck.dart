part of '../vinyl_player_theme.dart';

/// Turntable hero stage: platter, spinning record, tonearm and RPM badge.
class _VinylTurntableDeck extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
          maxHeight: isLandscape ? 300 : (isTablet ? 480 : 390),
          maxWidth: isLandscape ? 320 : (isTablet ? 500 : 410),
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
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF14151C),
                      borderRadius: AppRadii.r22All,
                      border: Border.all(
                        color: const Color(0xFF282B37),
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
                              Text(
                                context.l10n.vinylDirectDrive,
                                style: const TextStyle(
                                  fontSize: AppFontSize.micro,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: AppTracking.wide,
                                  color: Colors.white38,
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
                            painter: _PlatterStrobePainter(),
                          ),
                        ),

                        // 3. Spinning Vinyl Record
                        PositionedDirectional(
                          start: vinylLeft,
                          top: vinylTop,
                          width: vinylSize,
                          height: vinylSize,
                          child: RotationTransition(
                            turns: rotationController,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF0C0D11),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.scrimAt(0.5),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: CustomPaint(
                                painter: _VinylGroovesPainter(
                                  activeColor: activeColor,
                                ),
                                child: Center(
                                  // Center Album Artwork
                                  child: Container(
                                    width: vinylSize * 0.44,
                                    height: vinylSize * 0.44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
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
                                            remoteUrl: song.remoteArtworkUrl ??
                                                song.artworkUri,
                                            type: ArtworkType.AUDIO,
                                            size: vinylSize * 0.44,
                                            borderRadius: 999,
                                            highQuality: true,
                                            fallbackIcon:
                                                Icons.music_note_rounded,
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
                                    animation: tonearmAnimation,
                                    builder: (context, child) {
                                      final currentAngle = -0.06 +
                                          ((playAngle - (-0.06)) *
                                              tonearmAnimation.value);

                                      return CustomPaint(
                                        painter: _TonearmPainter(
                                          pivot: pivotOffset,
                                          angle: currentAngle,
                                          activeColor: activeColor,
                                          armLength: armLength,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ),

                        // 5. Bottom Plinth RPM Badge (33⅓ RPM / Standby)
                        PositionedDirectional(
                          bottom: 12,
                          start: 14,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xs,
                                    vertical: AppSpacing.xxs),
                                decoration: BoxDecoration(
                                  color: state.isPlaying
                                      ? activeColor.withValues(alpha: 0.15)
                                      : const Color(0xFF181A22),
                                  borderRadius: AppRadii.r6All,
                                  border: Border.all(
                                    color: state.isPlaying
                                        ? activeColor.withValues(alpha: 0.5)
                                        : const Color(0xFF2B2E3C),
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
                                    Text(
                                      state.isPlaying
                                          ? context.l10n.vinylSpeedRpm
                                          : context.l10n.dspStandby,
                                      style: TextStyle(
                                        fontSize: AppFontSize.micro,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: AppTracking.overline,
                                        color: state.isPlaying
                                            ? activeColor
                                            : Colors.white38,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
