import 'dart:async';
import 'package:flutter/foundation.dart';
import 'error_logger.dart';

/// Debug utility that tracks cubit instances and reports unclosed/leaked instances (I-12).
class LeakDetector {
  LeakDetector._();

  static final Map<Object, Timer> _pendingChecks = {};
  static final Set<Object> _trackedCubits = {};

  /// Records the creation of a cubit instance.
  ///
  /// L-05: Idempotent — tracking the same instance twice is a no-op because the
  /// registry is a [Set]. Callers may safely call this more than once; only the
  /// matching [untrack] (also idempotent) removes it.
  static void track(Object cubit) {
    if (!kDebugMode) return;
    _trackedCubits.add(cubit);
  }

  /// Notifies that all listeners to a cubit have been removed.
  /// If the cubit is not closed within [gracePeriod], a leak warning is reported.
  static void onListenersDetached(
    Object cubit,
    bool Function() isClosed, {
    Duration gracePeriod = const Duration(seconds: 5),
  }) {
    if (!kDebugMode) return;
    _pendingChecks[cubit]?.cancel();
    _pendingChecks[cubit] = Timer(gracePeriod, () {
      _pendingChecks.remove(cubit);
      if (!isClosed()) {
        ErrorLogger.log(
          'POTENTIAL LEAK: ${cubit.runtimeType} has no listeners and was not closed within ${gracePeriod.inSeconds}s',
          category: 'LeakDetector',
        );
      }
    });
  }

  /// Records that a cubit has been safely closed.
  static void untrack(Object cubit) {
    if (!kDebugMode) return;
    _pendingChecks[cubit]?.cancel();
    _pendingChecks.remove(cubit);
    _trackedCubits.remove(cubit);
  }

  /// Number of currently tracked cubit instances.
  static int get trackedCount => _trackedCubits.length;

  // FIX-A5: Add debugAssertNoLeaks for leak verification in tests
  static void debugAssertNoLeaks() {
    assert(() {
      if (_trackedCubits.isNotEmpty) {
        final leaked =
            _trackedCubits.map((c) => c.runtimeType.toString()).join(', ');
        throw AssertionError(
            'LeakDetector detected ${_trackedCubits.length} unclosed instances: $leaked');
      }
      return true;
    }(), 'Unclosed cubit instances remain');
  }
}
