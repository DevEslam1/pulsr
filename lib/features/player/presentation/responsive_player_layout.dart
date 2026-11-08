// lib/features/player/presentation/responsive_player_layout.dart
import 'dart:ui' show DisplayFeature, DisplayFeatureType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulsr/core/constants/app_colors.dart';

import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/motion/pulsr_motion.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_pressable.dart';
import '../../../core/widgets/pulsr_switch.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'themes/player_theme.dart';
import 'widgets/equalizer_sheet.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection.dart';
import '../../../../domain/models/quran_metadata.dart';
import '../../../../domain/repositories/quran_repository.dart';
import '../../../../data/repositories/quran_repository_impl.dart';
import 'themes/player_theme_chrome.dart';
import 'widgets/lyrics_view.dart';
import 'widgets/now_playing_queue_view.dart';
import 'widgets/player_controls.dart';
import 'widgets/player_seek_bar.dart';
import 'widgets/quran_mode_sheet.dart';
import 'widgets/quran_mushaf_view.dart';
import 'widgets/player_more_sheet.dart';

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
  QuranMetadata? _quranMetadata;
  String? _lastLoadedQuranUri;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    // If lyrics or queue was active prior to entering split view, open that tab
    if (widget.state.isLyricsVisible) {
      _tabController.index = 0;
    } else if (widget.state.isQueueVisible) {
      _tabController.index = 1;
    }
    _checkQuranMetadata();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 2) {
      widget.cubit.resetOverlayViews();
    }
  }

  void _checkQuranMetadata() {
    final uri = widget.state.currentSong?.uri ?? widget.state.currentSong?.path;
    if (uri == _lastLoadedQuranUri) return;
    _lastLoadedQuranUri = uri;
    if (uri == null || uri.isEmpty) {
      if (mounted) setState(() => _quranMetadata = null);
      return;
    }
    final repo = getIt.isRegistered<QuranRepository>()
        ? getIt<QuranRepository>()
        : QuranRepositoryImpl();
    repo.getMetadataForTrack(uri).then((meta) {
      if (mounted && _lastLoadedQuranUri == uri) {
        setState(() => _quranMetadata = meta);
      }
    }).catchError((_) {
      if (mounted && _lastLoadedQuranUri == uri) {
        setState(() => _quranMetadata = null);
      }
    });
  }

  @override
  void didUpdateWidget(ResponsivePlayerLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.currentSong?.uri != oldWidget.state.currentSong?.uri ||
        widget.state.currentSong?.path != oldWidget.state.currentSong?.path ||
        widget.state.isQuranModeEnabled != oldWidget.state.isQuranModeEnabled) {
      _checkQuranMetadata();
    }
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
    _tabController.removeListener(_onTabChanged);
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
    final p = context.palette;

    // 1. Tabletop Mode for Foldables (horizontal fold detected).
    // A zero-height hinge (degenerate/zero-width report) must not produce a
    // tabletop layout with no usable halves — fall through to split/single pane.
    if (hinge != null && hinge.bounds.height > 0) {
      _clearStaleOverlaysWhenLeavingSplit();
      final topHeight = hinge.bounds.top;
      final bottomHeight = mediaQuery.size.height - hinge.bounds.bottom;

      return _FoldableTabletopLayout(
        topHeight: topHeight,
        hingeHeight: hinge.bounds.height,
        bottomHeight: bottomHeight,
        state: widget.state,
        cubit: widget.cubit,
        themeWidget: widget.themeWidget,
        activeColor: widget.activeColor,
      );
    }

    // 2. Tablet / Desktop Split-View (Apple Music Tablet Landscape)
    final isLandscapeOrientation =
        width > mediaQuery.size.height || Adaptive.isLandscape(context);
    final isTabletLandscape =
        ((width >= 720 && mediaQuery.size.height >= 460) ||
                (Adaptive.isTablet(context) &&
                    width >= 600 &&
                    mediaQuery.size.height >= 400)) &&
            isLandscapeOrientation;
    if (isTabletLandscape) {
      _wasSplitView = true;
      final isQuran = widget.state.isQuranModeEnabled ||
          (widget.state.currentSong?.genre?.toLowerCase().contains('quran') ==
              true);

      return PlayerSplitViewScope(
        isInSplitView: true,
        tabController: _tabController,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Unified Radiant Dynamic Ambient Backdrop (Continuous Edge-to-Edge Canvas)
            Positioned.fill(
              child: RepaintBoundary(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Deep ambient base gradient
                    Positioned.fill(
                      child: AnimatedContainer(
                        duration: context.motionMs(500),
                        curve: context.motionCurve(Curves.easeInOut),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color.lerp(
                                    widget.bgColor,
                                    widget.activeColor,
                                    p.isDark ? 0.16 : 0.10,
                                  ) ??
                                  widget.bgColor,
                              widget.bgColor,
                              Color.lerp(
                                    widget.bgColor,
                                    Colors.black,
                                    p.isDark ? 0.32 : 0.08,
                                  ) ??
                                  widget.bgColor,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Atmospheric Stage Spotlight behind Left Deck (Continuous Full-Canvas Bounds)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: context.motionMs(500),
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(-0.55, -0.22),
                              radius: 1.35,
                              colors: [
                                widget.activeColor.withValues(
                                  alpha: p.isDark ? 0.36 : 0.22,
                                ),
                                widget.activeColor.withValues(
                                  alpha: p.isDark ? 0.14 : 0.08,
                                ),
                                widget.activeColor.withValues(alpha: 0.02),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.45, 0.80, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Soft Atmospheric Aura across Right Canvas
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: context.motionMs(500),
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0.60, 0.15),
                              radius: 1.40,
                              colors: [
                                widget.activeColor.withValues(
                                  alpha: p.isDark ? 0.14 : 0.07,
                                ),
                                widget.activeColor.withValues(
                                  alpha: p.isDark ? 0.04 : 0.02,
                                ),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.55, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Foreground 2-Pane Split Canvas
            SafeArea(
              top: true,
              bottom: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Pane: Navigation Header + Full-Fidelity Player Theme
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AppSpacing.lg,
                        end: AppSpacing.md,
                        top: AppSpacing.xs,
                        bottom: AppSpacing.sm,
                      ),
                      child: Column(
                        children: [
                          PlayerTopBar(
                            props: PlayerThemeProps(
                              state: widget.state,
                              cubit: widget.cubit,
                              activeColor: widget.activeColor,
                              bgColor: widget.bgColor,
                            ),
                            isTablet: true,
                            showMore: false,
                            horizontalPadding: 0,
                            tabletHorizontalPadding: 0,
                            verticalPadding: AppSpacing.s2,
                            onDismiss: () {
                              HapticFeedback.lightImpact();
                              try {
                                final router = GoRouter.of(context);
                                if (router.canPop()) {
                                  router.pop();
                                } else {
                                  router.go('/');
                                }
                              } catch (_) {
                                Navigator.of(context).maybePop();
                              }
                            },
                          ),
                          Expanded(
                            child: widget.themeWidget,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Natural Open Gutter (No hard dividing line, breathing room like Apple Music)
                  const SizedBox(width: AppSpacing.md),

                  // Right Pane: Seamless Apple Music Lyrics & Queue Canvas + Floating Bottom Actions
                  Expanded(
                    flex: 6,
                    child: Stack(
                      children: [
                        // Seamless Full-Bleed Content (TabBarView for Lyrics / Quran, Queue, DSP)
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: AppSpacing.sm,
                              end: AppSpacing.xl,
                              top: AppSpacing.sm,
                              bottom: 64.0,
                            ),
                            child: TabBarView(
                              controller: _tabController,
                              physics: const BouncingScrollPhysics(),
                              children: [
                                // Tab 0: Quran Mushaf View (when Quran track/mode) or Lyrics View
                                if (isQuran)
                                  QuranMushafView(
                                    key: ValueKey(
                                      'tablet_mushaf_${widget.state.currentSong?.uri ?? widget.state.currentSong?.path}_${_quranMetadata?.surahNumber}',
                                    ),
                                    metadata: _quranMetadata,
                                    currentPosition: widget.state.position,
                                    onSeek: (pos) => widget.cubit.seek(pos),
                                    isExpanded: true,
                                  )
                                else
                                  LyricsView(
                                    key: ValueKey(
                                      'tablet_lyrics_${widget.state.currentSong?.id}_${widget.state.currentSong?.remoteId}',
                                    ),
                                    lyrics: widget.state.lyrics,
                                    isLoading: widget.state.isLoadingLyrics,
                                    activeColor: widget.activeColor,
                                    source: widget.state.lyricsSource,
                                  ),

                                // Tab 1: Queue View
                                const NowPlayingQueueView(),

                                // Tab 2: Quick DSP Controls
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
                        ),

                        // Floating Bottom-Right Apple Music Pill Action Dock
                        PositionedDirectional(
                          end: AppSpacing.xl,
                          bottom: AppSpacing.md,
                          child: _TabletLandscapeFloatingDock(
                            controller: _tabController,
                            activeColor: widget.activeColor,
                            isQuran: isQuran,
                            cubit: widget.cubit,
                            props: PlayerThemeProps(
                              state: widget.state,
                              cubit: widget.cubit,
                              activeColor: widget.activeColor,
                              bgColor: widget.bgColor,
                            ),
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
      );
    }

    // 3. Single-Pane Layout (Phone / Standard)
    _clearStaleOverlaysWhenLeavingSplit();
    return widget.themeWidget;
  }
}

/// Foldable Tabletop Mode (Horizontal Hinge Detected):
/// Upper screen renders the showcase player theme; lower half acts as a
/// tactile studio control deck.
class _FoldableTabletopLayout extends StatelessWidget {
  final double topHeight;
  final double hingeHeight;
  final double bottomHeight;
  final PlayerState state;
  final PlayerCubit cubit;
  final Widget themeWidget;
  final Color activeColor;

  const _FoldableTabletopLayout({
    required this.topHeight,
    required this.hingeHeight,
    required this.bottomHeight,
    required this.state,
    required this.cubit,
    required this.themeWidget,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final song = state.currentSong;

    return Column(
      children: [
        // Upper Half: Framed Visual Stage
        SizedBox(
          height: topHeight,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: AppRadii.r24All,
                border: Border.all(
                  color: p.hairline,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: activeColor.withValues(alpha: p.isDark ? 0.14 : 0.08),
                    blurRadius: 24,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: AppRadii.r24All,
                child: themeWidget,
              ),
            ),
          ),
        ),

        // Physical Hinge Spacer
        SizedBox(height: hingeHeight),

        // Lower Half: Tactile Studio Control Deck
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
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    p.surfaceContainer,
                    Color.lerp(
                          p.surfaceContainer,
                          activeColor,
                          p.isDark ? 0.06 : 0.03,
                        ) ??
                        p.surfaceContainer,
                  ],
                ),
                borderRadius: AppRadii.r24All,
                border: Border.all(
                  color: p.hairline,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: p.isDark ? 0.38 : 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompactDeck = constraints.maxHeight < 175;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Top Deck Header: Track Metadata + Quick Console Actions
                      Row(
                        children: [
                          AnimatedContainer(
                            duration: context.motionMs(240),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: state.isPlaying
                                  ? activeColor
                                  : p.textSecondary.withValues(alpha: 0.4),
                              boxShadow: state.isPlaying
                                  ? [
                                      BoxShadow(
                                        color:
                                            activeColor.withValues(alpha: 0.6),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  song?.title ?? '',
                                  style: TextStyle(
                                    color: p.textPrimary,
                                    fontSize: AppFontSize.body,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (!isCompactDeck &&
                                    (song?.artist.isNotEmpty ?? false))
                                  Text(
                                    song!.artist,
                                    style: TextStyle(
                                      color: activeColor,
                                      fontSize: AppFontSize.bodySmall,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _DeckQuickActionButton(
                            icon: Icons.lyrics_rounded,
                            isActive: state.isLyricsVisible,
                            activeColor: activeColor,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              cubit.toggleLyricsVisibility();
                            },
                          ),
                          const SizedBox(width: 6),
                          _DeckQuickActionButton(
                            icon: Icons.queue_music_rounded,
                            isActive: state.isQueueVisible,
                            activeColor: activeColor,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              cubit.toggleQueueVisibility();
                            },
                          ),
                          const SizedBox(width: 6),
                          _DeckQuickActionButton(
                            icon: Icons.tune_rounded,
                            isActive: state.isEqEnabled,
                            activeColor: activeColor,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              EqualizerSheet.show(context);
                            },
                          ),
                        ],
                      ),

                      // Center Seek Bar
                      PlayerSeekBar(
                        duration: state.duration,
                        activeColor: activeColor,
                        showUpNext: false,
                        onSeek: (pos) => cubit.seek(pos),
                      ),

                      // Primary Transport Controls
                      PlayerControls(
                        isPlaying: state.isPlaying,
                        isBuffering: state.isBuffering,
                        isShuffle: state.isShuffle,
                        repeatMode: state.repeatMode,
                        primaryColor: activeColor,
                        onPlayPause: () => cubit.togglePlayPause(),
                        onNext: () => cubit.next(),
                        onPrevious: () => cubit.previous(),
                        onToggleShuffle: () => cubit.toggleShuffle(),
                        onToggleRepeat: () => cubit.toggleRepeat(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DeckQuickActionButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _DeckQuickActionButton({
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PulsrPressable(
      pressedScale: 0.92,
      onTap: onTap,
      child: AnimatedContainer(
        duration: context.motionMs(200),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: AppRadii.r14All,
          color: isActive
              ? activeColor.withValues(alpha: 0.22)
              : AppColors.specularAt(0.06),
          border: Border.all(
            color: isActive
                ? activeColor.withValues(alpha: 0.55)
                : p.hairline,
            width: 1.0,
          ),
        ),
        child: Icon(
          icon,
          size: 17,
          color: isActive ? activeColor : p.textSecondary,
        ),
      ),
    );
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
        // Top Header + Full Equalizer Sheet Trigger
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
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs + 2,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      activeColor.withValues(alpha: 0.28),
                      activeColor.withValues(alpha: 0.14),
                    ],
                  ),
                  borderRadius: AppRadii.r14All,
                  border: Border.all(
                    color: activeColor.withValues(alpha: 0.50),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.16),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                  ],
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

        if (state.isQuranModeEnabled) ...[
          _DspModuleBentoCard(
            icon: Icons.menu_book_rounded,
            title: l10n.quranMode,
            subtitle: '${state.quranReciterStyle.name.toUpperCase()} • ${l10n.dspQuranModeOn}',
            value: true,
            activeColor: AppColors.quranEmerald,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              QuranModeSheet.show(context);
            },
          ),
          const SizedBox(height: AppSpacing.s10),
        ],

        // Interactive Signal Chain Visualizer Strip
        _SignalChainVisualizerStrip(
          isEqEnabled: state.isEqEnabled,
          isDdcEnabled: state.isViperDdcEnabled,
          isLimiterEnabled: state.isLimiterEnabled,
          activeColor: activeColor,
        ),

        const SizedBox(height: AppSpacing.md),

        _DspModuleBentoCard(
          icon: Icons.graphic_eq_rounded,
          title: l10n.eqEngineTitle,
          subtitle: l10n.eqEngineSubtitle,
          value: state.isEqEnabled,
          activeColor: activeColor,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            cubit.setEqualizerEnabled(v);
          },
        ),
        const SizedBox(height: AppSpacing.s10),
        _DspModuleBentoCard(
          icon: Icons.shield_outlined,
          title: l10n.truePeakLimiterTitle,
          subtitle: l10n.truePeakLimiterSubtitle,
          value: state.isLimiterEnabled,
          activeColor: activeColor,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            cubit.setLookaheadLimiter(v);
          },
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
          onChanged: (v) {
            HapticFeedback.selectionClick();
            cubit.setViperDdcEnabled(v);
          },
        ),
      ],
    );
  }
}

/// Visual representation of the real-time C++ DSP chain nodes (`EQ -> DDC -> LIM`).
class _SignalChainVisualizerStrip extends StatelessWidget {
  final bool isEqEnabled;
  final bool isDdcEnabled;
  final bool isLimiterEnabled;
  final Color activeColor;

  const _SignalChainVisualizerStrip({
    required this.isEqEnabled,
    required this.isDdcEnabled,
    required this.isLimiterEnabled,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final anyActive = isEqEnabled || isDdcEnabled || isLimiterEnabled;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.specularAt(p.isDark ? 0.04 : 0.03),
        borderRadius: AppRadii.r16All,
        border: Border.all(
          color: anyActive
              ? activeColor.withValues(alpha: 0.28)
              : p.hairline,
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SignalStageChip(
            label: 'PCM IN',
            icon: Icons.waves_rounded,
            isActive: true,
            activeColor: activeColor,
          ),
          _SignalConnectorLine(
            isActive: isEqEnabled,
            activeColor: activeColor,
          ),
          _SignalStageChip(
            label: 'PEQ',
            icon: Icons.graphic_eq_rounded,
            isActive: isEqEnabled,
            activeColor: activeColor,
          ),
          _SignalConnectorLine(
            isActive: isDdcEnabled,
            activeColor: activeColor,
          ),
          _SignalStageChip(
            label: 'DDC',
            icon: Icons.headphones_rounded,
            isActive: isDdcEnabled,
            activeColor: activeColor,
          ),
          _SignalConnectorLine(
            isActive: isLimiterEnabled,
            activeColor: activeColor,
          ),
          _SignalStageChip(
            label: 'LIM',
            icon: Icons.shield_outlined,
            isActive: isLimiterEnabled,
            activeColor: activeColor,
          ),
        ],
      ),
    );
  }
}

class _SignalStageChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color activeColor;

  const _SignalStageChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: context.motionMs(220),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: isActive
            ? activeColor.withValues(alpha: 0.18)
            : AppColors.specularAt(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? activeColor.withValues(alpha: 0.50)
              : AppColors.specularAt(0.10),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isActive ? activeColor : p.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: isActive ? p.textPrimary : p.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalConnectorLine extends StatelessWidget {
  final bool isActive;
  final Color activeColor;

  const _SignalConnectorLine({
    required this.isActive,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: AnimatedContainer(
        duration: context.motionMs(220),
        height: 1.5,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          color: isActive
              ? activeColor.withValues(alpha: 0.65)
              : p.hairline,
        ),
      ),
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
                    activeColor.withValues(alpha: 0.18),
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
                ? activeColor.withValues(alpha: 0.48)
                : AppColors.specularAt(0.12),
            width: value ? 1.2 : 1.0,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.15),
                    blurRadius: 18,
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value
                    ? activeColor.withValues(alpha: 0.22)
                    : AppColors.specularAt(0.08),
                border: Border.all(
                  color: value
                      ? activeColor.withValues(alpha: 0.55)
                      : AppColors.specularAt(0.12),
                  width: 1.0,
                ),
                boxShadow: value
                    ? [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.25),
                          blurRadius: 10,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.body,
                            fontWeight: FontWeight.w800,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedContainer(
                        duration: context.motionMs(200),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: value
                              ? activeColor
                              : p.textSecondary.withValues(alpha: 0.28),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.bodySmall,
                      fontWeight: FontWeight.w500,
                      color: value
                          ? activeColor.withValues(alpha: 0.92)
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

/// Floating Frosted Pill Action Dock for Tablet Landscape (Apple Music iPad style).
class _TabletLandscapeFloatingDock extends StatelessWidget {
  final TabController controller;
  final Color activeColor;
  final bool isQuran;
  final PlayerCubit cubit;
  final PlayerThemeProps props;

  const _TabletLandscapeFloatingDock({
    required this.controller,
    required this.activeColor,
    required this.isQuran,
    required this.cubit,
    required this.props,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: controller.animation ?? controller,
      builder: (context, _) {
        final currentIdx = controller.index;

        Widget dockButton({
          required IconData icon,
          required String tooltip,
          required bool isSelected,
          required VoidCallback onTap,
        }) {
          return Tooltip(
            message: tooltip,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
                borderRadius: AppRadii.r16All,
                child: AnimatedContainer(
                  duration: context.motionMs(220),
                  curve: context.motionCurve(Curves.easeOutCubic),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0,
                    vertical: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? activeColor.withValues(alpha: isDark ? 0.32 : 0.22)
                        : Colors.transparent,
                    borderRadius: AppRadii.r16All,
                    border: Border.all(
                      color: isSelected
                          ? activeColor.withValues(alpha: isDark ? 0.70 : 0.50)
                          : Colors.transparent,
                      width: 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.32),
                              blurRadius: 12,
                              spreadRadius: -1,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? (isDark ? Colors.white : activeColor)
                        : p.textSecondary.withValues(alpha: 0.70),
                  ),
                ),
              ),
            ),
          );
        }

        return RepaintBoundary(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                props.bgColor.withValues(alpha: isDark ? 0.35 : 0.25),
                p.surfaceContainer.withValues(alpha: isDark ? 0.72 : 0.88),
              ),
              borderRadius: AppRadii.r24All,
              border: Border.all(
                color: Color.alphaBlend(
                  activeColor.withValues(alpha: 0.22),
                  p.hairline,
                ),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                dockButton(
                  icon: isQuran
                      ? Icons.menu_book_rounded
                      : Icons.chat_bubble_rounded,
                  tooltip:
                      isQuran ? context.l10n.quranMode : context.l10n.lyrics,
                  isSelected: currentIdx == 0,
                  onTap: () => controller.animateTo(0),
                ),
                const SizedBox(width: 3),
                dockButton(
                  icon: Icons.format_list_bulleted_rounded,
                  tooltip: context.l10n.queueTab,
                  isSelected: currentIdx == 1,
                  onTap: () => controller.animateTo(1),
                ),
                const SizedBox(width: 3),
                dockButton(
                  icon: Icons.tune_rounded,
                  tooltip: context.l10n.dspLabel,
                  isSelected: currentIdx == 2,
                  onTap: () {
                    cubit.resetOverlayViews();
                    controller.animateTo(2);
                  },
                ),
                const SizedBox(width: 3),
                dockButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: context.l10n.moreOptions,
                  isSelected: false,
                  onTap: () {
                    PlayerMoreSheet.show(
                      context,
                      song: props.state.currentSong,
                      activeColor: activeColor,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}