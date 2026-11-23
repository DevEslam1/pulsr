// lib/core/router/safe_navigation.dart
import 'dart:async';
import 'package:collection/collection.dart';
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
  static Object? _lastExtra;
  static bool _windowActive = false;
  static Timer? _clearTimer;
  static const Duration _window = Duration(milliseconds: 600);
  static const DeepCollectionEquality _equality = DeepCollectionEquality();

  static bool _areExtrasEqual(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      if (a.length > 20) {
        return identical(a.first, b.first) && identical(a.last, b.last);
      }
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key)) return false;
        final valA = entry.value;
        final valB = b[entry.key];
        if (identical(valA, valB)) continue;
        if (valA is List && valB is List) {
          if (valA.length != valB.length) return false;
          if (valA.length > 20) {
            if (valA.isNotEmpty &&
                (!identical(valA.first, valB.first) ||
                    !identical(valA.last, valB.last))) {
              return false;
            }
          } else if (!_equality.equals(valA, valB)) {
            return false;
          }
        } else if (valA != valB) {
          return false;
        }
      }
      return true;
    }
    return _equality.equals(a, b);
  }

  /// Clears an active debounce window (e.g. when a pushed route pops early).
  static void clearDebounce() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _lastLocation = null;
    _lastExtra = null;
    _windowActive = false;
  }

  /// Pushes [location] unless an identical push happened within the last
  /// [_window]; returns whether the navigation was actually performed.
  bool pushDebounced(String location, {Object? extra}) {
    if (_lastLocation == location &&
        _areExtrasEqual(_lastExtra, extra) &&
        _windowActive) {
      return false;
    }
    _clearTimer?.cancel();
    _lastLocation = location;
    _lastExtra = extra;
    _windowActive = true;
    _clearTimer = Timer(_window, () {
      _lastLocation = null;
      _lastExtra = null;
      _windowActive = false;
      _clearTimer = null;
    });
    try {
      final Future<void> pushFuture = push<void>(location, extra: extra);
      unawaited(pushFuture.whenComplete(() {
        if (_lastLocation == location && _areExtrasEqual(_lastExtra, extra)) {
          clearDebounce();
        }
      }));
    } catch (_) {
      clearDebounce();
      rethrow;
    }
    return true;
  }

  @visibleForTesting
  static void resetForTesting() => clearDebounce();
}
