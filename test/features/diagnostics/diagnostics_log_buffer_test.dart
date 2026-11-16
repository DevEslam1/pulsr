// test/features/diagnostics/diagnostics_log_buffer_test.dart
//
// Ring-buffer contract: exact line format, oldest-first eviction at 200 entries,
// and message normalization used by the exported bundle.

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/diagnostics/diagnostics_log_buffer.dart';

void main() {
  setUp(() {
    DiagnosticsLogBuffer.clear();
    DiagnosticsLogBuffer.setClock(() => DateTime(2026, 1, 2, 12, 34, 56));
  });

  tearDown(() {
    DiagnosticsLogBuffer.clear();
    DiagnosticsLogBuffer.resetClock();
  });

  test('formats HH:mm:ss LEVEL [category] message', () {
    DiagnosticsLogBuffer.add(
      'output opened',
      level: 'warn',
      category: 'Audio',
    );

    expect(
      DiagnosticsLogBuffer.snapshot(),
      <String>['12:34:56 WARN [Audio] output opened'],
    );
  });

  test('falls back to INFO and App for blank level or category', () {
    DiagnosticsLogBuffer.add('hello', level: '  ', category: '  ');

    expect(
      DiagnosticsLogBuffer.snapshot().single,
      '12:34:56 INFO [App] hello',
    );
  });

  test('keeps the newest 200 entries', () {
    for (var i = 0; i < 205; i++) {
      DiagnosticsLogBuffer.add('msg $i');
    }

    final snapshot = DiagnosticsLogBuffer.snapshot();

    expect(DiagnosticsLogBuffer.length, DiagnosticsLogBuffer.maxEntries);
    expect(snapshot.length, 200);
    expect(snapshot.first, endsWith('msg 5'));
    expect(snapshot.last, endsWith('msg 204'));
  });

  test('collapses newlines and truncates long messages', () {
    DiagnosticsLogBuffer.add('line one\nline two\r\nline three');

    expect(
      DiagnosticsLogBuffer.snapshot().single,
      '12:34:56 INFO [App] line one line two line three',
    );

    DiagnosticsLogBuffer.clear();
    final longMessage = 'x' * (DiagnosticsLogBuffer.maxMessageLength + 50);
    DiagnosticsLogBuffer.add(longMessage);

    final line = DiagnosticsLogBuffer.snapshot().single;
    expect(line.length, greaterThan(100));
    expect(line, endsWith('...'));
    expect(
      line.split('] ').last.length,
      DiagnosticsLogBuffer.maxMessageLength,
    );
  });

  test('clear drops everything', () {
    DiagnosticsLogBuffer.add('one');
    DiagnosticsLogBuffer.add('two');

    DiagnosticsLogBuffer.clear();

    expect(DiagnosticsLogBuffer.length, 0);
    expect(DiagnosticsLogBuffer.snapshot(), isEmpty);
  });
}
