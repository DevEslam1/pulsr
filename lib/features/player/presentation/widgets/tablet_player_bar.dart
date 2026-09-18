// lib/features/player/presentation/widgets/tablet_player_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'audio_quality_badge.dart';
import 'audio_quality_sheet.dart';
import 'equalizer_sheet.dart';
import '../../../../core/widgets/pulsr_modal_tracker.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

class TabletPlayerBar extends StatefulWidget {
  final VoidCallback onOpenNowPlaying;
  final VoidCallback? onToggleSideInspector;
  final bool isInspectorOpen;

  const TabletPlayerBar({
    super.key,
    required this.onOpenNowPlaying,
    this.onToggleSideInspector,
    this.isInspectorOpen = false,
  });

  @override
  State<TabletPlayerBar> createState() => _TabletPlayerBarState();
}

class _TabletPlayerBarState extends State<TabletPlayerBar> {
  /// Local drag override while the user is scrubbing the volume slider. When
  /// null, the authoritative volume is read from [PulsrAudioHandler] (the
  /// single volume owner used across the app). Mirrors [_dragSeekValue].
  double? _dragVolume;
  double _preMuteVolume = 1.0;
  double? _dragSeekValue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settingsState = context.watch<SettingsCubit>().state;

    return ValueListenableBuilder<bool>(
      valueListenable: PulsrModalTracker.isModalOpen,
      builder: (context, modalOpen, _) {
        if (modalOpen) return const SizedBox.shrink();
        return BlocBuilder<PlayerCubit, PlayerState>(
          buildWhen: (prev, curr) =>
              prev.currentSong?.id != curr.currentSong?.id ||
              prev.currentSong?.title != curr.currentSong?.title ||
              prev.currentSong?.artist != curr.currentSong?.artist ||
              prev.currentSong?.isFavorite != curr.currentSong?.isFavorite ||
              prev.isPlaying != curr.isPlaying ||
              prev.duration != curr.duration ||
              prev.isShuffle != curr.isShuffle ||
              prev.repeatMode != curr.repeatMode ||
              prev.isLyricsVisible != curr.isLyricsVisible ||
              prev.isQueueVisible != curr.isQueueVisible ||
              prev.isEqEnabled != curr.isEqEnabled,
          builder: (context, state) {
            final song = state.currentSong;
            if (song == null) return const SizedBox.shrink();

            final cubit = context.read<PlayerCubit>();
            final activeColor = p.accent;
            // A-3: the handler owns the master volume (no PlayerState.volume by
            // design). Read it as the single source of truth, keeping the local
            // drag override only while the user is scrubbing.
            final handlerVolume =
                context.read<PulsrAudioHandler>().volume.clamp(0.0, 1.0);
            final effectiveVolume = (_dragVolume ?? handlerVolume).clamp(0.0, 1.0);
            final isMuted = effectiveVolume <= 0.0;
            final l10n = context.l10n;

            return Container(
          height: 90,
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(
              top: BorderSide(color: p.hairline, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s6),
            child: Row(
              children: [
                // ── Left: Track Info & Artwork ──────────────────────────
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 180,
                    maxWidth: 270,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: widget.onOpenNowPlaying,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.r10),
                          child: CachedArtwork(
                            id: song.id,
                            remoteUrl: song.remoteArtworkUrl,
                            type: ArtworkType.AUDIO,
                            size: 50,
                            borderRadius: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s10),
                      Expanded(
                        child: GestureDetector(
                          onTap: widget.onOpenNowPlaying,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.bodySmall,
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
                                  fontSize: AppFontSize.label,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: AudioQualityBadge(
                                  song: song,
                                  activeColor: activeColor,
                                  compact: true,
                                  showDevice: false,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: Icon(
                          song.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: song.isFavorite ? p.favorite : p.textSecondary,
                          size: 20,
                        ),
                        tooltip: song.isFavorite ? l10n.unlike : l10n.like,
                        onPressed: () => cubit.toggleFavorite(song.id),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: AppSpacing.sm),

                // ── Center: Transport Controls & Seekbar ─────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Controls Row
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 48, minHeight: 48),
                                icon: Icon(
                                  Icons.shuffle_rounded,
                                  size: 19,
                                  color: state.isShuffle
                                      ? activeColor
                                      : p.textSecondary,
                                ),
                                tooltip: state.isShuffle
                                    ? l10n.disableShuffle
                                    : l10n.enableShuffle,
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  cubit.toggleShuffle();
                                },
                              ),
                              const SizedBox(width: AppSpacing.s2),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 48, minHeight: 48),
                                icon: Icon(
                                  Icons.skip_previous_rounded,
                                  size: 25,
                                  color: p.textPrimary,
                                ),
                                tooltip: l10n.previous,
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  cubit.previous();
                                },
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                              Semantics(
                                label: state.isPlaying ? l10n.pause : l10n.play,
                                button: true,
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.mediumImpact();
                                    cubit.togglePlayPause();
                                  },
                                  child: SizedBox(width: AppSpacing.xxl,
                                    height: 48,
                                    child: Center(
                                      child: Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: activeColor,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: p.glow
                                                  .withValues(alpha: 0.4),
                                              blurRadius: 10,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          state.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: p.onAccent,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 48, minHeight: 48),
                                icon: Icon(
                                  Icons.skip_next_rounded,
                                  size: 25,
                                  color: p.textPrimary,
                                ),
                                tooltip: l10n.next,
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  cubit.next();
                                },
                              ),
                              const SizedBox(width: AppSpacing.s2),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 48, minHeight: 48),
                                icon: Icon(
                                  state.repeatMode == PlayerRepeatMode.one
                                      ? Icons.repeat_one_rounded
                                      : Icons.repeat_rounded,
                                  size: 19,
                                  color:
                                      state.repeatMode != PlayerRepeatMode.off
                                          ? activeColor
                                          : p.textSecondary,
                                ),
                                tooltip:
                                    state.repeatMode == PlayerRepeatMode.one
                                        ? l10n.repeatOne
                                        : state.repeatMode ==
                                                PlayerRepeatMode.all
                                            ? l10n.repeatAll
                                            : l10n.repeatOff,
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  cubit.toggleRepeat();
                                },
                              ),
                            ],
                          ),
                        ),

                        // Seekbar Row
                        BlocSelector<PlayerCubit, PlayerState, Duration>(
                          selector: (s) => s.position,
                          builder: (context, position) {
                            final currentDuration = _dragSeekValue != null
                                ? Duration(
                                    milliseconds: _dragSeekValue!.toInt())
                                : position;
                            final valueLabel =
                                '${Formatters.formatDuration(currentDuration)} / ${Formatters.formatDuration(state.duration)}';
                            return Row(
                              children: [
                                Text(
                                  Formatters.formatDuration(
                                    _dragSeekValue != null
                                        ? Duration(
                                            milliseconds:
                                                _dragSeekValue!.toInt())
                                        : position,
                                  ),
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.caption,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Semantics(
                                    value: valueLabel,
                                    child: PulsrSlider(
                                      min: 0.0,
                                      max: state.duration.inMilliseconds
                                                  .toDouble() >
                                              0
                                          ? state.duration.inMilliseconds
                                              .toDouble()
                                          : 1.0,
                                      value: (_dragSeekValue ??
                                              position.inMilliseconds
                                                  .toDouble())
                                          .clamp(
                                        0.0,
                                        state.duration.inMilliseconds
                                                    .toDouble() >
                                                0
                                            ? state.duration.inMilliseconds
                                                .toDouble()
                                            : 1.0,
                                      ),
                                      semanticLabel: context.l10n.seekLabel,
                                      activeColor: activeColor,
                                      onChangeStart: (val) {
                                        setState(() => _dragSeekValue = val);
                                      },
                                      onChanged: (val) {
                                        setState(() => _dragSeekValue = val);
                                      },
                                      onChangeEnd: (val) {
                                        cubit.seek(
                                            Duration(milliseconds: val.toInt()));
                                        setState(() => _dragSeekValue = null);
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
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: AppSpacing.sm),

                // ── Right: Volume & Quick Actions ───────────────────────
                Flexible(
                  flex: 0,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Volume Mute / Slider
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 48, minHeight: 48),
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
                            if (isMuted) {
                              final restore =
                                  _preMuteVolume <= 0.0 ? 1.0 : _preMuteVolume;
                              setState(() {
                                _preMuteVolume = restore;
                                _dragVolume = null;
                              });
                              cubit.setVolume(restore);
                            } else {
                              setState(() {
                                _preMuteVolume = effectiveVolume;
                                _dragVolume = null;
                              });
                              cubit.setVolume(0.0);
                            }
                          },
                        ),
                        SizedBox(
                          width: 80,
                          child: Semantics(
                            label: l10n.volume,
                            child: PulsrSlider(
                              min: 0.0,
                              max: 1.0,
                              value: effectiveVolume,
                              activeColor: p.textPrimary,
                              onChangeStart: (v) =>
                                  setState(() => _dragVolume = v),
                              onChanged: (v) {
                                setState(() => _dragVolume = v);
                                cubit.setVolume(v);
                              },
                              onChangeEnd: (v) {
                                setState(() => _dragVolume = null);
                                cubit.setVolume(v);
                                if (v > 0.0) _preMuteVolume = v;
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s2),

                        // DAC / Output
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 48, minHeight: 48),
                          icon: Icon(
                            Icons.settings_input_component_rounded,
                            size: 19,
                            color: settingsState
                                        .currentOutputDevice?.isUsbDac ==
                                    true
                                ? AppColors.dacGold
                                : p.textSecondary,
                          ),
                          tooltip: l10n.audioOutputAndDac,
                          onPressed: () => AudioQualitySheet.show(
                              context, song, activeColor),
                        ),

                        // Equalizer
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 48, minHeight: 48),
                          icon: Icon(
                            Icons.equalizer_rounded,
                            size: 19,
                            color: state.isEqEnabled
                                ? activeColor
                                : p.textSecondary,
                          ),
                          tooltip: l10n.equalizer,
                          onPressed: () => EqualizerSheet.show(context),
                        ),

                        // Queue inspector toggle
                        if (widget.onToggleSideInspector != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            icon: Icon(
                              Icons.queue_music_rounded,
                              size: 19,
                              color: widget.isInspectorOpen
                                  ? activeColor
                                  : p.textSecondary,
                            ),
                            tooltip: l10n.toggleSideQueue,
                            onPressed: widget.onToggleSideInspector,
                          ),

                        // Expand Fullscreen
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 48, minHeight: 48),
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
               ],
             ),
           ),
         );
          },
        );
      },
    );
  }
}
