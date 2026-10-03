import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/performance/gpu_budget.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/pulsr_logo.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../nav_destinations.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

/// The 4 navigation rail display modes based on screen width/posture.
enum SidebarRailMode {
  hidden,
  iconOnly,
  compact,
  expanded,
}

class LandscapeSidebar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool isExtended;
  final VoidCallback onToggleExtended;
  final VoidCallback? onOpenNowPlaying;
  final VoidCallback? onToggleSideInspector;
  final bool isSideInspectorOpen;
  final Map<int, int>? badgeCounts;
  final SidebarRailMode? modeOverride;

  const LandscapeSidebar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.isExtended,
    required this.onToggleExtended,
    this.onOpenNowPlaying,
    this.onToggleSideInspector,
    this.isSideInspectorOpen = false,
    this.badgeCounts,
    this.modeOverride,
  });

  static SidebarRailMode resolveMode({
    required BuildContext context,
    SidebarRailMode? modeOverride,
    bool isExtended = false,
    bool isPeeking = false,
  }) {
    if (modeOverride != null) return modeOverride;
    if (isExtended || isPeeking) return SidebarRailMode.expanded;

    final breakpoint = PulsrBreakpoint.of(context);
    final isLandscape = PulsrBreakpoint.isLandscape(context);

    switch (breakpoint) {
      case PulsrBreakpoint.large:
        return SidebarRailMode.expanded;
      case PulsrBreakpoint.expanded:
        return isLandscape ? SidebarRailMode.compact : SidebarRailMode.iconOnly;
      case PulsrBreakpoint.medium:
        return isLandscape ? SidebarRailMode.compact : SidebarRailMode.iconOnly;
      case PulsrBreakpoint.compact:
        return isLandscape ? SidebarRailMode.iconOnly : SidebarRailMode.hidden;
    }
  }

  @override
  State<LandscapeSidebar> createState() => LandscapeSidebarState();
}

class LandscapeSidebarState extends State<LandscapeSidebar> {
  bool _isPeeking = false;
  Timer? _peekTimer;
  Orientation? _lastOrientation;

  @visibleForTesting
  bool get isPeeking => _isPeeking;

  @visibleForTesting
  void triggerPeek() => _triggerPeek();

  void _triggerPeek() {
    _peekTimer?.cancel();
    setState(() => _isPeeking = true);
    _peekTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isPeeking = false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (_lastOrientation != null && _lastOrientation != orientation) {
      if (_isPeeking) {
        _peekTimer?.cancel();
        _peekTimer = null;
        _isPeeking = false;
      }
    }
    _lastOrientation = orientation;
  }

  @override
  void didUpdateWidget(LandscapeSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExtended != oldWidget.isExtended ||
        widget.modeOverride != oldWidget.modeOverride) {
      if (_isPeeking) {
        _peekTimer?.cancel();
        _peekTimer = null;
        _isPeeking = false;
      }
    }
  }

  @override
  void dispose() {
    _peekTimer?.cancel();
    super.dispose();
  }

  SidebarRailMode _resolveMode(BuildContext context) =>
      LandscapeSidebar.resolveMode(
        context: context,
        modeOverride: widget.modeOverride,
        isExtended: widget.isExtended,
        isPeeking: _isPeeking,
      );

  @override
  Widget build(BuildContext context) {
    final mode = _resolveMode(context);
    if (mode == SidebarRailMode.hidden) return const SizedBox.shrink();

    final p = context.palette;
    final double width = switch (mode) {
      SidebarRailMode.hidden => 0.0,
      SidebarRailMode.iconOnly => 56.0,
      SidebarRailMode.compact => 64.0,
      SidebarRailMode.expanded => 240.0,
    };

    final double iconSize = switch (mode) {
      SidebarRailMode.hidden => 0.0,
      SidebarRailMode.iconOnly => 20.0,
      SidebarRailMode.compact => 22.0,
      SidebarRailMode.expanded => 24.0,
    };

    final double horizontalPadding = switch (mode) {
      SidebarRailMode.hidden => 0.0,
      SidebarRailMode.iconOnly => 8.0,
      SidebarRailMode.compact => 10.0,
      SidebarRailMode.expanded => 12.0,
    };

    final isExtended = mode == SidebarRailMode.expanded;
    final showCompactLabel = mode == SidebarRailMode.compact;
    final targetContentWidth = isExtended ? 240.0 : width;

    final destinations = pulsrDestinations(context);
    final primaryItems = destinations.where((d) => d.index <= 2);
    final secondaryItems = destinations.where((d) => d.index >= 3);
    final safePadding = MediaQuery.paddingOf(context);
    final leftInset = safePadding.left;
    final totalWidth = width > 0 ? (width + leftInset) : 0.0;

    return MouseRegion(
      onEnter: (_) {
        if (mode == SidebarRailMode.iconOnly) _triggerPeek();
      },
      child: GestureDetector(
        onLongPress: mode == SidebarRailMode.iconOnly ? _triggerPeek : null,
        child: AnimatedContainer(
          duration: context.motionMs(240),
          curve: context.motionCurve(Curves.easeOutCubic),
          width: totalWidth,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                GpuBudget.isGpuSaverActive
                    ? p.surface
                    : p.surface.withValues(alpha: p.isDark ? 0.78 : 0.88),
                GpuBudget.isGpuSaverActive
                    ? p.surfaceContainer
                    : p.surfaceContainer
                        .withValues(alpha: p.isDark ? 0.72 : 0.84),
              ],
            ),
            border: BorderDirectional(
              end: BorderSide(
                color: p.isDark
                    ? AppColors.specularStrong
                    : AppColors.scrimAt(0.08),
                width: 1.2,
              ),
            ),
          ),
          child: ClipRect(
            child: Builder(
              builder: (context) {
                final sidebarBody = Padding(
                  padding: EdgeInsetsDirectional.only(start: leftInset),
                  child: SafeArea(
                    top: true,
                    bottom: true,
                    left: false,
                    right: false,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: SizedBox(
                            width: targetContentWidth,
                            height: constraints.maxHeight,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ── Brand Header ──────────────────────────────────────────
                                _SidebarBrandHeader(
                                  isExtended: isExtended,
                                  onToggle: widget.onToggleExtended,
                                  p: p,
                                ),

                                const SizedBox(height: AppSpacing.s6),

                                // ── Main Scrollable Nav List ──────────────────────────────
                                Expanded(
                                  child: ListView(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: horizontalPadding,
                                      vertical: AppSpacing.xxs,
                                    ),
                                    children: [
                                      if (isExtended)
                                        _SectionHeader(
                                            title: context.l10n.sidebarBrowse,
                                            p: p),
                                      for (final item in primaryItems) ...[
                                        _SidebarNavItem(
                                          icon: item.icon,
                                          activeIcon: item.activeIcon,
                                          label: item.label,
                                          isSelected:
                                              widget.currentIndex == item.index,
                                          isExtended: isExtended,
                                          iconSize: iconSize,
                                          showCompactLabel: showCompactLabel,
                                          badgeCount:
                                              widget.badgeCounts?[item.index],
                                          p: p,
                                          onTap: () {
                                            if (widget.currentIndex !=
                                                item.index) {
                                              widget.onDestinationSelected(
                                                  item.index);
                                            }
                                          },
                                        ),
                                        const SizedBox(height: AppSpacing.xxs),
                                      ],

                                      const SizedBox(height: AppSpacing.s10),
                                      if (isExtended)
                                        _SectionHeader(
                                            title:
                                                context.l10n.sidebarCollection,
                                            p: p)
                                      else
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: AppSpacing.s14,
                                              vertical: AppSpacing.s6),
                                          child: Divider(
                                            height: 1,
                                            thickness: 1,
                                            color: p.hairline
                                                .withValues(alpha: 0.3),
                                          ),
                                        ),

                                      for (final item in secondaryItems) ...[
                                        _SidebarNavItem(
                                          icon: item.icon,
                                          activeIcon: item.activeIcon,
                                          label: item.label,
                                          isSelected:
                                              widget.currentIndex == item.index,
                                          isExtended: isExtended,
                                          iconSize: iconSize,
                                          showCompactLabel: showCompactLabel,
                                          badgeCount:
                                              widget.badgeCounts?[item.index],
                                          p: p,
                                          onTap: () {
                                            if (widget.currentIndex !=
                                                item.index) {
                                              widget.onDestinationSelected(
                                                  item.index);
                                            }
                                          },
                                        ),
                                        const SizedBox(height: AppSpacing.xxs),
                                      ],

                                      // Optional Side Inspector (Queue/Lyrics) Shortcut
                                      if (widget.onToggleSideInspector !=
                                          null) ...[
                                        const SizedBox(height: AppSpacing.s10),
                                        if (isExtended)
                                          _SectionHeader(
                                              title: context.l10n.sidebarPanel,
                                              p: p)
                                        else
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: AppSpacing.s14,
                                                vertical: AppSpacing.s6),
                                            child: Divider(
                                              height: 1,
                                              thickness: 1,
                                              color: p.hairline
                                                  .withValues(alpha: 0.3),
                                            ),
                                          ),
                                        _SidebarNavItem(
                                          icon: Icons.vertical_split_outlined,
                                          activeIcon:
                                              Icons.vertical_split_rounded,
                                          label: context.l10n.sidebarSidePanel,
                                          isSelected:
                                              widget.isSideInspectorOpen,
                                          isExtended: isExtended,
                                          iconSize: iconSize,
                                          showCompactLabel: showCompactLabel,
                                          p: p,
                                          trailingBadge: isExtended &&
                                                  widget.isSideInspectorOpen
                                              ? context.l10n.badgeOn
                                              : null,
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            widget.onToggleSideInspector!();
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // ── Bottom Section: Active Song Badge & Collapse Toggle ────
                                _SidebarBottomSection(
                                  isExtended: isExtended,
                                  p: p,
                                  onOpenNowPlaying: widget.onOpenNowPlaying,
                                  onToggleExtended: widget.onToggleExtended,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );

                if (GpuBudget.isGpuSaverActive) {
                  return sidebarBody;
                }
                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: sidebarBody,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarBrandHeader extends StatelessWidget {
  final bool isExtended;
  final VoidCallback onToggle;
  final PulsrPalette p;

  const _SidebarBrandHeader({
    required this.isExtended,
    required this.onToggle,
    required this.p,
  });

  @override
  Widget build(BuildContext context) {
    if (!isExtended) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
            0, AppSpacing.md, 0, AppSpacing.xs),
        child: Center(
          child: GestureDetector(
            onTap: onToggle,
            child: Tooltip(
              message: context.l10n.sidebarExpand,
              child: PulsrLogo(
                size: 32,
                color: p.accent,
                glowColor: p.glow,
                animate: false,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.xs),
      child: ClipRect(
        child: Row(
          children: [
            PulsrLogo(
              size: 32,
              color: p.accent,
              glowColor: p.glow,
              animate: false,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PULSR',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: AppTracking.widest,
                      fontSize: AppFontSize.bodyLarge,
                    ),
                  ),
                  Text(
                    context.l10n.studioAudio,
                    style: TextStyle(
                      color: p.accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: AppTracking.wide,
                      fontSize: AppFontSize.micro,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.sidebarCollapse,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.keyboard_double_arrow_left_rounded,
                color: p.textTertiary,
              ),
              onPressed: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final PulsrPalette p;

  const _SectionHeader({required this.title, required this.p});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.sm, AppSpacing.s6, AppSpacing.sm, AppSpacing.s6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: AppFontSize.tiny,
          fontWeight: FontWeight.w800,
          letterSpacing: AppTracking.wide,
          color: p.textTertiary.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final bool isExtended;
  final double iconSize;
  final bool showCompactLabel;
  final PulsrPalette p;
  final VoidCallback onTap;
  final String? trailingBadge;
  final int? badgeCount;

  const _SidebarNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.isExtended,
    required this.iconSize,
    required this.showCompactLabel,
    required this.p,
    required this.onTap,
    this.trailingBadge,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = p.accent;

    if (!isExtended) {
      return Semantics(
        selected: isSelected,
        button: true,
        label: label,
        excludeSemantics: true,
        child: Center(
          child: Tooltip(
            message: label,
            waitDuration: const Duration(milliseconds: 350),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppRadii.r14),
                splashColor: activeColor.withValues(alpha: 0.15),
                highlightColor: Colors.transparent,
                child: AnimatedContainer(
                  duration: context.motionMs(200),
                  curve: context.motionCurve(Curves.easeOutCubic),
                  height: showCompactLabel ? 52 : 46,
                  width: showCompactLabel ? 52 : 46,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? activeColor.withValues(alpha: p.isDark ? 0.18 : 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.r14),
                    border: isSelected
                        ? Border.all(
                            color: activeColor.withValues(alpha: 0.35),
                            width: 1.2,
                          )
                        : Border.all(color: Colors.transparent, width: 1.2),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.20),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: AnimatedScale(
                      scale: isSelected ? 1.08 : 1.0,
                      duration: context.motionMs(180),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          (badgeCount != null && badgeCount! > 0)
                              ? Badge(
                                  label: Text(
                                    badgeCount! > 99 ? '99+' : '$badgeCount',
                                    style: const TextStyle(
                                      fontSize: AppFontSize.micro,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  backgroundColor: activeColor,
                                  textColor: p.onAccent,
                                  child: Icon(
                                    isSelected ? activeIcon : icon,
                                    size: iconSize,
                                    color: isSelected
                                        ? activeColor
                                        : p.textSecondary,
                                  ),
                                )
                              : Icon(
                                  isSelected ? activeIcon : icon,
                                  size: iconSize,
                                  color: isSelected
                                      ? activeColor
                                      : p.textSecondary,
                                ),
                          if (showCompactLabel) ...[
                            const SizedBox(height: 2),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.micro,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color:
                                    isSelected ? activeColor : p.textTertiary,
                              ),
                            ),
                          ],
                        ],
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

    return Semantics(
      selected: isSelected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.r12),
          splashColor: activeColor.withValues(alpha: 0.12),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: context.motionMs(200),
            curve: context.motionCurve(Curves.easeOutCubic),
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: p.isDark ? 0.14 : 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.r12),
              border: isSelected
                  ? Border.all(
                      color: activeColor.withValues(alpha: 0.30),
                      width: 1.0,
                    )
                  : Border.all(color: Colors.transparent, width: 1.0),
            ),
            child: ClipRect(
              child: Row(
                children: [
                  // Indicator Bar
                  AnimatedContainer(
                    duration: context.motionMs(180),
                    width: 3.5,
                    height: isSelected ? 18 : 0,
                    decoration: BoxDecoration(
                      color: isSelected ? activeColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadii.r2),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: activeColor.withValues(alpha: 0.6),
                                blurRadius: 5,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),

                  // Icon
                  AnimatedScale(
                    scale: isSelected ? 1.06 : 1.0,
                    duration: context.motionMs(180),
                    child: Icon(
                      isSelected ? activeIcon : icon,
                      size: iconSize,
                      color: isSelected ? activeColor : p.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),

                  // Label
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSize.bodySmall,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? activeColor : p.textPrimary,
                        letterSpacing: AppTracking.label,
                      ),
                    ),
                  ),

                  // Trailing Badge (e.g. Side Panel 'ON' or badgeCount)
                  if (trailingBadge != null ||
                      (badgeCount != null && badgeCount! > 0))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppRadii.r6),
                      ),
                      child: Text(
                        trailingBadge ??
                            (badgeCount! > 99 ? '99+' : '$badgeCount'),
                        style: TextStyle(
                          fontSize: AppFontSize.tiny,
                          fontWeight: FontWeight.w800,
                          color: activeColor,
                          letterSpacing: AppTracking.overline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarBottomSection extends StatelessWidget {
  final bool isExtended;
  final PulsrPalette p;
  final VoidCallback? onOpenNowPlaying;
  final VoidCallback onToggleExtended;

  const _SidebarBottomSection({
    required this.isExtended,
    required this.p,
    required this.onOpenNowPlaying,
    required this.onToggleExtended,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.currentSong != curr.currentSong ||
          prev.isPlaying != curr.isPlaying,
      builder: (context, state) {
        final song = state.currentSong;

        return Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            isExtended ? 12 : 8,
            AppSpacing.xs,
            isExtended ? 12 : 8,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Now Playing Mini Badge (if active song exists)
              if (song != null) ...[
                if (!isExtended)
                  Tooltip(
                    message: '${song.title} - ${song.artist}',
                    child: GestureDetector(
                      onTap: onOpenNowPlaying,
                      child: Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.only(bottom: AppSpacing.s10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadii.r12),
                          border: Border.all(
                            color: state.isPlaying
                                ? p.accent.withValues(alpha: 0.6)
                                : p.hairline,
                            width: 1.2,
                          ),
                          boxShadow: state.isPlaying
                              ? [
                                  BoxShadow(
                                    color: p.accent.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.r12),
                          child: CachedArtwork(
                            id: song.id,
                            remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                            type: ArtworkType.AUDIO,
                            size: 44,
                            borderRadius: 11,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: onOpenNowPlaying,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs, vertical: AppSpacing.s6),
                      decoration: BoxDecoration(
                        color: p.surfaceContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(AppRadii.r10),
                        border: Border.all(
                          color: p.hairline.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: ClipRect(
                        child: Row(
                          children: [
                            CachedArtwork(
                              id: song.id,
                              remoteUrl:
                                  song.remoteArtworkUrl ?? song.artworkUri,
                              type: ArtworkType.AUDIO,
                              size: 28,
                              borderRadius: 6,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: AppFontSize.label,
                                      fontWeight: FontWeight.w700,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: AppFontSize.tiny,
                                      color: p.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (state.isPlaying)
                              Icon(
                                Icons.graphic_eq_rounded,
                                size: 16,
                                color: p.accent,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],

              // Expand / Collapse Bottom Trigger (for collapsed mode)
              if (!isExtended)
                IconButton(
                  constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget),
                  tooltip: context.l10n.sidebarExpand,
                  iconSize: 20,
                  icon: Icon(
                    Icons.keyboard_double_arrow_right_rounded,
                    color: p.textTertiary,
                  ),
                  onPressed: onToggleExtended,
                ),
            ],
          ),
        );
      },
    );
  }
}
