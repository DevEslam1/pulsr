// lib/features/diagnostics/diagnostics_log_buffer.dart
//
// Process-local ring buffer of the most recent diagnostics events. It never
// prints: the main agent wires ErrorLogger to push into it, and the bundle
// service reads the snapshot, so log lines reach the support file without a
// second console pipeline.

import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Fixed-size buffer of `HH:mm:ss LEVEL [category] message` lines.
abstract final class DiagnosticsLogBuffer {
  /// Maximum number of retained lines.
  static const int maxEntries = 200;

  /// Longest message kept per line; longer messages are truncated.
  static const int maxMessageLength = 500;

  static final ListQueue<String> _entries = ListQueue<String>();
  static DateTime Function() _clock = DateTime.now;

  /// Number of lines currently buffered.
  static int get length => _entries.length;

  /// Appends one line, dropping the oldest when the buffer is full.
  static void add(
    String message, {
    String level = 'INFO',
    String category = 'App',
  }) {
    _entries.addLast(
      '${_timestamp(_clock())} ${_normalizeLevel(level)} '
      '[${_normalizeCategory(category)}] ${_normalizeMessage(message)}',
    );
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
  }

  /// Oldest-to-newest copy of the buffered lines.
  static List<String> snapshot() => List<String>.unmodifiable(_entries);

  /// Drops every buffered line.
  static void clear() => _entries.clear();

  /// Pins the timestamp source so tests can assert exact formatting.
  @visibleForTesting
  static void setClock(DateTime Function() clock) => _clock = clock;

  /// Restores the wall clock after [setClock].
  @visibleForTesting
  static void resetClock() => _clock = DateTime.now;

  static String _timestamp(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  static String _normalizeLevel(String level) {
    final trimmed = level.trim().toUpperCase();
    return trimmed.isEmpty ? 'INFO' : trimmed;
  }

  static String _normalizeCategory(String category) {
    final trimmed = category.trim();
    return trimmed.isEmpty ? 'App' : trimmed;
  }

  static String _normalizeMessage(String message) {
    final singleLine = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= maxMessageLength) return singleLine;
    return '${singleLine.substring(0, maxMessageLength - 3)}...';
  }
}
