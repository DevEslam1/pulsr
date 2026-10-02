// lib/core/router/safe_navigation.dart
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Guards against accidental double-navigation from rapid double-taps on the
/// same control (a list tile, the mini-player, a "now playing" affordance).
///
/// go_router's bare [GoRouter.push] stacks a new page on every call, so a fast
/// double-tap can push two identical detail / now-playing pages. [pushDebounced]
/// collapses repeat pushes to the *same* location inside [_window] into one.
///
/// The guard is intentionally keyed on the destination location (not the
/// widget) and stored statically, so independent widgets racing to open the
/// same route (e.g. a tile and the mini-player both opening `/now-playing`)
/// are de-duplicated too. Navigating somewhere else immediately is never
/// blocked because the key changes.
extension PulsrSafePush on BuildContext {
  static String? _lastLocation;
  static DateTime? _lastPushAt;
  static const Duration _window = Duration(milliseconds: 600);

  /// Pushes [location] unless an identical push happened within the last
  /// [_window]; returns whether the navigation was actually performed.
  bool pushDebounced(String location, {Object? extra}) {
    final now = DateTime.now();
    final last = _lastPushAt;
    if (_lastLocation == location &&
        last != null &&
        now.difference(last) < _window) {
      return false;
    }
    _lastLocation = location;
    _lastPushAt = now;
    push<void>(location, extra: extra);
    return true;
  }
}
