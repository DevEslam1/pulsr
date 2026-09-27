// lib/domain/models/lyrics_line.dart

enum LyricsSource { embedded, externalLrc, lrclib, ytmusic, none }

/// Timestamp metadata for a single word within an enhanced LRC synchronized line.
class WordTimestamp {
  final String word;
  final int startMs;
  final int endMs;

  const WordTimestamp({
    required this.word,
    required this.startMs,
    required this.endMs,
  });

  Duration get startDuration => Duration(milliseconds: startMs);
  Duration get endDuration => Duration(milliseconds: endMs);

  @override
  String toString() => '$word($startMs..${endMs}ms)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WordTimestamp &&
          runtimeType == other.runtimeType &&
          word == other.word &&
          startMs == other.startMs &&
          endMs == other.endMs;

  @override
  int get hashCode => word.hashCode ^ startMs.hashCode ^ endMs.hashCode;
}

class LyricsLine {
  final Duration timestamp;
  final String text;
  final LyricsSource source;
  final List<WordTimestamp> words;
  final String? translation;
  final bool isVocal;

  const LyricsLine({
    required this.timestamp,
    required this.text,
    this.source = LyricsSource.none,
    this.words = const [],
    this.translation,
    this.isVocal = true,
  });

  LyricsLine copyWith({
    Duration? timestamp,
    String? text,
    LyricsSource? source,
    List<WordTimestamp>? words,
    String? translation,
    bool? isVocal,
  }) {
    return LyricsLine(
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      source: source ?? this.source,
      words: words ?? this.words,
      translation: translation ?? this.translation,
      isVocal: isVocal ?? this.isVocal,
    );
  }

  @override
  String toString() =>
      '[${timestamp.inMilliseconds}ms]: $text ($source, words: ${words.length}, vocal: $isVocal)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsLine &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          text == other.text &&
          source == other.source &&
          translation == other.translation &&
          isVocal == other.isVocal;

  @override
  int get hashCode =>
      timestamp.hashCode ^
      text.hashCode ^
      source.hashCode ^
      translation.hashCode ^
      isVocal.hashCode;
}

class LyricsResult {
  final List<LyricsLine> lines;
  final LyricsSource source;
  final Map<String, String> metadata;

  const LyricsResult({
    required this.lines,
    required this.source,
    this.metadata = const {},
  });

  bool get isSynced => lines.any((line) => line.timestamp > Duration.zero);
}
