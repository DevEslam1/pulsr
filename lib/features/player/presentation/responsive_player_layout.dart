// lib/features/player/presentation/responsive_player_layout.dart
import 'dart:ui' show DisplayFeature, DisplayFeatureType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/responsive/pulsr_layout_metrics.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_pressable.dart';
import '../../../core/widgets/pulsr_switch.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'themes/player_theme.dart';
import 'widgets/equalizer_sheet.dart';
import 'widgets/lyrics_view.dart';
import 'widgets/now_playing_queue_view.dart';
import 'widgets/player_controls.dart';
import 'widgets/player_seek_bar.dart';
import 'package:pulsr/core/constants/app_colors.dart';

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
  bool _wasSplitView = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // M-1: Sync manual tab swipes back to PlayerCubit so isLyricsVisible /
    // isQueueVisible always reflects the tab that is actually on screen.
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final cubit = context.read<PlayerCubit>();
    switch (_tabController.index) {
      case 0:
        if (!widget.state.isLyricsVisible) cubit.toggleLyricsVisibility();
      case 1:
        if (!widget.state.isQueueVisible) cubit.toggleQueueVisibility();
      case 2:
        // The DSP tab is not represented by an overlay flag: leaving both set
        // would surface a stale lyrics/queue overlay once the phone layout
        // reads the flags again after rotation.
        cubit.resetOverlayViews();
    }
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

  /// The overlay flags only describe the split-view tabs; once the split layout
  /// is gone they must not leak into the single-pane theme (which would render
  /// the stale lyrics/queue overlay instead of the track view).
  void _clearStaleOverlaysWhenLeavingSplit() {
    if (!_wasSplitView) return;
    _wasSplitView = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.cubit.resetOverlayViews();
    });
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
      _clearStaleOverlaysWhenLeavingSplit();
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
                borderRadius: AppRadii.r20All,
                child: widget.themeWidget,
              ),
            ),
          ),
          // Hinge spacer
          SizedBox(height: hinge.bounds.height),
          // Lower half: Tactile Control Deck
          SizedBox(
            height: bottomHeight,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.specularAt(0.08),
                      AppColors.specularAt(0.03),
                    ],
                  ),
                  borderRadius: AppRadii.r24All,
                  border: Border.all(
                    color: AppColors.specularAt(0.14),
                    width: 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PlayerSeekBar(
                      duration: widget.state.duration,
                      activeColor: widget.activeColor,
                      showUpNext: false,
                      onSeek: (pos) => widget.cubit.seek(pos),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PlayerControls(
                      isPlaying: widget.state.isPlaying,
                      isBuffering: widget.state.isBuffering,
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
          ),
        ],
      );
    }

    // 2. Tablet / Desktop Split-View
    // Must be an actual tablet or desktop (height >= 500) in landscape orientation
    // (width > height) to trigger the 2-pane tablet split.
    // Portrait tablets and landscape phones render the full-screen player theme directly.
    final isLandscapeOrientation =
        width > mediaQuery.size.height || Adaptive.isLandscape(context);
    final isTabletLandscape =
        ((width >= 840 && mediaQuery.size.height >= 500) ||
                (Adaptive.isTablet(context) &&
                    width >= 720 &&
                    mediaQuery.size.height >= 500)) &&
            isLandscapeOrientation;
    if (isTabletLandscape) {
      _wasSplitView = true;
      final p = context.palette;
      return Stack(
        children: [
          // 1. Unified Dynamic Ambient Backdrop (Isolated in RepaintBoundary)
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                children: [
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
                    height: mediaQuery.size.height * 0.75,
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
                    height: mediaQuery.size.height * 0.65,
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
                ],
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
                  child: PlayerSplitViewScope(
                    isInSplitView: true,
                    child: widget.themeWidget,
                  ),
                ),

                // Subtle vertical specular divider between panes
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.specularAt(0.10),
                        AppColors.specularAt(0.10),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.25, 0.75, 1.0],
                    ),
                  ),
                ),

                // Right Pane: Tabbed View (Lyrics by default, Queue, Quick DSP)
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      // Sleek Floating Capsule TabBar at Top Right
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: AppSpacing.sm,
                          bottom: AppSpacing.xs,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.center,
                          child: RepaintBoundary(
                            child: Container(
                              height:
                                  PulsrLayoutMetrics.fieldHeight(context) + 6,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.specularAt(0.10),
                                    AppColors.specularAt(0.05),
                                  ],
                                ),
                                borderRadius: AppRadii.r20All,
                                border: Border.all(
                                  color: AppColors.specularAt(0.15),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.scrimAt(0.24),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TabBar(
                                controller: _tabController,
                                isScrollable: true,
                                tabAlignment: TabAlignment.center,
                                dividerColor: Colors.transparent,
                                indicatorSize: TabBarIndicatorSize.tab,
                                splashBorderRadius: AppRadii.r16All,
                                indicator: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      widget.activeColor
                                          .withValues(alpha: 0.34),
                                      widget.activeColor
                                          .withValues(alpha: 0.18),
                                    ],
                                  ),
                                  borderRadius: AppRadii.r16All,
                                  border: Border.all(
                                    color: widget.activeColor
                                        .withValues(alpha: 0.55),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: widget.activeColor
                                          .withValues(alpha: 0.22),
                                      blurRadius: 12,
                                      spreadRadius: -2,
                                    ),
                                  ],
                                ),
                                labelColor: p.textPrimary,
                                unselectedLabelColor: p.textSecondary,
                                labelStyle: const TextStyle(
                                  fontSize: AppFontSize.label,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                                unselectedLabelStyle: const TextStyle(
                                  fontSize: AppFontSize.label,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
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
                                        const Icon(Icons.tune_rounded,
                                            size: 15),
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
    _clearStaleOverlaysWhenLeavingSplit();
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
    final p = context.palette;
    final l10n = context.l10n;

    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.quickDspControls,
                style: TextStyle(
                  fontSize: AppFontSize.title,
                  fontWeight: FontWeight.w900,
                  color: p.textPrimary,
                  letterSpacing: AppTracking.title,
                ),
              ),
            ),
            PulsrPressable(
              pressedScale: 0.95,
              onTap: () {
                HapticFeedback.lightImpact();
                EqualizerSheet.show(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      activeColor.withValues(alpha: 0.24),
                      activeColor.withValues(alpha: 0.12),
                    ],
                  ),
                  borderRadius: AppRadii.r14All,
                  border: Border.all(
                    color: activeColor.withValues(alpha: 0.45),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: activeColor,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      l10n.equalizer,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w800,
                        color: activeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _DspModuleBentoCard(
          icon: Icons.graphic_eq_rounded,
          title: l10n.eqEngineTitle,
          subtitle: l10n.eqEngineSubtitle,
          value: state.isEqEnabled,
          activeColor: activeColor,
          onChanged: (v) => cubit.setEqualizerEnabled(v),
        ),
        const SizedBox(height: AppSpacing.s10),
        _DspModuleBentoCard(
          icon: Icons.shield_outlined,
          title: l10n.truePeakLimiterTitle,
          subtitle: l10n.truePeakLimiterSubtitle,
          value: state.isLimiterEnabled,
          activeColor: activeColor,
          onChanged: (v) => cubit.setLookaheadLimiter(v),
        ),
        const SizedBox(height: AppSpacing.s10),
        _DspModuleBentoCard(
          icon: Icons.headphones_rounded,
          title: l10n.viperDdcTitle,
          subtitle: state.viperDdcProfileName.isNotEmpty
              ? state.viperDdcProfileName
              : l10n.dspNoProfileLoaded,
          value: state.isViperDdcEnabled,
          activeColor: activeColor,
          onChanged: (v) => cubit.setViperDdcEnabled(v),
        ),
      ],
    );
  }
}

class _DspModuleBentoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _DspModuleBentoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return PulsrPressable(
      pressedScale: 0.985,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: context.motionMs(220),
        curve: context.motionCurve(Curves.easeOutCubic),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.s14,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: value
                ? [
                    activeColor.withValues(alpha: 0.16),
                    activeColor.withValues(alpha: 0.06),
                  ]
                : [
                    AppColors.specularAt(0.07),
                    AppColors.specularAt(0.03),
                  ],
          ),
          borderRadius: AppRadii.r20All,
          border: Border.all(
            color: value
                ? activeColor.withValues(alpha: 0.45)
                : AppColors.specularAt(0.12),
            width: value ? 1.2 : 1.0,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.14),
                    blurRadius: 16,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: context.motionMs(220),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value
                    ? activeColor.withValues(alpha: 0.22)
                    : AppColors.specularAt(0.08),
                border: Border.all(
                  color: value
                      ? activeColor.withValues(alpha: 0.50)
                      : AppColors.specularAt(0.12),
                  width: 1.0,
                ),
              ),
              child: Icon(
                icon,
                size: 20,
                color: value ? activeColor : p.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.s14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: AppFontSize.body,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.bodySmall,
                      fontWeight: FontWeight.w500,
                      color: value
                          ? activeColor.withValues(alpha: 0.90)
                          : p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PulsrSwitch(
              value: value,
              activeColor: activeColor,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
