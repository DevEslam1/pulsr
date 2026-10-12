// lib/domain/models/lyrics_line.dart

/// Value equality for lists whose elements implement `==`. Kept local so the
/// pure domain model does not depend on Flutter's `listEquals`.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

enum LyricsSource { embedded, externalLrc, lrclib, ytmusic, none }

enum LyricAlignment { start, end }

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

  /// Fraction of this word sung at [positionMs] (0.0 before, 1.0 after, 0.0..1.0 during).
  double progressAt(int positionMs) {
    if (positionMs <= startMs) return 0.0;
    if (positionMs >= endMs) return 1.0;
    final span = endMs - startMs;
    if (span <= 0) return 1.0;
    return ((positionMs - startMs) / span).clamp(0.0, 1.0);
  }

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
  final String? romanization;
  final bool isVocal;
  final bool isBackground;
  final LyricAlignment alignment;

  const LyricsLine({
    required this.timestamp,
    required this.text,
    this.source = LyricsSource.none,
    this.words = const [],
    this.translation,
    this.romanization,
    this.isVocal = true,
    this.isBackground = false,
    this.alignment = LyricAlignment.start,
  });

  /// True if explicitly marked as background vocal or enclosed in parentheses/brackets.
  bool get isBackgroundLine {
    if (isBackground) return true;
    final trimmed = text.trim();
    return (trimmed.startsWith('(') && trimmed.endsWith(')')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  LyricsLine copyWith({
    Duration? timestamp,
    String? text,
    LyricsSource? source,
    List<WordTimestamp>? words,
    String? translation,
    String? romanization,
    bool? isVocal,
    bool? isBackground,
    LyricAlignment? alignment,
  }) {
    return LyricsLine(
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      source: source ?? this.source,
      words: words ?? this.words,
      translation: translation ?? this.translation,
      romanization: romanization ?? this.romanization,
      isVocal: isVocal ?? this.isVocal,
      isBackground: isBackground ?? this.isBackground,
      alignment: alignment ?? this.alignment,
    );
  }

  @override
  String toString() =>
      '[${timestamp.inMilliseconds}ms]: $text ($source, words: ${words.length}, vocal: $isVocal, bg: $isBackground, align: $alignment)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsLine &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          text == other.text &&
          source == other.source &&
          _listEquals(words, other.words) &&
          translation == other.translation &&
          romanization == other.romanization &&
          isVocal == other.isVocal &&
          isBackground == other.isBackground &&
          alignment == other.alignment;

  @override
  int get hashCode => Object.hash(
        timestamp,
        text,
        source,
        Object.hashAll(words),
        translation,
        romanization,
        isVocal,
        isBackground,
        alignment,
      );
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
