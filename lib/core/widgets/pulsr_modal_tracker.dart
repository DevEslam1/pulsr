// lib/core/widgets/pulsr_modal_tracker.dart
import 'package:flutter/material.dart';
import 'pulsr_dock_tracker.dart';

/// Global tracker for modal routes (dialogs / bottom sheets).
///
/// The app shell (mini player dock, tablet player bar) listens to
/// [isModalOpen] and hides itself while any modal is on screen, so the
/// mini player never renders on top of dialogs.
///
/// Modals must be registered either automatically via the root
/// [PulsrModalObserver] or manually with [push]/[pop] (used by
/// `PulsrDialog` helpers for non-root navigators).
class PulsrModalTracker {
  static final ValueNotifier<bool> isModalOpen = ValueNotifier<bool>(false);
  static int _activeModals = 0;

  static void push() {
    _activeModals++;
    if (_activeModals == 1) isModalOpen.value = true;
  }

  static void pop() {
    _activeModals = (_activeModals - 1).clamp(0, 1 << 30);
    if (_activeModals == 0) isModalOpen.value = false;
  }
}

/// Root navigator observer that auto-registers dialogs, bottom sheets, and full-screen player routes.
class PulsrModalObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    if (_isModal(route)) PulsrModalTracker.push();
    if (_isNowPlaying(route)) PulsrDockTracker.setNowPlayingOpen(true);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (_isModal(route)) PulsrModalTracker.pop();
    if (_isNowPlaying(route)) PulsrDockTracker.setNowPlayingOpen(false);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    if (_isModal(route)) PulsrModalTracker.pop();
    if (_isNowPlaying(route)) PulsrDockTracker.setNowPlayingOpen(false);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (oldRoute != null && _isModal(oldRoute)) PulsrModalTracker.pop();
    if (newRoute != null && _isModal(newRoute)) PulsrModalTracker.push();
    if (oldRoute != null && _isNowPlaying(oldRoute)) PulsrDockTracker.setNowPlayingOpen(false);
    if (newRoute != null && _isNowPlaying(newRoute)) PulsrDockTracker.setNowPlayingOpen(true);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  bool _isModal(Route route) =>
      route is PopupRoute ||
      route is DialogRoute ||
      route is RawDialogRoute ||
      route is ModalBottomSheetRoute;

  bool _isNowPlaying(Route route) =>
      route.settings.name == 'now-playing' ||
      route.settings.name == '/now-playing';
}

