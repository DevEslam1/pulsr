// lib/core/utils/lrc_parser.dart
import 'dart:collection';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../domain/models/lyrics_line.dart';
import 'error_logger.dart';

class LrcParser {
  static const MethodChannel _lyricsChannel = MethodChannel('com.pulsr.music/lyrics');
  static const int _maxCacheSize = 50;
  static final LinkedHashMap<String, LyricsResult?> _lyricsCache = LinkedHashMap();

  /// Parses raw LRC string content into a sorted list of `LyricsLine`.
  static List<LyricsLine> parse(String lrcContent, {LyricsSource source = LyricsSource.none}) {
    final lines = lrcContent.split(RegExp(r'\r?\n'));
    final List<LyricsLine> result = [];

    // Match tags like [01:23.45] or [01:23.456] or [01:23.4] or [01:23] or [120:00.00]
    final RegExp timeExp = RegExp(r'\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]');

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
        final milliseconds = int.parse(fractionStr.padRight(3, '0').substring(0, 3));

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

  /// Searches for a local `.lrc` file matching the audio file path across standard locations:
  /// 1. Exact path with .lrc extension (e.g. /Music/Song.lrc)
  /// 2. /Music/Lyrics/Song.lrc
  /// 3. /Music/lyrics.lrc
  static Future<List<LyricsLine>?> findAndParseLrc(
    String audioFilePath, {
    LyricsSource source = LyricsSource.externalLrc,
  }) async {
    try {
      final lastDot = audioFilePath.lastIndexOf('.');
      if (lastDot == -1) return null;
      final directLrcPath = '${audioFilePath.substring(0, lastDot)}.lrc';
      final file = File(directLrcPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = parse(content, source: source);
        if (lines.isNotEmpty) return lines;
      }

      // Check sibling "Lyrics" subdirectory
      final parentDir = File(audioFilePath).parent;
      final fileName = audioFilePath.split(Platform.pathSeparator).last;
      final fileNameWithoutExt = fileName.substring(0, fileName.lastIndexOf('.'));
      final lyricsSubdirLrc = File('${parentDir.path}${Platform.pathSeparator}Lyrics${Platform.pathSeparator}$fileNameWithoutExt.lrc');
      if (await lyricsSubdirLrc.exists()) {
        final content = await lyricsSubdirLrc.readAsString();
        final lines = parse(content, source: source);
        if (lines.isNotEmpty) return lines;
      }

      final genericLrc = File('${parentDir.path}${Platform.pathSeparator}lyrics.lrc');
      if (await genericLrc.exists()) {
        final content = await genericLrc.readAsString();
        final lines = parse(content, source: source);
        if (lines.isNotEmpty) return lines;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to read external .lrc file for $audioFilePath', error: e, stackTrace: st, category: 'LrcParser');
    }
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
    } catch (e, st) {
      ErrorLogger.log('Failed to query embedded lyrics for $audioFilePath', error: e, stackTrace: st, category: 'LrcParser');
    }
    return null;
  }

  /// Resolves lyrics following the fallback chain with in-memory caching:
  /// 1. Check in-memory LRU cache
  /// 2. Embedded lyrics via platform channel / tag reader
  /// 3. External .lrc file
  /// 4. Online LRCLIB database query
  /// 5. null
  static Future<LyricsResult?> resolveLyrics(
    String audioFilePath, {
    int? songId,
    String? trackTitle,
    String? artist,
    String? album,
    int? durationSec,
    dynamic lrclibService,
  }) async {
    final cacheKey = songId != null ? 'song_$songId' : audioFilePath;
    if (_lyricsCache.containsKey(cacheKey)) {
      final cached = _lyricsCache.remove(cacheKey);
      _lyricsCache[cacheKey] = cached;
      return cached;
    }

    LyricsResult? resolved;

    // 1. Embedded lyrics via platform channel / tag reader
    final embeddedText = await getEmbeddedLyrics(audioFilePath);
    if (embeddedText != null && embeddedText.trim().isNotEmpty) {
      final syncedLines = parse(embeddedText, source: LyricsSource.embedded);
      if (syncedLines.isNotEmpty) {
        resolved = LyricsResult(lines: syncedLines, source: LyricsSource.embedded);
      } else {
        final plainLines = parsePlainText(embeddedText, source: LyricsSource.embedded);
        if (plainLines.isNotEmpty) {
          resolved = LyricsResult(lines: plainLines, source: LyricsSource.embedded);
        }
      }
    }

    // 2. External .lrc file
    if (resolved == null) {
      final lrcLines = await findAndParseLrc(audioFilePath, source: LyricsSource.externalLrc);
      if (lrcLines != null && lrcLines.isNotEmpty) {
        resolved = LyricsResult(lines: lrcLines, source: LyricsSource.externalLrc);
      }
    }

    // 3. Online LRCLIB query
    if (resolved == null && trackTitle != null && trackTitle.isNotEmpty && artist != null && artist.isNotEmpty) {
      try {
        if (lrclibService != null) {
          resolved = await lrclibService.fetchLyrics(
            trackName: trackTitle,
            artistName: artist,
            albumName: album,
            durationSeconds: durationSec,
          );
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to fetch lyrics from LRCLIB for $trackTitle', error: e, stackTrace: st, category: 'LrcParser');
      }
    }

    // Cache the result (including null to avoid repeated failing lookups)
    if (_lyricsCache.length >= _maxCacheSize) {
      _lyricsCache.remove(_lyricsCache.keys.first);
    }
    _lyricsCache[cacheKey] = resolved;

    return resolved;
  }

  /// Clear the lyrics cache (e.g. on tag edit or rescan)
  static void clearCache() {
    _lyricsCache.clear();
  }
}
