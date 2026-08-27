// lib/domain/models/chapter_info.dart

class ChapterInfo {
  final int index;
  final String title;
  final Duration start;
  final Duration? end;
  final String? fileName;

  const ChapterInfo({
    required this.index,
    required this.title,
    required this.start,
    this.end,
    this.fileName,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterInfo &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          title == other.title &&
          start == other.start &&
          end == other.end &&
          fileName == other.fileName;

  @override
  int get hashCode =>
      index.hashCode ^
      title.hashCode ^
      start.hashCode ^
      end.hashCode ^
      fileName.hashCode;

  @override
  String toString() =>
      'ChapterInfo($index: $title [${start.inSeconds}s]${fileName != null ? ' file: $fileName' : ''})';
}
