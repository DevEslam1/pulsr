// lib/features/player/presentation/widgets/tablet_player_bar_sections.dart
part of 'tablet_player_bar.dart';

/// Extracted left (track/art), center (transport/seekbar), and right
/// (volume/quick-actions) sections of [TabletPlayerBar].
extension _TabletPlayerBarSections on _TabletPlayerBarState {
  Widget _buildLeftTrackSection({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required PulsrPalette p,
    required Color activeColor,
    required PlayerThemeMode playerThemeMode,
    required double leftMaxWidth,
    required bool isShortHeight,
    required bool isCompactBar,
    required bool showSecondaryBadges,
    required bool showFavoriteButton,
  }) {
    final song = state.currentSong!;
    final l10n = context.l10n;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 0,
        maxWidth: leftMaxWidth,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: widget.onOpenNowPlaying,
            child: ClipRRect(
              borderRadius: AppRadii.circular(
                isShortHeight ? AppRadii.r8 : AppRadii.r12,
              ),
              child: Hero(
                tag: nowPlayingArtHeroTag(playerThemeMode),
                child: CachedArtwork(
                  id: song.id,
                  albumId: song.albumId,
                  remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                  type: ArtworkType.AUDIO,
                  size: isShortHeight ? 40 : (isCompactBar ? 42 : 54),
                  borderRadius: isShortHeight ? 8 : 12,
                ),
              ),
            ),
          ),
          SizedBox(
            width: (isCompactBar || isShortHeight)
                ? AppSpacing.xs
                : AppSpacing.s10,
          ),
          Flexible(
            child: GestureDetector(
              onTap: widget.onOpenNowPlaying,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: isShortHeight
                          ? AppFontSize.label
                          : AppFontSize.bodySmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontWeight: FontWeight.w500,
                      fontSize: isShortHeight
                          ? AppFontSize.caption
                          : AppFontSize.label,
                    ),
                  ),
                  if (showSecondaryBadges) ...[
                    const SizedBox(height: 5.0),
                    AudioQualityBadge(
                      song: song,
                      activeColor: activeColor,
                      compact: true,
                      showDevice: false,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (showFavoriteButton)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              icon: Icon(
                song.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: song.isFavorite ? p.favorite : p.textSecondary,
                size: isShortHeight ? 18 : 20,
              ),
              tooltip: song.isFavorite ? l10n.unlike : l10n.like,
              onPressed: () => cubit.toggleFavorite(song.id),
            ),
        ],
      ),
    );
  }

  Widget _buildCenterTransportSection({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required PulsrPalette p,
    required Color activeColor,
    required PlayerSliderStyle playerSliderStyle,
    required bool isShortHeight,
  }) {
    final l10n = context.l10n;
    final buttonGap = isShortHeight ? AppSpacing.xxs : AppSpacing.xs;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: SizedBox(
                width: constraints.maxWidth.clamp(180.0, 520.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Controls Row (LTR locked so transport direction stays consistent)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Shuffle
                            _buildTransportToggleButton(
                              context: context,
                              p: p,
                              activeColor: activeColor,
                              label: state.isShuffle
                                  ? l10n.disableShuffle
                                  : l10n.enableShuffle,
                              icon: Icons.shuffle_rounded,
                              isActive: state.isShuffle,
                              isShortHeight: isShortHeight,
                              onTap: () {
                                PulsrHaptics.selectionClick();
                                cubit.toggleShuffle();
                              },
                            ),
                            SizedBox(width: buttonGap),
                            // Previous Button
                            _buildTransportSkipButton(
                              p: p,
                              label: l10n.previous,
                              icon: Icons.skip_previous_rounded,
                              enabled: true,
                              isShortHeight: isShortHeight,
                              onTap: () {
                                PulsrHaptics.lightImpact();
                                cubit.previous();
                              },
                            ),
                            SizedBox(width: buttonGap),
                            // Main Play / Pause Button
                            _buildTransportPlayPauseButton(
                              context: context,
                              cubit: cubit,
                              state: state,
                              activeColor: activeColor,
                              isShortHeight: isShortHeight,
                            ),
                            SizedBox(width: buttonGap),
                            // Next Button
                            _buildTransportSkipButton(
                              p: p,
                              label: l10n.next,
                              icon: Icons.skip_next_rounded,
                              enabled: state.hasNextNeighbour,
                              isShortHeight: isShortHeight,
                              onTap: state.hasNextNeighbour
                                  ? () {
                                      PulsrHaptics.lightImpact();
                                      cubit.next();
                                    }
                                  : null,
                            ),
                            SizedBox(width: buttonGap),
                            // Repeat
                            _buildTransportToggleButton(
                              context: context,
                              p: p,
                              activeColor: activeColor,
                              label: state.repeatMode == PlayerRepeatMode.one
                                  ? l10n.repeatOne
                                  : state.repeatMode == PlayerRepeatMode.all
                                      ? l10n.repeatAll
                                      : l10n.repeatOff,
                              icon: state.repeatMode == PlayerRepeatMode.one
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                              isActive:
                                  state.repeatMode != PlayerRepeatMode.off,
                              isShortHeight: isShortHeight,
                              onTap: () {
                                PulsrHaptics.selectionClick();
                                cubit.toggleRepeat();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: isShortHeight ? 2 : AppSpacing.xxs),
                    // Seekbar Row isolated with RepaintBoundary
                    _buildSeekbarRow(
                      context: context,
                      cubit: cubit,
                      state: state,
                      p: p,
                      activeColor: activeColor,
                      playerSliderStyle: playerSliderStyle,
                      isShortHeight: isShortHeight,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTransportToggleButton({
    required BuildContext context,
    required PulsrPalette p,
    required Color activeColor,
    required String label,
    required IconData icon,
    required bool isActive,
    required bool isShortHeight,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: context.motionMs(200),
                  width: isShortHeight ? 30 : 36,
                  height: isShortHeight ? 30 : 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? activeColor.withValues(alpha: 0.16)
                        : Colors.transparent,
                    border: isActive
                        ? Border.all(
                            color: activeColor.withValues(alpha: 0.35),
                            width: 1.0,
                          )
                        : null,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: isShortHeight ? 17 : 20,
                      color: isActive ? activeColor : p.textSecondary,
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

  Widget _buildTransportSkipButton({
    required PulsrPalette p,
    required String label,
    required IconData icon,
    required bool enabled,
    required bool isShortHeight,
    required VoidCallback? onTap,
  }) {
    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              child: Center(
                child: Container(
                  width: isShortHeight ? 34 : 40,
                  height: isShortHeight ? 34 : 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.textPrimary.withValues(alpha: 0.08),
                    border: Border.all(
                      color: p.textPrimary.withValues(alpha: 0.13),
                      width: 1.0,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: isShortHeight ? 20 : 24,
                      color: enabled
                          ? p.textPrimary
                          : p.textTertiary.withValues(alpha: 0.38),
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

  Widget _buildTransportPlayPauseButton({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required Color activeColor,
    required bool isShortHeight,
  }) {
    final l10n = context.l10n;
    final label = state.isPlaying ? l10n.pause : l10n.play;
    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            PulsrHaptics.mediumImpact();
            cubit.togglePlayPause();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppSpacing.minTouchTarget,
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: Center(
              child: AnimatedContainer(
                duration: context.motionMs(200),
                width: isShortHeight ? 40 : 48,
                height: isShortHeight ? 40 : 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(
                            activeColor,
                            AppColors.specularAt(1.0),
                            0.22,
                          ) ??
                          activeColor,
                      activeColor,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(
                        alpha: state.isPlaying ? 0.42 : 0.25,
                      ),
                      blurRadius: isShortHeight ? 10 : 14,
                      spreadRadius: state.isPlaying ? 1.0 : 0.0,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.specularAt(0.30),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: context.motionMs(200),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: child,
                    ),
                    child: state.isBuffering
                        ? SizedBox(
                            key: const ValueKey<String>('buffering'),
                            width: isShortHeight ? 18 : 22,
                            height: isShortHeight ? 18 : 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.3,
                              color: AppColors.textOnAccent(activeColor),
                            ),
                          )
                        : Icon(
                            state.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            key: ValueKey<bool>(state.isPlaying),
                            color: AppColors.textOnAccent(activeColor),
                            size: isShortHeight ? 22 : 26,
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

  Widget _buildSeekbarRow({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required PulsrPalette p,
    required Color activeColor,
    required PlayerSliderStyle playerSliderStyle,
    required bool isShortHeight,
  }) {
    final maxMs = state.duration.inMilliseconds.toDouble() > 0
        ? state.duration.inMilliseconds.toDouble()
        : 1.0;

    return RepaintBoundary(
      child: BlocSelector<PlayerCubit, PlayerState, Duration>(
        selector: (s) => s.position,
        builder: (context, position) {
          return ValueListenableBuilder<double?>(
            valueListenable: _dragSeekNotifier,
            builder: (context, dragSeekValue, _) {
              final currentDuration = dragSeekValue != null
                  ? Duration(milliseconds: dragSeekValue.toInt())
                  : position;
              final valueLabel =
                  '${Formatters.formatDuration(currentDuration)} / ${Formatters.formatDuration(state.duration)}';
              return Row(
                children: [
                  Text(
                    Formatters.formatDuration(currentDuration),
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.caption,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Semantics(
                      value: valueLabel,
                      child: PulsrSlider(
                        height: isShortHeight ? 16 : 24,
                        min: 0.0,
                        max: maxMs,
                        value: (dragSeekValue ??
                                position.inMilliseconds.toDouble())
                            .clamp(0.0, maxMs),
                        semanticLabel: context.l10n.seekLabel,
                        activeColor: activeColor,
                        inactiveColor:
                            Theme.of(context).brightness == Brightness.dark
                                ? (playerSliderStyle ==
                                        PlayerSliderStyle.capsule
                                    ? AppColors.specularAt(0.22)
                                    : AppColors.specularStrong)
                                : (playerSliderStyle ==
                                        PlayerSliderStyle.capsule
                                    ? AppColors.scrimAt(0.15)
                                    : p.hairline.withValues(alpha: 0.8)),
                        sliderStyle: playerSliderStyle,
                        isWavy: playerSliderStyle == PlayerSliderStyle.wavy,
                        animateWave: state.isPlaying,
                        onChangeStart: (val) {
                          _dragSeekNotifier.value = val;
                        },
                        onChanged: (val) {
                          _dragSeekNotifier.value = val;
                        },
                        onChangeEnd: (val) {
                          cubit.seek(Duration(milliseconds: val.toInt()));
                          _dragSeekNotifier.value = null;
                        },
                        onChangeCancel: () {
                          _dragSeekNotifier.value = null;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    Formatters.formatDuration(state.duration),
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.caption,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRightActionsSection({
    required BuildContext context,
    required PlayerCubit cubit,
    required PlayerState state,
    required PulsrPalette p,
    required Color activeColor,
    required PlayerSliderStyle playerSliderStyle,
    required AudioOutputInfo? currentOutputDevice,
    required double rightMaxWidth,
    required bool isShortHeight,
    required bool showVolumeSlider,
  }) {
    final song = state.currentSong!;
    final l10n = context.l10n;
    return Flexible(
      flex: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: rightMaxWidth),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!isShortHeight) ...[
                // Volume Mute / Slider
                BlocSelector<PlayerCubit, PlayerState, double>(
                  selector: (s) => s.volume,
                  builder: (context, cubitVolume) {
                    return ValueListenableBuilder<double?>(
                      valueListenable: _dragVolumeNotifier,
                      builder: (context, dragVolume, _) {
                        final effectiveVolume =
                            (dragVolume ?? cubitVolume).clamp(0.0, 1.0);
                        final isMuted =
                            cubit.isMuted || effectiveVolume <= 0.0;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: AppSpacing.minTouchTarget,
                                minHeight: AppSpacing.minTouchTarget,
                              ),
                              icon: Icon(
                                isMuted
                                    ? Icons.volume_off_rounded
                                    : (effectiveVolume < 0.5
                                        ? Icons.volume_down_rounded
                                        : Icons.volume_up_rounded),
                                color: p.textSecondary,
                                size: 19,
                              ),
                              tooltip: isMuted ? l10n.unmute : l10n.mute,
                              onPressed: () {
                                _dragVolumeNotifier.value = null;
                                cubit.toggleMute();
                              },
                            ),
                            if (showVolumeSlider)
                              SizedBox(
                                width: 80,
                                child: Semantics(
                                  label: l10n.volume,
                                  value: '${(effectiveVolume * 100).round()}%',
                                  child: PulsrSlider(
                                    min: 0.0,
                                    max: 1.0,
                                    value: effectiveVolume,
                                    activeColor: p.textPrimary,
                                    sliderStyle: playerSliderStyle ==
                                            PlayerSliderStyle.wavy
                                        ? PlayerSliderStyle.wavy
                                        : PlayerSliderStyle.normal,
                                    isWavy: playerSliderStyle ==
                                        PlayerSliderStyle.wavy,
                                    animateWave: false,
                                    onChangeStart: (v) =>
                                        _dragVolumeNotifier.value = v,
                                    onChanged: (v) {
                                      _dragVolumeNotifier.value = v;
                                      cubit.setVolume(v);
                                    },
                                    onChangeEnd: (v) {
                                      _dragVolumeNotifier.value = null;
                                      cubit.setVolume(v);
                                    },
                                    onChangeCancel: () {
                                      _dragVolumeNotifier.value = null;
                                    },
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.s2),
                // DAC / Output
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  icon: Icon(
                    Icons.settings_input_component_rounded,
                    size: 19,
                    color: currentOutputDevice?.isUsbDac == true
                        ? AppColors.dacGold
                        : p.textSecondary,
                  ),
                  tooltip: l10n.audioOutputAndDac,
                  onPressed: () =>
                      AudioQualitySheet.show(context, song, activeColor),
                ),
                // Equalizer
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  icon: Icon(
                    Icons.equalizer_rounded,
                    size: 19,
                    color: state.isEqEnabled ? activeColor : p.textSecondary,
                  ),
                  tooltip: l10n.equalizer,
                  onPressed: () => EqualizerSheet.show(context),
                ),
              ],
              // Queue inspector toggle
              if (widget.onToggleSideInspector != null)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  icon: Icon(
                    Icons.queue_music_rounded,
                    size: isShortHeight ? 18 : 19,
                    color:
                        widget.isInspectorOpen ? activeColor : p.textSecondary,
                  ),
                  tooltip: l10n.toggleSideQueue,
                  onPressed: widget.onToggleSideInspector,
                ),
              // Expand Fullscreen
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                icon: Icon(
                  Icons.open_in_full_rounded,
                  size: 18,
                  color: p.textSecondary,
                ),
                tooltip: l10n.fullscreenPlayer,
                onPressed: widget.onOpenNowPlaying,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
