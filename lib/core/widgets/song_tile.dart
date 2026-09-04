import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../data/db/app_database.dart';
import '../../core/utils/formatters.dart';
import '../theme/aura_theme.dart';
import 'cached_artwork.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../../features/player/cubit/player_state.dart';

/// The universal premium song row. Auto-highlights the active track with an
/// animated EQ indicator. Reused by Home/Library/Search/Albums/Playlists/etc.
class SongTile extends StatelessWidget {
  final SongsTableData song;
  final VoidCallback onTap;
  final VoidCallback? onMorePressed;
  final String? subtitleOverride;
  final int? index;
  final bool showArtwork;
  final double artworkSize;
  final bool selected;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool? isDownloaded;

  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.onMorePressed,
    this.subtitleOverride,
    this.index,
    this.showArtwork = true,
    this.artworkSize = 52,
    this.selected = false,
    this.onLongPress,
    this.trailing,
    this.isDownloaded,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isCompact = MediaQuery.sizeOf(context).width < 360;
    final effectiveArtworkSize =
        isCompact ? (artworkSize * 0.88).clamp(42.0, 52.0) : artworkSize;

    final isDownloadedTrack = isDownloaded ??
        (song.isDownloaded == true ||
            (song.source == SongSource.local &&
                song.remoteId != null &&
                song.remoteId!.isNotEmpty));

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (a, b) =>
          a.currentSong?.id != b.currentSong?.id || a.isPlaying != b.isPlaying,
      builder: (context, playerState) {
        final isActive = playerState.currentSong?.id == song.id;
        final isPlaying = isActive && playerState.isPlaying;

        return Semantics(
          label: '${song.title} by ${song.artist}',
          button: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Material(
              color: selected ? p.accentContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                onLongPress: onLongPress,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      if (index != null)
                        SizedBox(
                          width: isCompact ? 24 : 32,
                          child: Center(
                            child: Text(
                              '${index! + 1}',
                              style: TextStyle(
                                color: isActive ? p.accent : p.textTertiary,
                                fontWeight: FontWeight.w700,
                                fontSize: isCompact ? 12 : 13,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (showArtwork) ...[
                        SizedBox(
                          width: effectiveArtworkSize,
                          height: effectiveArtworkSize,
                          child: selected
                              ? Container(
                                  decoration: BoxDecoration(
                                    color: p.accent,
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(Icons.check_rounded,
                                      color: p.onAccent, size: 24),
                                )
                              : Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CachedArtwork(
                                      id: song.id,
                                      remoteUrl: song.remoteArtworkUrl,
                                      type: ArtworkType.AUDIO,
                                      size: effectiveArtworkSize,
                                      borderRadius: 13,
                                    ),
                                    if (isActive)
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.45),
                                          borderRadius:
                                              BorderRadius.circular(13),
                                        ),
                                        child: Center(
                                          child: NowPlayingIndicator(
                                              color: p.accent,
                                              isPlaying: isPlaying),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                        SizedBox(width: isCompact ? 8 : 12),
                      ],
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isActive ? p.accent : p.textPrimary,
                                fontWeight: isActive
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontSize: isCompact ? 13.5 : 14.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (isDownloadedTrack) ...[
                                  Icon(
                                    Icons.download_done_rounded,
                                    size: isCompact ? 12 : 13,
                                    color: p.accent,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Text(
                                    subtitleOverride ?? song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: isCompact ? 11.5 : 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (song.durationMs > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          Formatters.formatDurationMs(song.durationMs),
                          style: TextStyle(
                            color: p.textTertiary,
                            fontSize: isCompact ? 11 : 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                      if (trailing != null)
                        trailing!
                      else if (onMorePressed != null)
                        IconButton(
                          icon: Icon(Icons.more_vert_rounded,
                              size: 20, color: p.textTertiary),
                          onPressed: onMorePressed,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Animated 3-bar "now playing" EQ glyph.
class NowPlayingIndicator extends StatefulWidget {
  final Color color;
  final bool isPlaying;
  const NowPlayingIndicator(
      {super.key, required this.color, this.isPlaying = true});

  @override
  State<NowPlayingIndicator> createState() => _NowPlayingIndicatorState();
}

class _NowPlayingIndicatorState extends State<NowPlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.isPlaying) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(NowPlayingIndicator old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying != old.isPlaying) {
      if (widget.isPlaying) {
        _c.repeat(reverse: true);
      } else {
        _c.value = 0.0;
        _c.stop();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return SizedBox(
          width: 18,
          height: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final phase = _c.value * math.pi + i * 0.9;
              final h =
                  widget.isPlaying ? 5 + (math.sin(phase).abs() * 11) : 5.0;
              return Container(
                width: 3.5,
                height: h,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
