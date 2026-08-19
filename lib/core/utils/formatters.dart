// lib/core/utils/formatters.dart
class Formatters {
  static String formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
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
}
