// lib/core/utils/lrc_parser.dart
import 'dart:io';
import '../../domain/models/lyrics_line.dart';

class LrcParser {
  /// Parses raw LRC string content into a sorted list of `LyricsLine`.
  static List<LyricsLine> parse(String lrcContent) {
    final lines = lrcContent.split(RegExp(r'\r?\n'));
    final List<LyricsLine> result = [];

    // Match tags like [01:23.45] or [01:23.456] or [01:23]
    final RegExp timeExp = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\]');

    for (final line in lines) {
      final matches = timeExp.allMatches(line).toList();
      if (matches.isEmpty) continue;

      // The lyric text is everything after the last timestamp tag
      final lastMatch = matches.last;
      final text = line.substring(lastMatch.end).trim();
      if (text.isEmpty && matches.length == 1) {
        // Empty lyric line (e.g. instrumental pause)
      }

      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fractionStr = match.group(3) ?? '0';
        int milliseconds = 0;
        if (fractionStr.length == 2) {
          milliseconds = int.parse(fractionStr) * 10;
        } else if (fractionStr.length == 3) {
          milliseconds = int.parse(fractionStr);
        } else if (fractionStr.length == 1) {
          milliseconds = int.parse(fractionStr) * 100;
        }

        final totalDuration = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        result.add(LyricsLine(timestamp: totalDuration, text: text));
      }
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  /// Searches for a local `.lrc` file matching the audio file path
  static Future<List<LyricsLine>?> findAndParseLrc(String audioFilePath) async {
    try {
      final lastDot = audioFilePath.lastIndexOf('.');
      if (lastDot == -1) return null;
      final lrcPath = '${audioFilePath.substring(0, lastDot)}.lrc';
      final file = File(lrcPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        return parse(content);
      }
    } catch (_) {}
    return null;
  }
}
