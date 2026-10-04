// lib/core/widgets/pulsr_dock_tracker.dart
import 'package:flutter/material.dart';

/// Reserves space only in content that actually shares the shell's dock.
/// Standalone routes have no scope and do not inherit an offstage dock's height.
class PulsrDockScope extends InheritedWidget {
  final double height;
  const PulsrDockScope({super.key, required this.height, required super.child});

  static double heightOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PulsrDockScope>()?.height ?? 0;

  @override
  bool updateShouldNotify(PulsrDockScope oldWidget) =>
      height != oldWidget.height;
}

class PulsrDockAware extends StatelessWidget {
  final Widget child;
  final bool heightIncludesSafeArea;
  const PulsrDockAware(
      {super.key, required this.child, this.heightIncludesSafeArea = false});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: PulsrDockTracker.dockHeight,
        child: child,
        builder: (context, height, child) => PulsrDockScope(
          height: (height -
                  (heightIncludesSafeArea
                      ? MediaQuery.paddingOf(context).bottom
                      : 0))
              .clamp(0.0, double.infinity),
          child: child!,
        ),
      );
}

/// {@category DesignSystem}
/// Global tracker for bottom-docked surfaces (MiniPlayer dock in AppShell,
/// tablet player bar, bottom nav bar).
///
/// Enables floating overlays like [PulsrToast] / [PulsrSnackBar] to dynamically
/// float directly above the mini player with pixel-perfect clearance, adapting
/// automatically to track presence, dock modes, modal states, and orientations.
class PulsrDockTracker {
  /// Height of the visible bottom dock (excluding device safe area padding).
  /// Updated by [StackedBottomDock] and [TabletPlayerBar].
  static final ValueNotifier<double> dockHeight = ValueNotifier<double>(0.0);

  /// Whether the mini player component is actively rendered in the dock.
  static final ValueNotifier<bool> hasMiniPlayer = ValueNotifier<bool>(false);

  /// Whether the full-screen Now Playing route is currently on top.
  static final ValueNotifier<bool> isNowPlayingOpen =
      ValueNotifier<bool>(false);

  /// Combined notifier to trigger updates whenever any dock metric changes.
  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  static void updateDock({required double height, required bool miniPlayer}) {
    final changed = (dockHeight.value - height).abs() > 0.5 ||
        hasMiniPlayer.value != miniPlayer;
    if (changed) {
      dockHeight.value = height;
      hasMiniPlayer.value = miniPlayer;
      changeNotifier.value++;
    }
  }

  static void setNowPlayingOpen(bool open) {
    if (isNowPlayingOpen.value != open) {
      isNowPlayingOpen.value = open;
      changeNotifier.value++;
    }
  }
}
