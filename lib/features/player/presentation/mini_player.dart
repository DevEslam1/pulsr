import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/spinning_vinyl_disc.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';

class MiniPlayer extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onSwipeDown;
  final VoidCallback? onSwipeUp;

  const MiniPlayer({
    super.key,
    required this.onTap,
    this.onSwipeDown,
    this.onSwipeUp,
  });

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  PageController? _pageController;
  int _lastKnownIndex = -1;
  bool _isSwipingPage = false;
  double _verticalDragDy = 0.0;

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _syncPageController(int targetIndex, int queueLength) {
    if (queueLength == 0) return;
    final safeIndex = targetIndex.clamp(0, queueLength - 1);
    if (_pageController == null) {
      _lastKnownIndex = safeIndex;
      _pageController = PageController(initialPage: safeIndex);
    } else if (!_isSwipingPage && _lastKnownIndex != safeIndex) {
      _lastKnownIndex = safeIndex;
      if (_pageController!.hasClients &&
          _pageController!.page?.round() != safeIndex) {
        _pageController!.jumpToPage(safeIndex);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = context.watch<SettingsCubit>().state;
    final p = context.palette;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (a, b) =>
          a.currentSong?.id != b.currentSong?.id ||
          a.currentSong?.title != b.currentSong?.title ||
          a.currentSong?.artist != b.currentSong?.artist ||
          a.currentSong?.remoteArtworkUrl != b.currentSong?.remoteArtworkUrl ||
          a.isPlaying != b.isPlaying ||
          a.duration != b.duration ||
          a.currentIndex != b.currentIndex ||
          a.queue.length != b.queue.length,
      builder: (context, state) {
        final song = state.currentSong;
        if (song == null) return const SizedBox.shrink();

        final cubit = context.read<PlayerCubit>();
        final activeAccent = p.accent;
        final queue = state.queue.isNotEmpty ? state.queue : [song];
        final currentIndex = state.currentIndex.clamp(0, queue.length - 1);

        _syncPageController(currentIndex, queue.length);

        return Semantics(
          label: 'Now playing: ${song.title} by ${song.artist}',
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) {
              _verticalDragDy = 0.0;
            },
            onVerticalDragUpdate: (d) {
              _verticalDragDy += d.delta.dy;
            },
            onVerticalDragEnd: (d) {
              final vy = d.velocity.pixelsPerSecond.dy;
              if (_verticalDragDy > 25 || vy > 120) {
                widget.onSwipeDown?.call();
              } else if (_verticalDragDy < -25 || vy < -120) {
                if (widget.onSwipeUp != null) {
                  widget.onSwipeUp!();
                } else {
                  widget.onTap();
                }
              }
              _verticalDragDy = 0.0;
            },
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 8),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: AppRadii.miniPlayerRadius,
                  boxShadow: [
                    BoxShadow(
                      color: activeAccent.withValues(
                          alpha: p.isDark ? 0.22 : 0.15),
                      blurRadius: 18,
                      spreadRadius: -2,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: p.isDark ? 0.45 : 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: GlassContainer(
                  blur: 20,
                  opacity: p.isDark ? 0.93 : 0.97,
                  borderRadius: AppRadii.miniPlayerRadius,
                  color: Color.alphaBlend(
                    activeAccent.withValues(alpha: p.isDark ? 0.12 : 0.08),
                    p.surface,
                  ),
                  border: Border.all(
                    color: activeAccent.withValues(alpha: 0.26),
                    width: 1.2,
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadii.miniPlayerRadius,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                            child: Row(
                              children: [
                                // Interactive Swipeable Track Info Carousel
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: PageView.builder(
                                      controller: _pageController,
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: queue.length,
                                      onPageChanged: (page) {
                                        if (page != currentIndex &&
                                            !_isSwipingPage) {
                                          _isSwipingPage = true;
                                          _lastKnownIndex = page;
                                          cubit.skipToQueueItem(page);
                                          Future.delayed(
                                              const Duration(milliseconds: 300),
                                              () {
                                            if (mounted) {
                                              _isSwipingPage = false;
                                            }
                                          });
                                        }
                                      },
                                      itemBuilder: (context, index) {
                                        final item = queue[index];
                                        final isCurrent = index == currentIndex;

                                        return GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: widget.onTap,
                                          child: Row(
                                            children: [
                                              // Artwork or Vinyl Disc
                                              if (settingsState
                                                      .playerThemeMode ==
                                                  PlayerThemeMode.vinyl)
                                                SpinningVinylDisc(
                                                  id: item.id,
                                                  remoteArtworkUrl:
                                                      item.remoteArtworkUrl,
                                                  size: 46,
                                                  isPlaying: state.isPlaying &&
                                                      isCurrent,
                                                )
                                              else
                                                Hero(
                                                  tag: isCurrent
                                                      ? 'now_playing_art_mini'
                                                      : 'queue_art_$index',
                                                  child: CachedArtwork(
                                                    id: item.id,
                                                    remoteUrl:
                                                        item.remoteArtworkUrl,
                                                    type: ArtworkType.AUDIO,
                                                    size: 46,
                                                    borderRadius: 12,
                                                  ),
                                                ),
                                              const SizedBox(width: 12),
                                              // Track title & artist
                                              Expanded(
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      item.title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: isCurrent
                                                            ? p.textPrimary
                                                            : p.textSecondary,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 14.5,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      item.artist,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: p.textSecondary,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Controls
                                IconButton(
                                  tooltip: state.isPlaying
                                      ? context.l10n.pause
                                      : context.l10n.play,
                                  icon: Icon(
                                    state.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: activeAccent,
                                    size: 32,
                                  ),
                                  onPressed: cubit.togglePlayPause,
                                ),
                                IconButton(
                                  tooltip: context.l10n.next,
                                  icon: Icon(
                                    Icons.skip_next_rounded,
                                    color: p.textPrimary,
                                    size: 28,
                                  ),
                                  onPressed: cubit.next,
                                ),
                              ],
                            ),
                          ),
                        ),
                        _MiniPlayerProgressBar(
                          duration: state.duration,
                          activeAccent: activeAccent,
                          hairlineColor: p.hairline,
                          onSeek: (pos) => cubit.seek(pos),
                        ),
                      ],
                    ),
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

class _MiniPlayerProgressBar extends StatelessWidget {
  final Duration duration;
  final Color activeAccent;
  final Color hairlineColor;
  final void Function(Duration) onSeek;

  const _MiniPlayerProgressBar({
    required this.duration,
    required this.activeAccent,
    required this.hairlineColor,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          return BlocSelector<PlayerCubit, PlayerState, Duration>(
            selector: (s) => s.position,
            builder: (context, position) {
              final progress = duration.inMilliseconds > 0
                  ? (position.inMilliseconds / duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                  : 0.0;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  if (trackWidth > 0 && duration.inMilliseconds > 0) {
                    final ratio =
                        (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                    final seekMs = (duration.inMilliseconds * ratio).round();
                    onSeek(Duration(milliseconds: seekMs));
                  }
                },
                onHorizontalDragStart: (_) {},
                onHorizontalDragUpdate: (details) {
                  if (trackWidth > 0 && duration.inMilliseconds > 0) {
                    final ratio =
                        (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                    final seekMs = (duration.inMilliseconds * ratio).round();
                    onSeek(Duration(milliseconds: seekMs));
                  }
                },
                child: SizedBox(
                  height: 4.5,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                            color: hairlineColor.withValues(alpha: 0.35)),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 4.5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  activeAccent.withValues(alpha: 0.7),
                                  activeAccent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: activeAccent.withValues(alpha: 0.45),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
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
      ),
    );
  }
}
