// lib/domain/models/lyrics_line.dart

enum LyricsSource { embedded, externalLrc, none }

class LyricsLine {
  final Duration timestamp;
  final String text;
  final LyricsSource source;

  const LyricsLine({
    required this.timestamp,
    required this.text,
    this.source = LyricsSource.none,
  });

  LyricsLine copyWith({
    Duration? timestamp,
    String? text,
    LyricsSource? source,
  }) {
    return LyricsLine(
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      source: source ?? this.source,
    );
  }

  @override
  String toString() => '[${timestamp.inMilliseconds}ms]: $text ($source)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsLine &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          text == other.text &&
          source == other.source;

  @override
  int get hashCode => timestamp.hashCode ^ text.hashCode ^ source.hashCode;
}

class LyricsResult {
  final List<LyricsLine> lines;
  final LyricsSource source;

  const LyricsResult({
    required this.lines,
    required this.source,
  });

  bool get isSynced => lines.any((line) => line.timestamp > Duration.zero);
}
