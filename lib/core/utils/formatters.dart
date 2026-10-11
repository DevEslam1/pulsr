// lib/core/utils/formatters.dart
class Formatters {
  static String formatDuration(Duration? duration) {
    if (duration == null || duration.isNegative) return '0:00';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String formatDurationMs(int? milliseconds) {
    if (milliseconds == null || milliseconds <= 0) return '0:00';
    return formatDuration(Duration(milliseconds: milliseconds));
  }

  static String formatTrackCount(int count) {
    return count == 1 ? '1 track' : '$count tracks';
  }

  static String formatSongCount(int count) {
    return count == 1 ? '1 song' : '$count songs';
  }

  static String formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024.0 && i < suffixes.length - 1) {
      d /= 1024.0;
      i++;
    }
    // Promote when rounding reaches a full unit (1,048,575 B is 1023.999 KB,
    // which toStringAsFixed(1) would print as the impossible "1024.0 KB").
    if (i > 0 && i < suffixes.length - 1 && d.toStringAsFixed(1) == '1024.0') {
      d /= 1024.0;
      i++;
    }
    return '${d.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}
