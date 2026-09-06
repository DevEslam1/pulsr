import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import '../../../player/presentation/mini_player.dart';
import '../bottom_nav_bar.dart';

enum DockStackMode {
  /// Default: MiniPlayer is placed above BottomNavBar in vertical order.
  defaultLayout,

  /// Stacked: MiniPlayer is stacked on the BottomNavBar (in front).
  miniPlayerOnTop,

  /// Stacked: BottomNavBar is in front, MiniPlayer is stacked behind it.
  navBarOnTop,
}

class StackedBottomDock extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTapNav;
  final VoidCallback onOpenNowPlaying;
  final DockStackMode mode;
  final ValueChanged<DockStackMode> onModeChanged;

  const StackedBottomDock({
    super.key,
    required this.currentIndex,
    required this.onTapNav,
    required this.onOpenNowPlaying,
    required this.mode,
    required this.onModeChanged,
  });

  @override
  State<StackedBottomDock> createState() => _StackedBottomDockState();
}

class _StackedBottomDockState extends State<StackedBottomDock> {
  static const Duration _animDuration = Duration(milliseconds: 320);
  static const Curve _animCurve = Curves.easeOutCubic;
  static const double _peekOffset = 14.0;
  static const double _miniPlayerHeight = 78.0;

  void _setMode(DockStackMode nextMode) {
    if (widget.mode == nextMode) return;
    HapticFeedback.lightImpact();
    widget.onModeChanged(nextMode);
  }

  void _handleSwipeDown() {
    switch (widget.mode) {
      case DockStackMode.defaultLayout:
        _setMode(DockStackMode.miniPlayerOnTop);
        break;
      case DockStackMode.miniPlayerOnTop:
        _setMode(DockStackMode.navBarOnTop);
        break;
      case DockStackMode.navBarOnTop:
        _setMode(DockStackMode.miniPlayerOnTop);
        break;
    }
  }

  void _handleSwipeUp() {
    if (widget.mode != DockStackMode.defaultLayout) {
      _setMode(DockStackMode.defaultLayout);
    } else {
      widget.onOpenNowPlaying();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final double maxPlayerWidth = isTablet ? 640.0 : 560.0;
    final double maxBarWidth = isTablet ? 620.0 : 540.0;
    final double barHeight = isTablet ? 68.0 : 64.0;
    final double navBarPaddingVertical = isTablet ? 14.0 : 10.0;
    final double navBarTotalHeight = barHeight + navBarPaddingVertical;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          (prev.currentSong != null) != (curr.currentSong != null),
      builder: (context, state) {
        final hasSong = state.currentSong != null;

        // If no song is active, render only the standalone navigation bar
        if (!hasSong) {
          return PulsrBottomNavBar(
            currentIndex: widget.currentIndex,
            onTap: widget.onTapNav,
            includeSafeArea: true,
          );
        }

        final mode = widget.mode;
        final isStacked = mode != DockStackMode.defaultLayout;
        final isNavBarOnTop = mode == DockStackMode.navBarOnTop;

        final double dockHeight = isStacked
            ? (navBarTotalHeight + _peekOffset)
            : (navBarTotalHeight + _miniPlayerHeight);

        // Calculate card bottom offsets, scales, and opacities
        final double miniPlayerBottom;
        final double miniPlayerScale;
        final double miniPlayerOpacity;

        final double navBarBottom;
        final double navBarScale;
        final double navBarOpacity;

        switch (mode) {
          case DockStackMode.defaultLayout:
            miniPlayerBottom = navBarTotalHeight;
            miniPlayerScale = 1.0;
            miniPlayerOpacity = 1.0;
            navBarBottom = 0.0;
            navBarScale = 1.0;
            navBarOpacity = 1.0;
            break;
          case DockStackMode.miniPlayerOnTop:
            miniPlayerBottom = 0.0;
            miniPlayerScale = 1.0;
            miniPlayerOpacity = 1.0;
            navBarBottom = _peekOffset;
            navBarScale = 0.95;
            navBarOpacity = 0.70;
            break;
          case DockStackMode.navBarOnTop:
            miniPlayerBottom = _peekOffset;
            miniPlayerScale = 0.95;
            miniPlayerOpacity = 0.70;
            navBarBottom = 0.0;
            navBarScale = 1.0;
            navBarOpacity = 1.0;
            break;
        }

        final List<BoxShadow> stackedElevationShadow = [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.20),
            blurRadius: 18,
            spreadRadius: 0,
            offset: const Offset(0, -4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.30 : 0.12),
            blurRadius: 12,
            spreadRadius: -1,
            offset: const Offset(0, 4),
          ),
        ];

        // ── Card 1: Mini Player Card ──
        final bool isMiniBehind = isStacked && isNavBarOnTop;
        Widget miniPlayerWidget = MiniPlayer(
          onTap: widget.onOpenNowPlaying,
          onSwipeDown: _handleSwipeDown,
          onSwipeUp: _handleSwipeUp,
        );

        if (isStacked && !isMiniBehind) {
          // Add drop shadow when mini player is the top stacked card
          miniPlayerWidget = DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: stackedElevationShadow,
            ),
            child: miniPlayerWidget,
          );
        }

        Widget wrapBehindCard(Widget child, DockStackMode targetMode) {
          double behindDragDy = 0;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setMode(targetMode),
            onVerticalDragStart: (_) => behindDragDy = 0,
            onVerticalDragUpdate: (d) => behindDragDy += d.delta.dy,
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (behindDragDy > 20 || v > 80) {
                _handleSwipeDown();
              } else if (behindDragDy < -20 || v < -80) {
                _handleSwipeUp();
              }
              behindDragDy = 0;
            },
            onVerticalDragCancel: () => behindDragDy = 0,
            child: AbsorbPointer(child: child),
          );
        }

        if (isMiniBehind) {
          miniPlayerWidget = wrapBehindCard(
            miniPlayerWidget,
            DockStackMode.miniPlayerOnTop,
          );
        }

        final Widget miniPlayerCard = AnimatedPositioned(
          key: const ValueKey('dock_mini_player_positioned'),
          duration: _animDuration,
          curve: _animCurve,
          left: 0,
          right: 0,
          bottom: miniPlayerBottom,
          child: AnimatedScale(
            duration: _animDuration,
            curve: _animCurve,
            scale: miniPlayerScale,
            alignment: Alignment.bottomCenter,
            child: AnimatedOpacity(
              duration: _animDuration,
              curve: _animCurve,
              opacity: miniPlayerOpacity,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxPlayerWidth),
                  child: miniPlayerWidget,
                ),
              ),
            ),
          ),
        );

        // ── Card 2: Bottom Navigation Bar Card ──
        final bool isBarBehind = isStacked && !isNavBarOnTop;
        Widget navBarWidget = PulsrBottomNavBar(
          currentIndex: widget.currentIndex,
          onTap: widget.onTapNav,
          onSwipeDown: _handleSwipeDown,
          onSwipeUp: _handleSwipeUp,
          includeSafeArea: false,
        );

        if (isStacked && isNavBarOnTop) {
          // Add drop shadow when nav bar is the top stacked card
          navBarWidget = DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: stackedElevationShadow,
            ),
            child: navBarWidget,
          );
        }

        if (isBarBehind) {
          navBarWidget = wrapBehindCard(
            navBarWidget,
            DockStackMode.navBarOnTop,
          );
        }

        final Widget navBarCard = AnimatedPositioned(
          key: const ValueKey('dock_nav_bar_positioned'),
          duration: _animDuration,
          curve: _animCurve,
          left: 0,
          right: 0,
          bottom: navBarBottom,
          child: AnimatedScale(
            duration: _animDuration,
            curve: _animCurve,
            scale: navBarScale,
            alignment: Alignment.bottomCenter,
            child: AnimatedOpacity(
              duration: _animDuration,
              curve: _animCurve,
              opacity: navBarOpacity,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBarWidth),
                  child: navBarWidget,
                ),
              ),
            ),
          ),
        );

        // Z-order: The top card must be rendered second in the Stack.
        final List<Widget> stackChildren = isNavBarOnTop
            ? [miniPlayerCard, navBarCard]
            : [navBarCard, miniPlayerCard];

        double dockDragDy = 0;
        return SafeArea(
          top: false,
          left: false,
          right: false,
          bottom: true,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) => dockDragDy = 0,
            onVerticalDragUpdate: (d) => dockDragDy += d.delta.dy,
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (dockDragDy > 20 || v > 80) {
                _handleSwipeDown();
              } else if (dockDragDy < -20 || v < -80) {
                _handleSwipeUp();
              }
              dockDragDy = 0;
            },
            onVerticalDragCancel: () => dockDragDy = 0,
            child: AnimatedContainer(
              duration: _animDuration,
              curve: _animCurve,
              height: dockHeight,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: stackChildren,
              ),
            ),
          ),
        );
      },
    );
  }
}
