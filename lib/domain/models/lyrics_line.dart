// lib/domain/models/lyrics_line.dart

class LyricsLine {
  final Duration timestamp;
  final String text;

  const LyricsLine({
    required this.timestamp,
    required this.text,
  });

  @override
  String toString() => '[${timestamp.inMilliseconds}ms]: $text';
}
