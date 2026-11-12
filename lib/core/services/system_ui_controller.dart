// lib/core/services/system_ui_controller.dart
import 'package:flutter/material.dart';
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
  bool? _currentImmersiveApplied;

  /// Requests immersive mode for a specific owner/screen.
  void requestImmersive(String requesterId) {
    _immersiveRequesters.add(requesterId);
    _apply();
  }

  /// Releases immersive mode for a specific owner/screen.
  void releaseImmersive(String requesterId) {
    _immersiveRequesters.remove(requesterId);
    _apply();
  }

  /// Forces re-application of the current calculated system UI state
  /// (e.g. after a route pop or app resume).
  void invalidate() {
    _currentImmersiveApplied = null;
    _apply();
  }

  /// Directly set immersive state based on orientation/conditions for an owner.
  void syncMode({required String owner, required bool immersive}) {
    if (immersive) {
      _immersiveRequesters.add(owner);
    } else {
      _immersiveRequesters.remove(owner);
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
  void resetForTesting() {
    _immersiveRequesters.clear();
    _currentImmersiveApplied = null;
  }
}
