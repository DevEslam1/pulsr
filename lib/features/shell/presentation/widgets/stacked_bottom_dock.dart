import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';
import '../../../player/presentation/mini_player.dart';
import '../../../../core/widgets/pulsr_modal_tracker.dart';
import '../../../../core/widgets/pulsr_dock_tracker.dart';
import '../../../../core/responsive/layout_delegate.dart';
import '../../../../core/responsive/pulsr_layout_metrics.dart';
import '../bottom_nav_bar.dart';
import 'dock_style_picker_sheet.dart';
import 'package:pulsr/core/constants/app_colors.dart';

enum DockStackMode {
  /// Default: MiniPlayer is placed above BottomNavBar in vertical order.
  defaultLayout,

  /// Stacked: MiniPlayer is stacked on the BottomNavBar (in front).
  miniPlayerOnTop,

  /// Stacked: BottomNavBar is in front, MiniPlayer is stacked behind it.
  navBarOnTop,

  /// System: MiniPlayer docks to a floating native media pill style above the nav bar.
  system,
}

/// Hides the dock (mini player + nav bar) while any dialog or bottom sheet
/// is open, so nothing renders on top of the modal layer.
class _ModalGate extends StatelessWidget {
  final Widget child;

  const _ModalGate({required this.child});

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final isKeyboardOpen = keyboardInset > 0;
    return ValueListenableBuilder<bool>(
      valueListenable: PulsrModalTracker.isModalOpen,
      builder: (context, modalOpen, _) {
        final shouldHide = modalOpen || isKeyboardOpen;
        return AnimatedSlide(
          duration: context.motion(PulsrDurations.layout),
          curve: context.motionCurve(Curves.easeInOutCubic),
          offset: shouldHide ? const Offset(0, 1.4) : Offset.zero,
          child: AnimatedOpacity(
            duration: context.motion(PulsrDurations.state),
            curve: context.motionCurve(Curves.easeOut),
            opacity: shouldHide ? 0.0 : 1.0,
            child: RepaintBoundary(
              child: IgnorePointer(ignoring: shouldHide, child: child),
            ),
          ),
        );
      },
    );
  }
}

class StackedBottomDock extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTapNav;
  final VoidCallback onOpenNowPlaying;
  final DockStackMode mode;
  final ValueChanged<DockStackMode> onModeChanged;
  final ShellLayoutMode? layoutMode;

  const StackedBottomDock({
    super.key,
    required this.currentIndex,
    required this.onTapNav,
    required this.onOpenNowPlaying,
    required this.mode,
    required this.onModeChanged,
    this.layoutMode,
  });

  static double computeDockHeight({
    required bool hasSong,
    required DockStackMode mode,
    required double navBarTotalHeight,
    double keyboardInset = 0.0,
    bool isKeyboardVisible = false,
  }) =>
      StackedBottomDockState.computeDockHeight(
        hasSong: hasSong,
        mode: mode,
        navBarTotalHeight: navBarTotalHeight,
        keyboardInset: keyboardInset,
        isKeyboardVisible: isKeyboardVisible,
      );

  @override
  State<StackedBottomDock> createState() => StackedBottomDockState();
}

class StackedBottomDockState extends State<StackedBottomDock> {
  static const Duration _animDuration = PulsrDurations.page;
  static const Curve _animCurve = Curves.easeOutCubic;
  static const double _peekOffset = PulsrLayoutMetrics.peekOffset;
  static const double _miniPlayerHeight = PulsrLayoutMetrics.miniPlayerHeight;
  static const double _dockPillGap = PulsrLayoutMetrics.dockPillGap;
  double _behindMiniDragDy = 0;
  double _behindNavDragDy = 0;
  double _dockDragDy = 0;

  double? _lastReportedHeight;
  bool? _lastReportedMiniPlayer;
  double? _targetDockHeight;
  bool? _targetMiniPlayer;
  bool _pendingUpdate = false;

  void _maybeUpdateDock({required double height, required bool miniPlayer}) {
    if (_lastReportedHeight == height &&
        _lastReportedMiniPlayer == miniPlayer) {
      return;
    }
    _targetDockHeight = height;
    _targetMiniPlayer = miniPlayer;

    if (_pendingUpdate) return;
    _pendingUpdate = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingUpdate = false;
      if (!mounted) return;
      final h = _targetDockHeight;
      final mp = _targetMiniPlayer;
      if (h != null && mp != null) {
        if (_lastReportedHeight != h || _lastReportedMiniPlayer != mp) {
          _lastReportedHeight = h;
          _lastReportedMiniPlayer = mp;
          PulsrDockTracker.updateDock(height: h, miniPlayer: mp);
        }
      }
    });
  }

  static double computeDockHeight({
    required bool hasSong,
    required DockStackMode mode,
    required double navBarTotalHeight,
    double keyboardInset = 0.0,
    bool isKeyboardVisible = false,
  }) {
    if (isKeyboardVisible || keyboardInset > 0) return 0.0;
    if (!hasSong) return navBarTotalHeight;
    if (mode == DockStackMode.system) {
      return navBarTotalHeight + _miniPlayerHeight + 4.0;
    }
    final isStacked = mode != DockStackMode.defaultLayout;
    return !isStacked
        ? (navBarTotalHeight + _dockPillGap + _miniPlayerHeight)
        : (_peekOffset + _miniPlayerHeight);
  }

  void _syncDock({required bool hasSong}) {
    if (!mounted) return;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final effectiveLayoutMode =
        widget.layoutMode ?? PulsrLayoutDelegate.of(context).layoutMode;
    if (effectiveLayoutMode == ShellLayoutMode.bottomNavWide) {
      _maybeUpdateDock(
        height: keyboardInset > 0 ? 0.0 : 56.0,
        miniPlayer: keyboardInset > 0 ? false : hasSong,
      );
      return;
    }

    final double navBarTotalHeight =
        PulsrLayoutMetrics.navBarTotalHeight(context);

    final double dockHeight = computeDockHeight(
      hasSong: hasSong,
      mode: widget.mode,
      navBarTotalHeight: navBarTotalHeight,
      keyboardInset: keyboardInset,
    );
    _maybeUpdateDock(
      height: dockHeight,
      miniPlayer: keyboardInset > 0 ? false : hasSong,
    );
  }

  bool? _lastKnownHasSong;
  int? _lastKnownSongId;
  double? _lastKnownKeyboardInset;
  Timer? _dockSyncDebounceTimer;

  @visibleForTesting
  Timer? get dockSyncDebounceTimer => _dockSyncDebounceTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!mounted) return;
    try {
      final currentSong = context.read<PlayerCubit>().state.currentSong;
      final songId = currentSong?.id;
      final hasSong = currentSong != null;
      final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
      if (_lastKnownSongId != songId ||
          _lastKnownHasSong != hasSong ||
          _lastKnownKeyboardInset != keyboardInset) {
        final isFirstSync = _lastKnownHasSong == null;
        _lastKnownSongId = songId;
        _lastKnownHasSong = hasSong;
        _lastKnownKeyboardInset = keyboardInset;
        _dockSyncDebounceTimer?.cancel();
        _dockSyncDebounceTimer = null;
        if (isFirstSync) {
          _syncDock(hasSong: hasSong);
        } else {
          _dockSyncDebounceTimer = Timer(const Duration(milliseconds: 50), () {
            if (!mounted) return;
            _dockSyncDebounceTimer = null;
            _syncDock(hasSong: hasSong);
          });
        }
      }
    } catch (_) {
      // PlayerCubit not yet provided or tree detaching
    }
  }

  @override
  void didUpdateWidget(covariant StackedBottomDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _dockSyncDebounceTimer?.cancel();
      _dockSyncDebounceTimer = null;
      try {
        final currentSong = context.read<PlayerCubit>().state.currentSong;
        final hasSong = currentSong != null;
        _lastKnownSongId = currentSong?.id;
        _lastKnownHasSong = hasSong;
        _syncDock(hasSong: hasSong);
      } catch (_) {
        if (_lastKnownHasSong != null) {
          _syncDock(hasSong: _lastKnownHasSong!);
        }
      }
    }
  }

  @override
  void dispose() {
    _dockSyncDebounceTimer?.cancel();
    _dockSyncDebounceTimer = null;
    _pendingUpdate = false;
    _targetDockHeight = null;
    _targetMiniPlayer = null;
    _lastReportedHeight = null;
    _lastReportedMiniPlayer = null;
    PulsrDockTracker.updateDock(height: 0.0, miniPlayer: false);
    super.dispose();
  }

  void _setMode(DockStackMode nextMode) {
    if (widget.mode == nextMode) return;
    HapticFeedback.lightImpact();
    widget.onModeChanged(nextMode);
  }

  void _handleSwipeDown() {
    switch (widget.mode) {
      case DockStackMode.defaultLayout:
        _setMode(DockStackMode.system);
        break;
      case DockStackMode.system:
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

  /// Discoverable alternative to the swipe-only dock-mode cycling: a long-press
  /// on the mini player opens an explicit chooser.
  void _showDockStylePicker() {
    HapticFeedback.mediumImpact();
    DockStylePickerSheet.show(
      context,
      current: widget.mode,
      onSelected: _setMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final animDuration = context.motion(_animDuration);
    final animCurve = context.motionCurve(_animCurve);
    final isTablet = Adaptive.isTablet(context);
    final double maxDockWidth = isTablet ? 640.0 : 540.0;
    final double navBarTotalHeight =
        PulsrLayoutMetrics.navBarTotalHeight(context);

    return _ModalGate(
      child: BlocListener<PlayerCubit, PlayerState>(
        listenWhen: (prev, curr) =>
            (prev.currentSong != null) != (curr.currentSong != null),
        listener: (context, state) =>
            _syncDock(hasSong: state.currentSong != null),
        child: BlocSelector<PlayerCubit, PlayerState, bool>(
          selector: (state) => state.currentSong != null,
          builder: (context, hasSong) {
            final effectiveLayoutMode =
                widget.layoutMode ?? PulsrLayoutDelegate.of(context).layoutMode;

            if (effectiveLayoutMode == ShellLayoutMode.bottomNavWide) {
              return SafeArea(
                top: false,
                left: false,
                right: false,
                bottom: true,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 860, maxHeight: 56),
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: p.surface.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(AppRadii.r24),
                          border: Border.all(
                            color: p.hairline,
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: p.isDark ? 0.35 : 0.12),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.r24),
                          child: Row(
                            children: [
                              if (hasSong) ...[
                                Expanded(
                                  flex: 5,
                                  child: MiniPlayerHorizontal(
                                    onTap: widget.onOpenNowPlaying,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 28,
                                  color: p.hairline.withValues(alpha: 0.35),
                                ),
                                Expanded(
                                  flex: 5,
                                  child: PulsrBottomNavBar(
                                    currentIndex: widget.currentIndex,
                                    onTap: widget.onTapNav,
                                    includeSafeArea: false,
                                    iconOnly: true,
                                  ),
                                ),
                              ] else ...[
                                Expanded(
                                  child: PulsrBottomNavBar(
                                    currentIndex: widget.currentIndex,
                                    onTap: widget.onTapNav,
                                    includeSafeArea: false,
                                    iconOnly: false,
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
              );
            }

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

            // Size the stack to whichever card sits highest. In navBarOnTop the
            // mini player peeks above the nav bar, so its top is
            // _peekOffset + _miniPlayerHeight (not navBarTotalHeight + _peekOffset,
            // which clipped it).
            final double dockHeight = computeDockHeight(
              hasSong: true,
              mode: mode,
              navBarTotalHeight: navBarTotalHeight,
            );

            // Calculate card bottom offsets, scales, and opacities
            final double miniPlayerBottom;
            final double miniPlayerScale;
            final double miniPlayerOpacity;

            final double navBarBottom;
            final double navBarScale;
            final double navBarOpacity;

            switch (mode) {
              case DockStackMode.defaultLayout:
                miniPlayerBottom = navBarTotalHeight + _dockPillGap;
                miniPlayerScale = 1.0;
                miniPlayerOpacity = 1.0;
                navBarBottom = 0.0;
                navBarScale = 1.0;
                navBarOpacity = 1.0;
                break;
              case DockStackMode.system:
                miniPlayerBottom = navBarTotalHeight + 4.0;
                miniPlayerScale = 0.98;
                miniPlayerOpacity = 1.0;
                navBarBottom = 0.0;
                navBarScale = 1.0;
                navBarOpacity = 1.0;
                break;
              case DockStackMode.miniPlayerOnTop:
                miniPlayerBottom = 0.0;
                miniPlayerScale = 1.0;
                miniPlayerOpacity = 1.0;
                navBarBottom =
                    _miniPlayerHeight - navBarTotalHeight + _peekOffset;
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
                color: AppColors.scrimAt(p.isDark ? 0.45 : 0.20),
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, -4),
              ),
              BoxShadow(
                color: AppColors.scrimAt(p.isDark ? 0.30 : 0.12),
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
              onLongPress: _showDockStylePicker,
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

            Widget wrapBehindCard(Widget child, DockStackMode targetMode,
                {required bool isMini}) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _setMode(targetMode),
                onVerticalDragStart: (_) {
                  if (isMini) {
                    _behindMiniDragDy = 0;
                  } else {
                    _behindNavDragDy = 0;
                  }
                },
                onVerticalDragUpdate: (d) {
                  if (isMini) {
                    _behindMiniDragDy += d.delta.dy;
                  } else {
                    _behindNavDragDy += d.delta.dy;
                  }
                },
                onVerticalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  final dragDy = isMini ? _behindMiniDragDy : _behindNavDragDy;
                  if (dragDy > 40 || v > 120) {
                    _handleSwipeDown();
                  } else if (dragDy < -40 || v < -120) {
                    _handleSwipeUp();
                  }
                  if (isMini) {
                    _behindMiniDragDy = 0;
                  } else {
                    _behindNavDragDy = 0;
                  }
                },
                onVerticalDragCancel: () {
                  if (isMini) {
                    _behindMiniDragDy = 0;
                  } else {
                    _behindNavDragDy = 0;
                  }
                },
                child: AbsorbPointer(child: child),
              );
            }

            if (isMiniBehind) {
              miniPlayerWidget = wrapBehindCard(
                miniPlayerWidget,
                DockStackMode.miniPlayerOnTop,
                isMini: true,
              );
            }

            final Widget miniPlayerCard = AnimatedPositioned(
              key: const ValueKey('dock_mini_player_positioned'),
              duration: animDuration,
              curve: animCurve,
              left: 0,
              right: 0,
              bottom: miniPlayerBottom,
              child: _AnimatedCardTransform(
                duration: animDuration,
                curve: animCurve,
                scale: miniPlayerScale,
                opacity: miniPlayerOpacity,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxDockWidth),
                    child: miniPlayerWidget,
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
                isMini: false,
              );
            }

            final Widget navBarCard = AnimatedPositioned(
              key: const ValueKey('dock_nav_bar_positioned'),
              duration: animDuration,
              curve: animCurve,
              left: 0,
              right: 0,
              bottom: navBarBottom,
              child: _AnimatedCardTransform(
                duration: animDuration,
                curve: animCurve,
                scale: navBarScale,
                opacity: navBarOpacity,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxDockWidth),
                    child: navBarWidget,
                  ),
                ),
              ),
            );

            // Z-order: The top card must be rendered second in the Stack.
            final List<Widget> stackChildren = isNavBarOnTop
                ? [miniPlayerCard, navBarCard]
                : [navBarCard, miniPlayerCard];

            return SafeArea(
              top: false,
              left: false,
              right: false,
              bottom: true,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: (_) => _dockDragDy = 0,
                onVerticalDragUpdate: (d) => _dockDragDy += d.delta.dy,
                onVerticalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (_dockDragDy > 40 || v > 120) {
                    _handleSwipeDown();
                  } else if (_dockDragDy < -40 || v < -120) {
                    _handleSwipeUp();
                  }
                  _dockDragDy = 0;
                },
                onVerticalDragCancel: () => _dockDragDy = 0,
                child: AnimatedContainer(
                  duration: animDuration,
                  curve: animCurve,
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
        ),
      ),
    );
  }
}

class _AnimatedCardTransform extends ImplicitlyAnimatedWidget {
  final double scale;
  final double opacity;
  final Widget child;

  const _AnimatedCardTransform({
    required this.scale,
    required this.opacity,
    required this.child,
    required super.duration,
    required super.curve,
  });

  @override
  AnimatedWidgetBaseState<_AnimatedCardTransform> createState() =>
      _AnimatedCardTransformState();
}

class _AnimatedCardTransformState
    extends AnimatedWidgetBaseState<_AnimatedCardTransform> {
  Tween<double>? _scaleTween;
  Tween<double>? _opacityTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _scaleTween = visitor(
      _scaleTween,
      widget.scale,
      (dynamic value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
    _opacityTween = visitor(
      _opacityTween,
      widget.opacity,
      (dynamic value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final currentScale = _scaleTween?.evaluate(animation) ?? widget.scale;
    final currentOpacity =
        (_opacityTween?.evaluate(animation) ?? widget.opacity).clamp(0.0, 1.0);
    return Transform.scale(
      scale: currentScale,
      alignment: Alignment.bottomCenter,
      child: Opacity(
        opacity: currentOpacity,
        child: widget.child,
      ),
    );
  }
}
