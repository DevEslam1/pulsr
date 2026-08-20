// lib/core/utils/lrc_parser.dart
import 'dart:io';
import 'package:flutter/services.dart';
import '../../domain/models/lyrics_line.dart';

class LrcParser {
  static const MethodChannel _lyricsChannel = MethodChannel('com.pulsr.music/lyrics');

  /// Parses raw LRC string content into a sorted list of `LyricsLine`.
  static List<LyricsLine> parse(String lrcContent, {LyricsSource source = LyricsSource.none}) {
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

        result.add(LyricsLine(timestamp: totalDuration, text: text, source: source));
      }
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  /// Parses plain text non-synced lyrics into a list of `LyricsLine`.
  static List<LyricsLine> parsePlainText(String text, {LyricsSource source = LyricsSource.embedded}) {
    final lines = text.split(RegExp(r'\r?\n'));
    final List<LyricsLine> result = [];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        result.add(LyricsLine(
          timestamp: Duration.zero,
          text: trimmed,
          source: source,
        ));
      }
    }
    return result;
  }

  /// Searches for a local `.lrc` file matching the audio file path
  static Future<List<LyricsLine>?> findAndParseLrc(
    String audioFilePath, {
    LyricsSource source = LyricsSource.externalLrc,
  }) async {
    try {
      final lastDot = audioFilePath.lastIndexOf('.');
      if (lastDot == -1) return null;
      final lrcPath = '${audioFilePath.substring(0, lastDot)}.lrc';
      final file = File(lrcPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = parse(content, source: source);
        if (lines.isNotEmpty) return lines;
      }
    } catch (_) {}
    return null;
  }

  /// Attempts to fetch embedded lyrics via platform channel.
  static Future<String?> getEmbeddedLyrics(String audioFilePath) async {
    try {
      final String? lyrics = await _lyricsChannel.invokeMethod<String>(
        'getEmbeddedLyrics',
        {'filePath': audioFilePath},
      );
      if (lyrics != null && lyrics.trim().isNotEmpty) {
        return lyrics.trim();
      }
    } catch (_) {
      // Platform channel error or unsupported platform
    }
    return null;
  }

  /// Resolves lyrics following the fallback chain:
  /// 1. Embedded lyrics via platform channel / tag reader
  /// 2. External .lrc file
  /// 3. null
  static Future<LyricsResult?> resolveLyrics(String audioFilePath) async {
    // 1. Embedded lyrics via platform channel / tag reader
    final embeddedText = await getEmbeddedLyrics(audioFilePath);
    if (embeddedText != null && embeddedText.trim().isNotEmpty) {
      final syncedLines = parse(embeddedText, source: LyricsSource.embedded);
      if (syncedLines.isNotEmpty) {
        return LyricsResult(lines: syncedLines, source: LyricsSource.embedded);
      }
      final plainLines = parsePlainText(embeddedText, source: LyricsSource.embedded);
      if (plainLines.isNotEmpty) {
        return LyricsResult(lines: plainLines, source: LyricsSource.embedded);
      }
    }

    // 2. External .lrc file
    final lrcLines = await findAndParseLrc(audioFilePath, source: LyricsSource.externalLrc);
    if (lrcLines != null && lrcLines.isNotEmpty) {
      return LyricsResult(lines: lrcLines, source: LyricsSource.externalLrc);
    }

    // 3. Fallback to null
    return null;
  }
}
