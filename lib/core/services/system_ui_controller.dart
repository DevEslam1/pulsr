// lib/core/services/system_ui_controller.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Single authority for system UI mode (immersive / edge-to-edge) and overlays across the app.
///
/// Prevents conflicting [SystemChrome] mutations when nested or modal screens (e.g. Now Playing,
/// Karaoke, AppShell) enter or exit landscape orientation.
class SystemUiController {
  SystemUiController._();
  static final SystemUiController instance = SystemUiController._();

  static const SystemUiOverlayStyle edgeToEdgeStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );

  final Set<String> _immersiveRequesters = <String>{};
  final Map<Object, Set<String>> _routeRequesters = <Object, Set<String>>{};
  bool? _currentImmersiveApplied;

  void _bindRoute(Object? route, String requesterId) {
    if (route == null) return;
    _routeRequesters.putIfAbsent(route, () => <String>{}).add(requesterId);
  }

  void _unbindRequester(String requesterId) {
    _routeRequesters.removeWhere((_, ids) {
      ids.remove(requesterId);
      return ids.isEmpty;
    });
  }

  /// Requests immersive mode for a specific owner/screen, optionally bound to
  /// a [route] or lifecycle token so popping that route releases it cleanly.
  void requestImmersive(String requesterId, {Object? route}) {
    _immersiveRequesters.add(requesterId);
    _bindRoute(route, requesterId);
    _apply();
  }

  /// Releases immersive mode for a specific owner/screen.
  void releaseImmersive(String requesterId) {
    _immersiveRequesters.remove(requesterId);
    _unbindRequester(requesterId);
    _apply();
  }

  /// Releases every immersive requester associated with [route] (called by
  /// [PulsrModalObserver] on route pop/remove/replace).
  void releaseForRoute(Object route) {
    final ids = _routeRequesters.remove(route);
    if (ids == null || ids.isEmpty) return;
    _immersiveRequesters.removeAll(ids);
    _apply();
  }

  /// Forces re-application of the current calculated system UI state
  /// (e.g. after a route pop or app resume).
  void invalidate() {
    _currentImmersiveApplied = null;
    _apply();
  }

  /// Directly set immersive state based on orientation/conditions for an owner.
  void syncMode({
    required String owner,
    required bool immersive,
    Object? route,
  }) {
    if (immersive) {
      _immersiveRequesters.add(owner);
      _bindRoute(route, owner);
    } else {
      _immersiveRequesters.remove(owner);
      _unbindRequester(owner);
    }
    _apply();
  }

  void _apply() {
    final shouldBeImmersive = _immersiveRequesters.isNotEmpty;
    if (_currentImmersiveApplied == shouldBeImmersive) return;
    _currentImmersiveApplied = shouldBeImmersive;

    if (shouldBeImmersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(edgeToEdgeStyle);
    }
  }

  @visibleForTesting
  bool get isImmersive => _currentImmersiveApplied ?? false;

  @visibleForTesting
  int get activeRequesterCount => _immersiveRequesters.length;

  @visibleForTesting
  void resetForTesting() {
    _immersiveRequesters.clear();
    _routeRequesters.clear();
    _currentImmersiveApplied = null;
  }
}
