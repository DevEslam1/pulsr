// lib/features/diagnostics/diagnostics_log_buffer.dart
//
// Feature-facing facade over the core ring buffer. ErrorLogger writes into
// [LogRingBuffer] (core) and the bundle service reads it here, so the logger no
// longer imports a feature module and the core -> feature dependency cycle is
// gone. The facade keeps the diagnostics test/API surface unchanged.

import '../../core/utils/log_ring_buffer.dart';

/// Fixed-size buffer of `HH:mm:ss LEVEL [category] message` lines.
abstract final class DiagnosticsLogBuffer {
  /// Maximum number of retained lines.
  static const int maxEntries = LogRingBuffer.maxEntries;

  /// Longest message kept per line; longer messages are truncated.
  static const int maxMessageLength = LogRingBuffer.maxMessageLength;

  /// Number of lines currently buffered.
  static int get length => LogRingBuffer.length;

  /// Appends one line, dropping the oldest when the buffer is full.
  static void add(
    String message, {
    String level = 'INFO',
    String category = 'App',
  }) =>
      LogRingBuffer.add(message, level: level, category: category);

  /// Oldest-to-newest copy of the buffered lines.
  static List<String> snapshot() => LogRingBuffer.snapshot();

  /// Drops every buffered line.
  static void clear() => LogRingBuffer.clear();

  /// Pins the timestamp source so tests can assert exact formatting.
  static void setClock(DateTime Function() clock) =>
      LogRingBuffer.setClock(clock);

  /// Restores the wall clock after [setClock].
  static void resetClock() => LogRingBuffer.resetClock();
}
