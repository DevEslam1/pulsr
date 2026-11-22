// lib/features/player/presentation/themes/player_surface_shell.dart
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import 'player_theme.dart';
import 'player_theme_scaffold.dart'
    show PlayerThemeMetrics, PlayerThemePreviewScope;
import 'player_view_switcher.dart' show playerOverlayTransitionBuilder;

/// Builder for a full-screen player theme canvas inside [PlayerSurfaceShell].
typedef PlayerSurfaceBuilder = Widget Function(
  BuildContext context,
  PlayerThemeMetrics metrics,
  bool isInSplitView,
  bool isPreview,
);

/// Lightweight decoupled full-screen shell for Now Playing player themes.
///
/// Unlike [PlayerThemeScaffold], this shell does NOT impose a top header bar,
/// Track/Lyrics/Queue pill bar, standard seek bar, or 7-icon bottom dock.
/// Each theme owns 100% of its full-screen visual identity, typography,
/// transport styling, and compact controls.
///
/// Responsibilities handled automatically by [PlayerSurfaceShell]:
/// 1. `LayoutBuilder` -> [PlayerThemeMetrics] computation.
/// 2. [PlayerSplitViewScope] awareness: in Tablet 2-pane split mode, suppresses
///    outer background, ambient overlay, optional top bar, and inline
///    Lyrics/Queue overlays because `ResponsivePlayerLayout` renders the
///    unified backdrop, top bar, and right-pane tabs.
/// 3. [PlayerThemePreviewScope] awareness: renders a clean, static thumbnail
///    inside Theme Picker and Theme Studio without overlays or transient chrome.
/// 4. [AnimatedSwitcher] with [playerOverlayTransitionBuilder] to seamlessly
///    transition between the theme canvas and the Lyrics (`state.isLyricsVisible`)
///    or Queue (`state.isQueueVisible`) overlays. Themes that render lyrics
///    natively on-canvas (e.g. `LyricsPlayerTheme`) pass
///    `handlesLyricsInline: true` so lyrics are never double-wrapped.
class PlayerSurfaceShell extends StatelessWidget {
  final PlayerThemeProps props;
  final PlayerSurfaceBuilder builder;
  final Widget? background;
  final Widget? ambientOverlay;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)?
      topBarBuilder;
  final bool handlesLyricsInline;
  final bool handlesQueueInline;
  final bool useSafeArea;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)?
      lyricsOverlayBuilder;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)?
      queueOverlayBuilder;
  final Color? overlayBackgroundColor;

  const PlayerSurfaceShell({
    super.key,
    required this.props,
    required this.builder,
    this.background,
    this.ambientOverlay,
    this.topBarBuilder,
    this.handlesLyricsInline = false,
    this.handlesQueueInline = false,
    this.useSafeArea = false,
    this.lyricsOverlayBuilder,
    this.queueOverlayBuilder,
    this.overlayBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final isInSplitView = PlayerSplitViewScope.of(context);
    final isPreview = PlayerThemePreviewScope.of(context);

    final showLyricsOverlay = !isInSplitView &&
        !isPreview &&
        !handlesLyricsInline &&
        state.isLyricsVisible;
    final showQueueOverlay = !isInSplitView &&
        !isPreview &&
        !handlesQueueInline &&
        !showLyricsOverlay &&
        state.isQueueVisible;
    final hasOverlay = showLyricsOverlay || showQueueOverlay;

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = PlayerThemeMetrics.calculate(context, constraints);
        final song = state.currentSong;

        final Widget activeChild;
        if (showLyricsOverlay) {
          activeChild = KeyedSubtree(
            key: ValueKey('surface_lyrics_${song?.id}_${song?.remoteId}'),
            child: lyricsOverlayBuilder != null
                ? lyricsOverlayBuilder!(context, metrics)
                : _SurfaceOverlayPane(
                    props: props,
                    title: context.l10n.lyrics,
                    overlayBackgroundColor: overlayBackgroundColor,
                    isLyrics: true,
                    child: LyricsView(
                      key: ValueKey('lyrics_${song?.id}_${song?.remoteId}'),
                      lyrics: state.lyrics,
                      isLoading: state.isLoadingLyrics,
                      activeColor: props.activeColor,
                      source: state.lyricsSource,
                      transparentBackground: true,
                    ),
                  ),
          );
        } else if (showQueueOverlay) {
          activeChild = KeyedSubtree(
            key: const ValueKey('surface_queue'),
            child: queueOverlayBuilder != null
                ? queueOverlayBuilder!(context, metrics)
                : _SurfaceOverlayPane(
                    props: props,
                    title: context.l10n.queue,
                    overlayBackgroundColor: overlayBackgroundColor,
                    isLyrics: false,
                    child: const NowPlayingQueueView(
                      key: ValueKey('queue_view'),
                    ),
                  ),
          );
        } else {
          final canvas = builder(context, metrics, isInSplitView, isPreview);
          activeChild = KeyedSubtree(
            key: const ValueKey('surface_canvas'),
            child: useSafeArea && !isInSplitView && !isPreview
                ? SafeArea(child: canvas)
                : canvas,
          );
        }

        final Widget switched = (!isInSplitView && !isPreview)
            ? AnimatedSwitcher(
                duration: context.motionMs(320),
                transitionBuilder: (child, anim) =>
                    playerOverlayTransitionBuilder(context, child, anim),
                child: activeChild,
              )
            : activeChild;

        if (isInSplitView) {
          return switched;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            if (background != null)
              Positioned.fill(
                child: ExcludeSemantics(child: background!),
              ),
            if (ambientOverlay != null && !hasOverlay)
              Positioned.fill(
                child: ExcludeSemantics(child: ambientOverlay!),
              ),
            Positioned.fill(child: switched),
            if (topBarBuilder != null && !isPreview && !hasOverlay)
              PositionedDirectional(
                top: 0,
                start: 0,
                end: 0,
                child: SafeArea(
                  top: true,
                  bottom: false,
                  child: topBarBuilder!(context, metrics),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Clean overlay wrapper rendered by [PlayerSurfaceShell] when Lyrics or Queue
/// is active over a full-screen theme. Provides 1-tap return to the Track view
/// plus a compact transport bar so playback remains controllable.
class _SurfaceOverlayPane extends StatelessWidget {
  final PlayerThemeProps props;
  final String title;
  final bool isLyrics;
  final Color? overlayBackgroundColor;
  final Widget child;

  const _SurfaceOverlayPane({
    required this.props,
    required this.title,
    required this.isLyrics,
    required this.child,
    this.overlayBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final state = props.state;
    final cubit = props.cubit;
    final song = state.currentSong;
    final bg = overlayBackgroundColor ??
        (p.isDark ? p.bg.withValues(alpha: 0.94) : p.bg.withValues(alpha: 0.96));

    return ColoredBox(
      color: bg,
      child: SafeArea(
        child: Column(
          children: [
            // Overlay header: Back to Track + Lyrics/Queue switcher + Close
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: l10n.trackNumber,
                    excludeSemantics: true,
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
                      tooltip: l10n.trackNumber,
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: p.textPrimary,
                      ),
                      onPressed: () {
                        PulsrHaptics.selectionClick();
                        cubit.resetOverlayViews();
                      },
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.bodyLarge,
                            fontWeight: FontWeight.w800,
                            color: p.textPrimary,
                          ),
                        ),
                        if (song != null && song.title.trim().isNotEmpty)
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w600,
                              color: p.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    toggled: !isLyrics,
                    label: isLyrics ? l10n.queue : l10n.lyrics,
                    excludeSemantics: true,
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
                      tooltip: isLyrics ? l10n.queue : l10n.lyrics,
                      icon: Icon(
                        isLyrics
                            ? Icons.queue_music_rounded
                            : Icons.lyrics_rounded,
                        color: p.textSecondary,
                      ),
                      onPressed: () {
                        PulsrHaptics.selectionClick();
                        if (isLyrics) {
                          cubit.toggleQueueVisibility();
                        } else {
                          cubit.toggleLyricsVisibility();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Expanded Lyrics / Queue content
            Expanded(child: child),

            // Compact bottom transport bar
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: p.surfaceContainer.withValues(alpha: 0.88),
                border: Border(
                  top: BorderSide(
                    color: p.isDark ? AppColors.specularAt(0.10) : p.hairline,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song?.title ?? l10n.nowPlaying,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.bodySmall,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                        if (song != null && song.artist.trim().isNotEmpty)
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              color: p.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Semantics(
                    button: true,
                    label: l10n.previous,
                    excludeSemantics: true,
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
                      tooltip: l10n.previous,
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        color: p.textPrimary,
                      ),
                      onPressed: () {
                        PulsrHaptics.light();
                        cubit.previous();
                      },
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: state.isPlaying ? l10n.pause : l10n.play,
                    excludeSemantics: true,
                    child: Material(
                      color: props.activeColor,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          PulsrHaptics.lightImpact();
                          cubit.togglePlayPause();
                        },
                        child: SizedBox(
                          width: AppSpacing.minTouchTarget,
                          height: AppSpacing.minTouchTarget,
                          child: Center(
                            child: Icon(
                              state.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: AppColors.textOnAccent(props.activeColor),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l10n.next,
                    excludeSemantics: true,
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
                      tooltip: l10n.next,
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: p.textPrimary,
                      ),
                      onPressed: () {
                        PulsrHaptics.light();
                        cubit.next();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
