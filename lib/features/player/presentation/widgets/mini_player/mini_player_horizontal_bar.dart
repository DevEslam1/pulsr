// lib/features/player/presentation/widgets/mini_player/mini_player_horizontal_bar.dart
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../../core/motion/pulsr_motion.dart';
import '../../../../../core/theme/aura_theme.dart';
import '../../../../../core/utils/l10n_extensions.dart';
import '../../../../../core/utils/pulsr_haptics.dart';
import '../../../../../core/widgets/cached_artwork.dart';
import '../../../../../core/widgets/marquee_text.dart';
import '../../../../../data/db/app_database.dart';
import '../../../cubit/player_cubit.dart';
import '../../../cubit/player_state.dart';

/// Inner row rendered by [MiniPlayerHorizontal] for landscape phones and medium
/// breakpoint docks. Scales height smoothly for 1.3x–2.0x text accessibility
/// while keeping a 48dp compact footprint at 1.0x text scale.
class MiniPlayerHorizontalBar extends StatelessWidget {
  final PlayerState state;
  final SongsTableData song;
  final PlayerCubit cubit;
  final VoidCallback onTap;

  const MiniPlayerHorizontalBar({
    super.key,
    required this.state,
    required this.song,
    required this.cubit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final activeAccent = p.accent;
    final allowMotion = PulsrMotion.shouldAnimate(context);
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    final barHeight = math.max(48.0, 44.0 * textScale);

    return Semantics(
      label: context.l10n.nowPlayingSemantics(song.title, song.artist),
      button: true,
      customSemanticsActions: {
        CustomSemanticsAction(label: context.l10n.expandPlayer): onTap,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: barHeight,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Row(
                children: [
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.r8All,
                      border: Border.all(
                        color: p.hairline,
                        width: 0.75,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: AppRadii.r8All,
                      child: CachedArtwork(
                        id: song.id,
                        albumId: song.albumId,
                        remoteUrl: song.remoteArtworkUrl,
                        type: ArtworkType.AUDIO,
                        size: 40,
                        borderRadius: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: MediaQuery.withClampedTextScaling(
                      minScaleFactor: 0.8,
                      maxScaleFactor: 2.0,
                      child: AnimatedSwitcher(
                        duration: context.motionMs(200),
                        transitionBuilder: (child, anim) {
                          if (!allowMotion) return child;
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.0, 0.15),
                                end: Offset.zero,
                              ).animate(
                                anim.drive(
                                  CurveTween(
                                    curve: context
                                        .motionCurve(Curves.easeOutCubic),
                                  ),
                                ),
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey('song_meta_${song.id}'),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MarqueeText(
                                text: song.title,
                                textAlign: TextAlign.start,
                                allowUserPause: false,
                                velocity: 28.0,
                                blankSpace: 36.0,
                                style: TextStyle(
                                  fontSize: AppFontSize.bodySmall,
                                  fontWeight: FontWeight.w700,
                                  color: p.textPrimary,
                                  letterSpacing: -0.15,
                                ),
                              ),
                              const SizedBox(height: 1),
                              MarqueeText(
                                text: song.artist,
                                textAlign: TextAlign.start,
                                allowUserPause: false,
                                velocity: 24.0,
                                blankSpace: 32.0,
                                style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w500,
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: state.isPlaying
                        ? context.l10n.pause
                        : context.l10n.play,
                    iconSize: 26,
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget,
                    ),
                    icon: state.isBuffering
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: activeAccent,
                            ),
                          )
                        : Icon(
                            state.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: activeAccent,
                          ),
                    onPressed: () {
                      PulsrHaptics.lightImpact();
                      cubit.togglePlayPause();
                    },
                  ),
                  IconButton(
                    tooltip: context.l10n.next,
                    iconSize: 24,
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget,
                    ),
                    icon: Icon(
                      Icons.skip_next_rounded,
                      color: state.hasNextNeighbour
                          ? p.textPrimary
                          : p.textTertiary.withValues(alpha: 0.38),
                    ),
                    onPressed: state.hasNextNeighbour
                        ? () {
                            PulsrHaptics.selectionClick();
                            cubit.next();
                          }
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ),
              // Subtle bottom progress hairline for horizontal dock
              PositionedDirectional(
                start: AppSpacing.xs,
                end: AppSpacing.xs,
                bottom: 0,
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: BlocSelector<PlayerCubit, PlayerState, Duration>(
                      selector: (s) => s.position,
                      builder: (context, pos) {
                        final frac = state.duration.inMilliseconds > 0
                            ? (pos.inMilliseconds /
                                    state.duration.inMilliseconds)
                                .clamp(0.0, 1.0)
                            : 0.0;
                        return ClipRRect(
                          borderRadius: AppRadii.r1_5All,
                          child: LinearProgressIndicator(
                            value: frac,
                            minHeight: 2.0,
                            backgroundColor:
                                p.textTertiary.withValues(alpha: 0.20),
                            valueColor:
                                AlwaysStoppedAnimation<Color>(activeAccent),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
