// lib/core/utils/cue_parser.dart
import 'dart:io';
import '../../domain/models/chapter_info.dart';
import 'error_logger.dart';

class CueParser {
  /// Parses standard CUE sheet text content into a sorted list of ChapterInfo,
  /// supporting both single-file album sheets and multi-file split-track sheets.
  static List<ChapterInfo> parse(String cueContent) {
    final lines = cueContent.split(RegExp(r'\r?\n'));
    final List<ChapterInfo> chapters = [];

    int currentTrackIndex = 0;
    String currentTitle = '';
    String? currentFileName;
    Duration? currentStart;

    final fileRegex =
        RegExp(r'^\s*FILE\s+"?([^"]+?)"?\s+([A-Z0-9]+)', caseSensitive: false);
    final trackRegex =
        RegExp(r'^\s*TRACK\s+(\d+)\s+AUDIO', caseSensitive: false);
    final titleRegex = RegExp(r'^\s*TITLE\s+"?([^"]+)"?', caseSensitive: false);
    final indexRegex = RegExp(r'^\s*INDEX\s+01\s+(\d{2}):(\d{2}):(\d{2})',
        caseSensitive: false);

    void savePrevious() {
      if (currentTrackIndex > 0 && currentStart != null) {
        final title = currentTitle.isNotEmpty
            ? currentTitle
            : 'Chapter $currentTrackIndex';
        chapters.add(ChapterInfo(
          index: currentTrackIndex,
          title: title,
          start: currentStart,
          fileName: currentFileName,
        ));
      }
    }

    for (final line in lines) {
      final fileMatch = fileRegex.firstMatch(line);
      if (fileMatch != null) {
        savePrevious();
        currentTrackIndex = 0;
        currentTitle = '';
        currentStart = null;
        currentFileName = fileMatch.group(1)?.trim();
        continue;
      }

      final trackMatch = trackRegex.firstMatch(line);
      if (trackMatch != null) {
        savePrevious();
        currentTrackIndex =
            int.tryParse(trackMatch.group(1) ?? '1') ?? (chapters.length + 1);
        currentTitle = '';
        currentStart = null;
        continue;
      }

      final titleMatch = titleRegex.firstMatch(line);
      if (titleMatch != null && currentTrackIndex > 0) {
        currentTitle = titleMatch.group(1)?.trim() ?? '';
        continue;
      }

      final indexMatch = indexRegex.firstMatch(line);
      if (indexMatch != null && currentTrackIndex > 0) {
        final minutes = int.tryParse(indexMatch.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(indexMatch.group(2) ?? '0') ?? 0;
        final frames = int.tryParse(indexMatch.group(3) ?? '0') ?? 0;
        final ms = ((frames / 75.0) * 1000.0).round();
        currentStart =
            Duration(minutes: minutes, seconds: seconds, milliseconds: ms);
      }
    }

    savePrevious();

    // Calculate end durations
    final List<ChapterInfo> resolved = [];
    for (int i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      // Only set end duration if next track is in the same source file
      final Duration? end =
          (i + 1 < chapters.length && chapters[i + 1].fileName == c.fileName)
              ? chapters[i + 1].start
              : null;
      resolved.add(ChapterInfo(
        index: c.index,
        title: c.title,
        start: c.start,
        end: end,
        fileName: c.fileName,
      ));
    }

    return resolved;
  }

  /// Searches for and parses sibling .cue file matching audioFilePath.
  static Future<List<ChapterInfo>> findAndParseCue(String audioFilePath) async {
    try {
      final lastDot = audioFilePath.lastIndexOf('.');
      if (lastDot == -1) return const [];
      final cuePath = '${audioFilePath.substring(0, lastDot)}.cue';
      final file = File(cuePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        return parse(content);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to read external .cue file for $audioFilePath',
          error: e, stackTrace: st, category: 'CueParser');
    }
    return const [];
  }
}
