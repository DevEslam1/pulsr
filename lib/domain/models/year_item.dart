// lib/domain/models/year_item.dart

class YearItem {
  final int year;
  final int songCount;

  const YearItem({
    required this.year,
    required this.songCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YearItem &&
          runtimeType == other.runtimeType &&
          year == other.year &&
          songCount == other.songCount;

  @override
  int get hashCode => year.hashCode ^ songCount.hashCode;
}
