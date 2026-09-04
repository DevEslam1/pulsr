// lib/features/player/presentation/widgets/tablet_player_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'audio_quality_badge.dart';
import 'audio_quality_sheet.dart';
import 'equalizer_sheet.dart';

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
  double _volume = 1.0;
  bool _isMuted = false;
  double _preMuteVolume = 1.0;
  double? _dragSeekValue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settingsState = context.watch<SettingsCubit>().state;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.currentSong?.id != curr.currentSong?.id ||
          prev.currentSong?.title != curr.currentSong?.title ||
          prev.currentSong?.artist != curr.currentSong?.artist ||
          prev.isPlaying != curr.isPlaying ||
          prev.position != curr.position ||
          prev.duration != curr.duration ||
          prev.isShuffle != curr.isShuffle ||
          prev.repeatMode != curr.repeatMode ||
          prev.isLyricsVisible != curr.isLyricsVisible ||
          prev.isQueueVisible != curr.isQueueVisible,
      builder: (context, state) {
        final song = state.currentSong;
        if (song == null) return const SizedBox.shrink();

        final cubit = context.read<PlayerCubit>();
        final activeColor = p.accent;

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                          borderRadius: BorderRadius.circular(10),
                          child: CachedArtwork(
                            id: song.id,
                            remoteUrl: song.remoteArtworkUrl,
                            type: ArtworkType.AUDIO,
                            size: 50,
                            borderRadius: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
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
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 3),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
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
                        padding: const EdgeInsets.all(6),
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                        icon: Icon(
                          song.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: song.isFavorite ? p.favorite : p.textSecondary,
                          size: 20,
                        ),
                        tooltip: song.isFavorite ? 'Unlike' : 'Like',
                        onPressed: () => cubit.toggleFavorite(song.id),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // ── Center: Transport Controls & Seekbar ─────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Controls Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(
                                  minWidth: 34, minHeight: 34),
                              icon: Icon(
                                Icons.shuffle_rounded,
                                size: 19,
                                color: state.isShuffle
                                    ? activeColor
                                    : p.textSecondary,
                              ),
                              tooltip: 'Shuffle',
                              onPressed: cubit.toggleShuffle,
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(
                                  minWidth: 38, minHeight: 38),
                              icon: Icon(
                                Icons.skip_previous_rounded,
                                size: 25,
                                color: p.textPrimary,
                              ),
                              tooltip: 'Previous',
                              onPressed: cubit.previous,
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: cubit.togglePlayPause,
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: activeColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: p.glow.withValues(alpha: 0.4),
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
                            const SizedBox(width: 4),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(
                                  minWidth: 38, minHeight: 38),
                              icon: Icon(
                                Icons.skip_next_rounded,
                                size: 25,
                                color: p.textPrimary,
                              ),
                              tooltip: 'Next',
                              onPressed: cubit.next,
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(
                                  minWidth: 34, minHeight: 34),
                              icon: Icon(
                                state.repeatMode == PlayerRepeatMode.one
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                size: 19,
                                color: state.repeatMode != PlayerRepeatMode.off
                                    ? activeColor
                                    : p.textSecondary,
                              ),
                              tooltip: 'Repeat',
                              onPressed: cubit.toggleRepeat,
                            ),
                          ],
                        ),

                        // Seekbar Row
                        Row(
                          children: [
                            Text(
                              Formatters.formatDuration(
                                _dragSeekValue != null
                                    ? Duration(
                                        milliseconds: _dragSeekValue!.toInt())
                                    : state.position,
                              ),
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 11,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3.5,
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 5.5),
                                  overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 11),
                                  activeTrackColor: activeColor,
                                  inactiveTrackColor:
                                      p.textSecondary.withValues(alpha: 0.25),
                                  thumbColor: activeColor,
                                  overlayColor:
                                      activeColor.withValues(alpha: 0.15),
                                ),
                                child: Slider(
                                  min: 0.0,
                                  max: state.duration.inMilliseconds
                                              .toDouble() >
                                          0
                                      ? state.duration.inMilliseconds
                                          .toDouble()
                                      : 1.0,
                                  value: (_dragSeekValue ??
                                          state.position.inMilliseconds
                                              .toDouble())
                                      .clamp(
                                    0.0,
                                    state.duration.inMilliseconds.toDouble() >
                                            0
                                        ? state.duration.inMilliseconds
                                            .toDouble()
                                        : 1.0,
                                  ),
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
                            const SizedBox(width: 8),
                            Text(
                              Formatters.formatDuration(state.duration),
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 11,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // ── Right: Volume & Quick Actions ───────────────────────
                Flexible(
                  flex: 0,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Volume Mute / Slider
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(
                              minWidth: 34, minHeight: 34),
                          icon: Icon(
                            _isMuted || _volume == 0
                                ? Icons.volume_off_rounded
                                : (_volume < 0.5
                                    ? Icons.volume_down_rounded
                                    : Icons.volume_up_rounded),
                            color: p.textSecondary,
                            size: 19,
                          ),
                          tooltip: _isMuted ? 'Unmute' : 'Mute',
                          onPressed: () {
                            setState(() {
                              if (_isMuted) {
                                _volume = _preMuteVolume;
                                _isMuted = false;
                              } else {
                                _preMuteVolume = _volume;
                                _volume = 0.0;
                                _isMuted = true;
                              }
                            });
                            cubit.setVolume(_volume);
                          },
                        ),
                        SizedBox(
                          width: 76,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 4.5),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 9),
                              activeTrackColor: p.textPrimary,
                              inactiveTrackColor:
                                  p.textSecondary.withValues(alpha: 0.25),
                              thumbColor: p.textPrimary,
                            ),
                            child: Slider(
                              min: 0.0,
                              max: 1.0,
                              value: _volume.clamp(0.0, 1.0),
                              onChanged: (v) {
                                setState(() {
                                  _volume = v;
                                  _isMuted = v == 0;
                                });
                                cubit.setVolume(v);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),

                        // DAC / Output
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(
                              minWidth: 34, minHeight: 34),
                          icon: Icon(
                            Icons.settings_input_component_rounded,
                            size: 19,
                            color: settingsState
                                        .currentOutputDevice?.isUsbDac ==
                                    true
                                ? const Color(0xFFFFD700)
                                : p.textSecondary,
                          ),
                          tooltip: 'Audio Output & DAC',
                          onPressed: () => AudioQualitySheet.show(
                              context, song, activeColor),
                        ),

                        // Equalizer
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(
                              minWidth: 34, minHeight: 34),
                          icon: Icon(
                            Icons.equalizer_rounded,
                            size: 19,
                            color: state.isEqEnabled
                                ? activeColor
                                : p.textSecondary,
                          ),
                          tooltip: 'Equalizer',
                          onPressed: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const EqualizerSheet(),
                          ),
                        ),

                        // Queue inspector toggle
                        if (widget.onToggleSideInspector != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(
                                minWidth: 34, minHeight: 34),
                            icon: Icon(
                              Icons.queue_music_rounded,
                              size: 19,
                              color: widget.isInspectorOpen
                                  ? activeColor
                                  : p.textSecondary,
                            ),
                            tooltip: 'Toggle Side Queue',
                            onPressed: widget.onToggleSideInspector,
                          ),

                        // Expand Fullscreen
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(
                              minWidth: 34, minHeight: 34),
                          icon: Icon(
                            Icons.open_in_full_rounded,
                            size: 18,
                            color: p.textSecondary,
                          ),
                          tooltip: 'Fullscreen Player',
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
  }
}
