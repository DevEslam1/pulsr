// lib/domain/models/genre_item.dart

class GenreItem {
  final String name;
  final int songCount;

  const GenreItem({
    required this.name,
    required this.songCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenreItem &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          songCount == other.songCount;

  @override
  int get hashCode => name.hashCode ^ songCount.hashCode;
}
