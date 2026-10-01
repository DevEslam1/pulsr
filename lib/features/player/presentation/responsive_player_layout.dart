// lib/features/player/presentation/responsive_player_layout.dart
import 'dart:ui' show DisplayFeature, DisplayFeatureType;
import 'package:flutter/material.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'widgets/lyrics_view.dart';
import 'widgets/now_playing_queue_view.dart';
import 'widgets/player_controls.dart';
import 'widgets/player_seek_bar.dart';

/// Responsive layout coordinator for the Now Playing screen.
///
/// Automatically adapts between:
/// 1. Tabletop Mode (foldables half-folded along horizontal hinge)
/// 2. Tablet Split-View (screens with width > 840dp)
/// 3. Standard Single-Pane Layout (phones and compact screens)
class ResponsivePlayerLayout extends StatefulWidget {
  final PlayerState state;
  final PlayerCubit cubit;
  final Widget themeWidget;
  final Color activeColor;
  final Color bgColor;

  const ResponsivePlayerLayout({
    super.key,
    required this.state,
    required this.cubit,
    required this.themeWidget,
    required this.activeColor,
    required this.bgColor,
  });

  @override
  State<ResponsivePlayerLayout> createState() => _ResponsivePlayerLayoutState();
}

class _ResponsivePlayerLayoutState extends State<ResponsivePlayerLayout>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didUpdateWidget(ResponsivePlayerLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.isLyricsVisible != oldWidget.state.isLyricsVisible &&
        widget.state.isLyricsVisible &&
        _tabController.index != 0) {
      _tabController.animateTo(0);
    } else if (widget.state.isQueueVisible != oldWidget.state.isQueueVisible &&
        widget.state.isQueueVisible &&
        _tabController.index != 1) {
      _tabController.animateTo(1);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DisplayFeature? _findHorizontalHinge(BuildContext context) {
    for (final feature in MediaQuery.displayFeaturesOf(context)) {
      if ((feature.type == DisplayFeatureType.hinge ||
              feature.type == DisplayFeatureType.fold) &&
          feature.bounds.width > feature.bounds.height) {
        return feature;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width;
    final hinge = _findHorizontalHinge(context);

    // 1. Tabletop Mode for Foldables (horizontal fold detected).
    // A zero-height hinge (degenerate/zero-width report) must not produce a
    // tabletop layout with no usable halves — fall through to split/single pane.
    if (hinge != null && hinge.bounds.height > 0) {
      final topHeight = hinge.bounds.top;
      final bottomHeight = mediaQuery.size.height - hinge.bounds.bottom;

      return Column(
        children: [
          // Upper half: Album Art + Lyrics Focus
          SizedBox(
            height: topHeight,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.r20),
                child: widget.themeWidget,
              ),
            ),
          ),
          // Hinge spacer
          SizedBox(height: hinge.bounds.height),
          // Lower half: Waveform, Transport Controls, and Queue preview
          SizedBox(
            height: bottomHeight,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PlayerSeekBar(
                    position: widget.state.position,
                    duration: widget.state.duration,
                    activeColor: widget.activeColor,
                    showUpNext: false,
                    onSeek: (pos) => widget.cubit.seek(pos),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PlayerControls(
                    isPlaying: widget.state.isPlaying,
                    isShuffle: widget.state.isShuffle,
                    repeatMode: widget.state.repeatMode,
                    primaryColor: widget.activeColor,
                    onPlayPause: () => widget.cubit.togglePlayPause(),
                    onNext: () => widget.cubit.next(),
                    onPrevious: () => widget.cubit.previous(),
                    onToggleShuffle: () => widget.cubit.toggleShuffle(),
                    onToggleRepeat: () => widget.cubit.toggleRepeat(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    widget.state.currentSong?.title ?? '',
                    style: TextStyle(
                      color: widget.activeColor,
                      fontSize: AppFontSize.body,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 2. Tablet / Desktop Split-View
    // Must be an actual tablet or desktop (height >= 550) to prevent landscape phones
    // (which have width 840-932 but height ~360-430) from triggering the 2-pane tablet split.
    // Landscape phones render the immersive full-screen player theme directly.
    final isTabletLandscape = (width >= 840 && mediaQuery.size.height >= 550) ||
        (Adaptive.isTablet(context) &&
            width >= 720 &&
            mediaQuery.size.height >= 550);
    if (isTabletLandscape) {
      final p = context.palette;
      return Stack(
        children: [
          // 1. Unified Dynamic Ambient Backdrop
          Positioned.fill(
            child: AnimatedContainer(
              duration: context.motionMs(500),
              curve: context.motionCurve(Curves.easeInOut),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(widget.bgColor, Colors.black, 0.45) ??
                        widget.bgColor,
                    p.bg,
                    p.deepShade,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.50, 1.0],
                ),
              ),
            ),
          ),

          // Ambient Glow Sphere behind artwork (Left)
          PositionedDirectional(
            top: -40,
            start: -30,
            width: width * 0.52,
            height: 540,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: context.motionMs(500),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.85,
                    colors: [
                      widget.activeColor.withValues(alpha: 0.30),
                      widget.activeColor.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.52, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Ambient Glow Sphere behind lyrics (Right)
          PositionedDirectional(
            top: 40,
            end: -30,
            width: width * 0.50,
            height: 480,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: context.motionMs(500),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.85,
                    colors: [
                      widget.activeColor.withValues(alpha: 0.16),
                      widget.activeColor.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.50, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 2. Foreground 2-Pane Split (Apple Music Element Ordering)
          SafeArea(
            top: true,
            bottom: false,
            child: Row(
              children: [
                // Left Pane: Persistent Full-Fidelity Player Theme (Artwork + Controls Column)
                Expanded(
                  flex: 5,
                  child: widget.themeWidget,
                ),

                // Right Pane: Tabbed View (Lyrics by default, Queue, Quick DSP)
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      // Sleek Floating Capsule TabBar at Top Right
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: AppSpacing.md,
                          bottom: AppSpacing.xs,
                          end: AppSpacing.lg,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(AppRadii.r20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 0.8,
                              ),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              isScrollable: true,
                              tabAlignment: TabAlignment.center,
                              dividerColor: Colors.transparent,
                              indicatorSize: TabBarIndicatorSize.tab,
                              indicator: BoxDecoration(
                                color:
                                    widget.activeColor.withValues(alpha: 0.28),
                                borderRadius:
                                    BorderRadius.circular(AppRadii.r16),
                                border: Border.all(
                                  color: widget.activeColor
                                      .withValues(alpha: 0.45),
                                  width: 1,
                                ),
                              ),
                              labelColor: Colors.white,
                              unselectedLabelColor:
                                  Colors.white.withValues(alpha: 0.60),
                              labelStyle: const TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w700,
                              ),
                              unselectedLabelStyle: const TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w500,
                              ),
                              tabs: [
                                Tab(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.lyrics_rounded,
                                          size: 15),
                                      const SizedBox(width: 6),
                                      Text(context.l10n.lyrics),
                                    ],
                                  ),
                                ),
                                Tab(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.queue_music_rounded,
                                          size: 15),
                                      const SizedBox(width: 6),
                                      Text(context.l10n.queueTab),
                                    ],
                                  ),
                                ),
                                Tab(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.tune_rounded, size: 15),
                                      const SizedBox(width: 6),
                                      Text(context.l10n.dspLabel),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Right Content Views
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // 1. Lyrics View (Tab 0 - default, matching Apple Music iPad)
                            Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                AppSpacing.sm,
                                0,
                                AppSpacing.lg,
                                AppSpacing.md,
                              ),
                              child: LyricsView(
                                key: ValueKey(
                                  'tablet_lyrics_${widget.state.currentSong?.id}_${widget.state.currentSong?.remoteId}',
                                ),
                                lyrics: widget.state.lyrics,
                                isLoading: widget.state.isLoadingLyrics,
                                activeColor: widget.activeColor,
                                source: widget.state.lyricsSource,
                              ),
                            ),
                            // 2. Queue View (Tab 1)
                            const Padding(
                              padding: EdgeInsetsDirectional.fromSTEB(
                                AppSpacing.sm,
                                0,
                                AppSpacing.lg,
                                AppSpacing.md,
                              ),
                              child: NowPlayingQueueView(),
                            ),
                            // 3. Quick DSP Controls (Tab 2)
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: _QuickDspControls(
                                cubit: widget.cubit,
                                state: widget.state,
                                activeColor: widget.activeColor,
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
        ],
      );
    }

    // 3. Single-Pane Layout (Phone / Standard)
    return widget.themeWidget;
  }
}

class _QuickDspControls extends StatelessWidget {
  final PlayerCubit cubit;
  final PlayerState state;
  final Color activeColor;

  const _QuickDspControls({
    required this.cubit,
    required this.state,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(
          context.l10n.quickDspControls,
          style: TextStyle(
            fontSize: AppFontSize.title,
            fontWeight: FontWeight.w800,
            color: activeColor,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SwitchListTile(
          title: Text(context.l10n.eqEngineTitle),
          subtitle: Text(context.l10n.eqEngineSubtitle),
          value: state.isEqEnabled,
          activeTrackColor: activeColor,
          onChanged: (v) => cubit.setEqualizerEnabled(v),
        ),
        SwitchListTile(
          title: Text(context.l10n.truePeakLimiterTitle),
          subtitle: Text(context.l10n.truePeakLimiterSubtitle),
          value: state.isLimiterEnabled,
          activeTrackColor: activeColor,
          onChanged: (v) => cubit.setLookaheadLimiter(v),
        ),
        SwitchListTile(
          title: Text(context.l10n.viperDdcTitle),
          subtitle: Text(
            state.viperDdcProfileName.isNotEmpty
                ? state.viperDdcProfileName
                : context.l10n.dspNoProfileLoaded,
          ),
          value: state.isViperDdcEnabled,
          activeTrackColor: activeColor,
          onChanged: (v) => cubit.setViperDdcEnabled(v),
        ),
      ],
    );
  }
}
