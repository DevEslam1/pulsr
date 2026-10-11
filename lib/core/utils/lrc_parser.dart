// lib/core/utils/lrc_parser.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/lyrics_line.dart';
import '../constants/channels.dart';
import 'error_logger.dart';

class LrcParser {
  static const MethodChannel _lyricsChannel =
      MethodChannel(PulsrChannels.lyrics);
  static const int _maxCacheSize = 50;
  static final LinkedHashMap<String, LyricsResult?> _lyricsCache =
      LinkedHashMap();

  /// Parses raw LRC string content into a sorted list of `LyricsLine`.
  static List<LyricsLine> parse(String lrcContent,
      {LyricsSource source = LyricsSource.none}) {
    return parseWithMetadata(lrcContent, source: source).lines;
  }

  /// Parses raw LRC string content with extended metadata tags ([ar:], [ti:], [by:], [offset:]).
  static LyricsResult parseWithMetadata(String lrcContent,
      {LyricsSource source = LyricsSource.none}) {
    // Strip UTF-8 BOM if present
    var content = lrcContent;
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }
    final lines = content.split(RegExp(r'\r?\n'));
    final List<LyricsLine> result = [];
    final Map<String, String> metadata = {};

    // Check for [offset:+/-ms] tag and other metadata
    int offsetMs = 0;
    final RegExp metaExp = RegExp(
        r'^\s*\[(ar|ti|al|by|offset|length):([^\]]*)\]',
        caseSensitive: false);

    for (final rawLine in lines) {
      var trimmed = rawLine.trim();
      // Consecutive metadata tags ([ar:][ti:]) were previously recorded only
      // up to the first match; strip them all so each is captured.
      while (true) {
        final metaMatch = metaExp.firstMatch(trimmed);
        if (metaMatch == null) break;
        final key = metaMatch.group(1)!.toLowerCase();
        final value = metaMatch.group(2)!.trim();
        metadata[key] = value;
        if (key == 'offset') {
          offsetMs = int.tryParse(value) ?? 0;
        }
        trimmed = trimmed.substring(metaMatch.end).trimLeft();
      }
    }

    final RegExp timeExp =
        RegExp(r'\[(-)?(\d{1,3}):(\d{2})(?:[.,:](\d{1,3}))?\]');
    final RegExp wordTagExp = RegExp(r'<(?:\d{1,3}:)?\d{2}(?:[.,:]\d{1,3})?>');

    for (final rawLine in lines) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      // Strip leading metadata tags instead of dropping the whole line, so
      // `[ar:X][00:12.34]text` keeps its lyric.
      while (true) {
        final metaMatch = metaExp.firstMatch(line);
        if (metaMatch == null) break;
        line = line.substring(metaMatch.end).trimLeft();
      }
      if (line.isEmpty) continue;

      final matches = timeExp.allMatches(line).toList();
      if (matches.isEmpty) continue;

      final lastMatch = matches.last;
      final rawTextAfterTags = line.substring(lastMatch.end);
      final text = rawTextAfterTags.replaceAll(wordTagExp, '').trim();

      final isVocal = text.isNotEmpty &&
          text != '♪' &&
          text != '•••' &&
          text != '...' &&
          !text.toLowerCase().contains('instrumental');

      for (final match in matches) {
        final isNegative = match.group(1) == '-';
        final minutes = int.tryParse(match.group(2) ?? '');
        final seconds = int.tryParse(match.group(3) ?? '');
        if (minutes == null || seconds == null) continue;

        final fractionStr = match.group(4) ?? '0';
        final milliseconds =
            int.tryParse(fractionStr.padRight(3, '0').substring(0, 3)) ?? 0;

        var rawMs = minutes * 60000 + seconds * 1000 + milliseconds;
        if (isNegative) rawMs = -rawMs;
        var totalMs = rawMs + offsetMs;
        if (totalMs < 0) totalMs = 0;
        final totalDuration = Duration(milliseconds: totalMs);

        final words = _parseWordTimestamps(rawTextAfterTags, totalMs, offsetMs);

        result.add(LyricsLine(
          timestamp: totalDuration,
          text: text,
          source: source,
          words: words,
          isVocal: isVocal,
        ));
      }
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Combine bilingual lines with matching timestamps
    final List<LyricsLine> merged = [];
    for (int i = 0; i < result.length; i++) {
      final cur = result[i];
      if (merged.isNotEmpty &&
          (cur.timestamp.inMilliseconds - merged.last.timestamp.inMilliseconds)
                  .abs() <=
              50 &&
          merged.last.translation == null &&
          cur.text != merged.last.text) {
        merged[merged.length - 1] = merged.last.copyWith(translation: cur.text);
      } else {
        merged.add(cur);
      }
    }

    return LyricsResult(lines: merged, source: source, metadata: metadata);
  }

  static List<WordTimestamp> _parseWordTimestamps(
    String rawLine,
    int lineStartMs,
    int offsetMs,
  ) {
    final wordTagExp = RegExp(r'<(?:\d{1,3}:)?\d{2}(?:[.,:]\d{1,3})?>');
    final matches = wordTagExp.allMatches(rawLine).toList();
    if (matches.isEmpty) return const [];

    int parseTime(String tag) {
      final clean = tag.replaceAll(RegExp(r'[<>]'), '');
      final parts = clean.split(':');
      if (parts.length == 2) {
        final min = int.tryParse(parts[0]) ?? 0;
        final secParts = parts[1].split(RegExp(r'[.,]'));
        final sec = int.tryParse(secParts[0]) ?? 0;
        final frac = secParts.length > 1
            ? (int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ?? 0)
            : 0;
        final total = min * 60000 + sec * 1000 + frac + offsetMs;
        return total < 0 ? 0 : total;
      }
      // Minutes-less form (`<12.34>` / `<12>`): the value is seconds, not a
      // line-start fallback — treating every such word tag as lineStartMs
      // collapsed all enhanced-LRC word timings onto the line start.
      final secParts = clean.split(RegExp(r'[.,]'));
      final sec = int.tryParse(secParts[0]);
      if (sec == null) return lineStartMs;
      final frac = secParts.length > 1
          ? (int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ?? 0)
          : 0;
      final total = sec * 1000 + frac + offsetMs;
      return total < 0 ? 0 : total;
    }

    final words = <WordTimestamp>[];
    for (int i = 0; i < matches.length; i++) {
      final curMatch = matches[i];
      final startMs = parseTime(curMatch.group(0)!);
      final textStart = curMatch.end;
      final textEnd =
          (i + 1 < matches.length) ? matches[i + 1].start : rawLine.length;
      final word = rawLine.substring(textStart, textEnd).trim();

      final endMs = (i + 1 < matches.length)
          ? parseTime(matches[i + 1].group(0)!)
          : (startMs + 350);

      if (word.isNotEmpty) {
        words.add(WordTimestamp(
          word: word,
          startMs: startMs,
          endMs: endMs > startMs ? endMs : startMs + 50,
        ));
      }
    }
    return words;
  }

  /// Formats a list of [LyricsLine] into a valid LRC formatted string.
  static String formatToLrc(List<LyricsLine> lines) {
    final sb = StringBuffer();
    for (final line in lines) {
      final totalMs = line.timestamp.inMilliseconds;
      final minutes = (totalMs ~/ 60000).toString().padLeft(2, '0');
      final seconds = ((totalMs % 60000) ~/ 1000).toString().padLeft(2, '0');
      final centis = ((totalMs % 1000) ~/ 10).toString().padLeft(2, '0');
      final text = line.text.isNotEmpty ? line.text : '•••';
      sb.writeln('[$minutes:$seconds.$centis]$text');
    }
    return sb.toString();
  }

  /// Decodes raw `.lrc` bytes into text. Byte-order marks win (UTF-8,
  /// UTF-16LE, UTF-16BE — all common in real-world lyric files); without one
  /// the chain is UTF-8 -> latin1 so legacy files never fail to load.
  @visibleForTesting
  static String decodeLrcBytes(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return _decodeUtf8OrLatin1(bytes.sublist(3));
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), bigEndian: false);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), bigEndian: true);
    }
    return _decodeUtf8OrLatin1(bytes);
  }

  static String _decodeUtf8OrLatin1(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// Manual UTF-16 decode (no extra dependency) that combines surrogate pairs
  /// so supplementary-plane characters survive. A trailing odd byte is ignored.
  static String _decodeUtf16(List<int> bytes, {required bool bigEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(bigEndian
          ? (bytes[i] << 8) | bytes[i + 1]
          : bytes[i] | (bytes[i + 1] << 8));
    }
    final sb = StringBuffer();
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < units.length) {
        final low = units[i + 1];
        if (low >= 0xDC00 && low <= 0xDFFF) {
          sb.writeCharCode(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00));
          i++;
          continue;
        }
      }
      sb.writeCharCode(unit);
    }
    return sb.toString();
  }

  /// Parses plain text non-synced lyrics into a list of `LyricsLine`.
  static List<LyricsLine> parsePlainText(String text,
      {LyricsSource source = LyricsSource.embedded}) {
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

  /// Helper to read a file and parse as LRC, returning null if file missing or
  /// content doesn't contain synced timestamps.
  static Future<List<LyricsLine>?> _tryParseLrcFile(
      String path, LyricsSource source) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final content = decodeLrcBytes(bytes);
      final lines = parse(content, source: source);
      if (lines.isNotEmpty) return lines;
    } catch (_) {}
    return null;
  }

  /// Searches for a local `.lrc` file matching the audio file path across standard locations:
  /// 1. Exact path with .lrc extension (e.g. /Music/Song.lrc) – also tries .txt fallback
  /// 2. /Music/Lyrics/Song.lrc and /Music/lyrics/Song.lrc
  /// 3. /Music/lyrics.lrc (generic)
  static Future<List<LyricsLine>?> findAndParseLrc(
    String audioFilePath, {
    LyricsSource source = LyricsSource.externalLrc,
  }) async {
    if (audioFilePath.isEmpty ||
        audioFilePath.startsWith('content:') ||
        audioFilePath.startsWith('http') ||
        audioFilePath.startsWith('ytmusic://')) {
      return null;
    }
    try {
      final lastDot = audioFilePath.lastIndexOf('.');
      if (lastDot == -1) return null;
      final basePath = audioFilePath.substring(0, lastDot);

      // 1. Direct sibling .lrc (and .txt fallback for some providers)
      for (final ext in ['.lrc', '.txt', '.LRC', '.TXT']) {
        final candidate = '$basePath$ext';
        final lines = await _tryParseLrcFile(candidate, source);
        if (lines != null) return lines;
      }

      // Check sibling "Lyrics" / "lyrics" subdirectory (case-insensitive on ext4)
      final parentDir = File(audioFilePath).parent;
      final fileName = audioFilePath.split(Platform.pathSeparator).last;
      final dotIdx = fileName.lastIndexOf('.');
      final fileNameWithoutExt =
          dotIdx != -1 ? fileName.substring(0, dotIdx) : fileName;
      for (final subdirName in ['Lyrics', 'lyrics', 'LRC', 'lrc']) {
        for (final ext in ['.lrc', '.txt']) {
          final p =
              '${parentDir.path}${Platform.pathSeparator}$subdirName${Platform.pathSeparator}$fileNameWithoutExt$ext';
          final lines = await _tryParseLrcFile(p, source);
          if (lines != null) return lines;
        }
      }

      for (final genericName in ['lyrics.lrc', 'Lyrics.lrc', 'lyrics.txt']) {
        final genericLrc =
            File('${parentDir.path}${Platform.pathSeparator}$genericName');
        if (await genericLrc.exists()) {
          try {
            final bytes = await genericLrc.readAsBytes();
            final content = decodeLrcBytes(bytes);
            final lines = parse(content, source: source);
            if (lines.isNotEmpty) return lines;
            // If not synced, try plain-text fallback from generic file
            final plain = parsePlainText(content, source: source);
            if (plain.isNotEmpty) return plain;
          } catch (_) {}
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to read external .lrc file for $audioFilePath',
          error: e, stackTrace: st, category: 'LrcParser');
    }
    return null;
  }

  /// Attempts to fetch embedded lyrics via platform channel (Android only).
  static Future<String?> getEmbeddedLyrics(String audioFilePath) async {
    if (!Platform.isAndroid) return null;
    try {
      final String? lyrics = await _lyricsChannel.invokeMethod<String>(
        'getEmbeddedLyrics',
        {'filePath': audioFilePath},
      );
      if (lyrics != null && lyrics.trim().isNotEmpty) {
        return lyrics.trim();
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to query embedded lyrics for $audioFilePath',
          error: e, stackTrace: st, category: 'LrcParser');
    }
    return null;
  }

  /// Checks if lyrics are already cached in memory (positive or valid negative cache).
  static bool hasCachedLyrics({int? songId, String? path}) {
    final cacheKey = songId != null ? 'song_$songId' : path;
    if (cacheKey == null || !_lyricsCache.containsKey(cacheKey)) return false;
    final cached = _lyricsCache[cacheKey];
    if (cached == null) {
      final cachedTime = _negativeCacheTimes[cacheKey];
      if (cachedTime != null &&
          DateTime.now().difference(cachedTime) > _negativeCacheTtl) {
        _lyricsCache.remove(cacheKey);
        _negativeCacheTimes.remove(cacheKey);
        return false;
      }
    }
    return true;
  }

  /// Retrieves cached lyrics from in-memory LRU cache if available.
  static LyricsResult? getCachedLyrics({int? songId, String? path}) {
    final cacheKey = songId != null ? 'song_$songId' : path;
    if (cacheKey == null || !_lyricsCache.containsKey(cacheKey)) return null;
    final cached = _lyricsCache[cacheKey];
    if (cached == null) {
      final cachedTime = _negativeCacheTimes[cacheKey];
      if (cachedTime != null &&
          DateTime.now().difference(cachedTime) > _negativeCacheTtl) {
        _lyricsCache.remove(cacheKey);
        _negativeCacheTimes.remove(cacheKey);
        return null;
      }
    }
    // Refresh LRU order
    final restored = _lyricsCache.remove(cacheKey);
    _lyricsCache[cacheKey] = restored;
    return restored;
  }

  /// FIX-H02: Returns the timestamp when negative cache entry was recorded.
  static DateTime? getCacheTimestamp({int? songId, String? path}) {
    final cacheKey = songId != null ? 'song_$songId' : path;
    if (cacheKey == null) return null;
    return _negativeCacheTimes[cacheKey];
  }

  /// Invalidates memory and disk cache for a song so it can be re-fetched.
  static void invalidateCache({int? songId, String? path}) {
    if (songId != null) {
      final key = 'song_$songId';
      _lyricsCache.remove(key);
      _negativeCacheTimes.remove(key);
      unawaited(_deleteFromDiskCache(key));
    }
    if (path != null && path.isNotEmpty) {
      _lyricsCache.remove(path);
      _negativeCacheTimes.remove(path);
      unawaited(_deleteFromDiskCache(path));
    }
  }

  static Directory? _diskCacheDir;

  static String _diskCacheKey(String key) {
    var hash = 0xcbf29ce484222325;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    return (hash & 0x7FFFFFFFFFFFFFFF).toRadixString(16);
  }

  static Future<Directory?> _getDiskCacheDir() async {
    if (_diskCacheDir != null) return _diskCacheDir;
    try {
      final baseDir = await getApplicationSupportDirectory();
      final dir = Directory('${baseDir.path}/lyrics_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _diskCacheDir = dir;
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Serializes a [LyricsResult] for the disk cache. Version 2 carries word
  /// timestamps, translations, vocal flags and metadata; v1 only had
  /// ms/text/source and silently dropped the enhanced data.
  @visibleForTesting
  static Map<String, dynamic> encodeDiskCachePayload(LyricsResult result) {
    return {
      'v': 2,
      'source': result.source.name,
      'metadata': result.metadata,
      'lines': result.lines
          .map((l) => {
                'ms': l.timestamp.inMilliseconds,
                'text': l.text,
                'source': l.source.name,
                'vocal': l.isVocal,
                if (l.translation != null) 'translation': l.translation,
                if (l.words.isNotEmpty)
                  'words': l.words
                      .map((w) => {
                            'w': w.word,
                            's': w.startMs,
                            'e': w.endMs,
                          })
                      .toList(),
              })
          .toList(),
    };
  }

  /// Decodes a disk cache payload. Unknown future versions are ignored
  /// (returns null); legacy v1 payloads decode with defaults for the fields
  /// they never stored.
  @visibleForTesting
  static LyricsResult? decodeDiskCachePayload(Map<String, dynamic> data) {
    final version = data['v'];
    if (version is int && version > 2) return null;

    final rawSource = data['source'];
    final source = LyricsSource.values.firstWhere(
      (e) => e.name == rawSource,
      orElse: () => LyricsSource.lrclib,
    );

    final rawLines = data['lines'];
    if (rawLines is! List) return null;

    final lines = <LyricsLine>[];
    for (final item in rawLines) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final rawLineSource = map['source'];
      final lineSource = LyricsSource.values.firstWhere(
        (e) => e.name == rawLineSource,
        orElse: () => source,
      );

      final words = <WordTimestamp>[];
      final rawWords = map['words'];
      if (rawWords is List) {
        for (final w in rawWords) {
          if (w is! Map) continue;
          final word = w['w'];
          if (word is! String || word.isEmpty) continue;
          final rawStart = w['s'];
          final rawEnd = w['e'];
          final startMs = rawStart is num ? rawStart.toInt() : 0;
          final endMs = rawEnd is num ? rawEnd.toInt() : startMs + 50;
          words.add(WordTimestamp(
            word: word,
            startMs: startMs,
            endMs: endMs > startMs ? endMs : startMs + 50,
          ));
        }
      }

      final rawMs = map['ms'];
      final rawText = map['text'];
      final rawTranslation = map['translation'];
      final rawVocal = map['vocal'];
      lines.add(LyricsLine(
        timestamp: Duration(milliseconds: rawMs is num ? rawMs.toInt() : 0),
        text: rawText is String ? rawText : '',
        source: lineSource,
        words: words,
        translation: rawTranslation is String ? rawTranslation : null,
        isVocal: rawVocal is bool ? rawVocal : true,
      ));
    }

    final metadata = <String, String>{};
    final rawMetadata = data['metadata'];
    if (rawMetadata is Map) {
      rawMetadata.forEach((k, v) {
        if (k is String && v is String) metadata[k] = v;
      });
    }

    return LyricsResult(lines: lines, source: source, metadata: metadata);
  }

  static Future<void> _writeToDiskCache(
      String cacheKey, LyricsResult result) async {
    try {
      final dir = await _getDiskCacheDir();
      if (dir == null) return;
      final file = File('${dir.path}/${_diskCacheKey(cacheKey)}.json');
      final payload = encodeDiskCachePayload(result);
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (e) {
      // Disk-full / quota / permission — log once, never crash playback.
      ErrorLogger.log('Lyrics disk cache write failed',
          error: e, category: 'Lyrics');
    }
  }

  static Future<LyricsResult?> _readFromDiskCache(String cacheKey) async {
    try {
      final dir = await _getDiskCacheDir();
      if (dir == null) return null;
      final file = File('${dir.path}/${_diskCacheKey(cacheKey)}.json');
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      return decodeDiskCachePayload(data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteFromDiskCache(String cacheKey) async {
    try {
      final dir = await _getDiskCacheDir();
      if (dir == null) return;
      final file = File('${dir.path}/${_diskCacheKey(cacheKey)}.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<void> _clearDiskCache() async {
    try {
      final dir = await _getDiskCacheDir();
      if (dir == null) return;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        _diskCacheDir = null;
      }
    } catch (_) {}
  }

  /// Manually cache a resolved lyrics result (e.g. from LRCLIB or YTM).
  static void cacheLyricsResult(
    LyricsResult? result, {
    int? songId,
    String? path,
  }) {
    final cacheKey = songId != null ? 'song_$songId' : path;
    if (cacheKey == null) return;
    if (_lyricsCache.length >= _maxCacheSize) {
      final evictedKey = _lyricsCache.keys.first;
      _lyricsCache.remove(evictedKey);
      _negativeCacheTimes.remove(evictedKey);
    }
    _lyricsCache[cacheKey] = result;
    if (result == null) {
      _negativeCacheTimes[cacheKey] = DateTime.now();
    } else {
      _negativeCacheTimes.remove(cacheKey);
      unawaited(_writeToDiskCache(cacheKey, result));
    }
    if (songId != null && path != null && path.isNotEmpty) {
      _lyricsCache[path] = result;
      if (result == null) {
        _negativeCacheTimes[path] = DateTime.now();
      } else {
        _negativeCacheTimes.remove(path);
        unawaited(_writeToDiskCache(path, result));
      }
    }
  }

  /// Resolves lyrics following the fallback chain with in-memory caching:
  /// 1. Check in-memory LRU cache
  /// 2. Check persistent disk cache (offline LRCLIB / online results)
  /// 3. Embedded lyrics via platform channel / tag reader
  /// 4. External .lrc file
  /// 5. Online LRCLIB database query
  /// 6. null
  static final Map<String, DateTime> _negativeCacheTimes = {};
  static const Duration _negativeCacheTtl = Duration(minutes: 10);
  static final Map<String, Future<LyricsResult?>> _inFlightResolves = {};

  static Future<LyricsResult?> resolveLyrics(
    String audioFilePath, {
    int? songId,
    String? trackTitle,
    String? artist,
    String? album,
    int? durationSec,
    Object? lrclibService,
  }) async {
    final cacheKey = songId != null ? 'song_$songId' : audioFilePath;
    if (hasCachedLyrics(songId: songId, path: audioFilePath)) {
      return getCachedLyrics(songId: songId, path: audioFilePath);
    }
    // Dedup concurrent requests for the same song.
    final inFlight = _inFlightResolves[cacheKey];
    if (inFlight != null) return inFlight;
    final future = _resolveLyricsInner(
      audioFilePath,
      cacheKey: cacheKey,
      trackTitle: trackTitle,
      artist: artist,
      album: album,
      durationSec: durationSec,
      lrclibService: lrclibService,
    );
    _inFlightResolves[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inFlightResolves.remove(cacheKey);
    }
  }

  static Future<LyricsResult?> _resolveLyricsInner(
    String audioFilePath, {
    required String cacheKey,
    String? trackTitle,
    String? artist,
    String? album,
    int? durationSec,
    Object? lrclibService,
  }) async {
    // Check persistent disk cache before external searching or network lookups
    final diskCached = await _readFromDiskCache(cacheKey);
    if (diskCached != null) {
      _lyricsCache[cacheKey] = diskCached;
      return diskCached;
    }

    LyricsResult? resolved;
    List<LyricsLine>? embeddedPlainFallback;

    // 1. External .lrc file – highest priority for synced lyrics
    final lrcLines =
        await findAndParseLrc(audioFilePath, source: LyricsSource.externalLrc);
    if (lrcLines != null && lrcLines.isNotEmpty) {
      final isSynced = lrcLines.any((l) => l.timestamp > Duration.zero);
      if (isSynced) {
        resolved =
            LyricsResult(lines: lrcLines, source: LyricsSource.externalLrc);
      } else {
        // Keep as fallback if no synced source found
        embeddedPlainFallback = lrcLines;
      }
    }

    // 2. Embedded lyrics via platform channel / tag reader
    if (resolved == null) {
      final embeddedText = await getEmbeddedLyrics(audioFilePath);
      if (embeddedText != null && embeddedText.trim().isNotEmpty) {
        final syncedLines = parse(embeddedText, source: LyricsSource.embedded);
        if (syncedLines.isNotEmpty) {
          resolved =
              LyricsResult(lines: syncedLines, source: LyricsSource.embedded);
        } else {
          final plainLines =
              parsePlainText(embeddedText, source: LyricsSource.embedded);
          if (plainLines.isNotEmpty) {
            embeddedPlainFallback ??= plainLines;
            // Only use plain if no better source exists later (LRCLIB may provide synced)
          }
        }
      }
    }

    // Prefer external plain fallback if no synced yet and no LRCLIB will be tried
    // Otherwise keep plain for later if LRCLIB fails

    // 3. Online LRCLIB query
    if (resolved == null &&
        trackTitle != null &&
        trackTitle.isNotEmpty &&
        artist != null &&
        artist.isNotEmpty) {
      try {
        if (lrclibService != null) {
          resolved = await (lrclibService as dynamic).fetchLyrics(
            trackName: trackTitle,
            artistName: artist,
            albumName: album,
            durationSeconds: durationSec,
          );
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to fetch lyrics from LRCLIB for $trackTitle',
            error: e, stackTrace: st, category: 'LrcParser');
      }
    }

    // 4. Fallback to plain unsynced lyrics if no synced source succeeded
    if (resolved == null && embeddedPlainFallback != null) {
      final src = embeddedPlainFallback.first.source;
      resolved = LyricsResult(lines: embeddedPlainFallback, source: src);
    }

    // Cache the result (including null to avoid repeated failing lookups, with TTL)
    // Only cache negative null if online resolution was attempted (trackTitle != null)
    if (resolved != null || (trackTitle != null && trackTitle.isNotEmpty)) {
      // Proactively sweep expired negative entries so the map can't grow
      // across a long session of misses.
      if (_negativeCacheTimes.length > _maxCacheSize) {
        final now = DateTime.now();
        _negativeCacheTimes
            .removeWhere((_, t) => now.difference(t) > _negativeCacheTtl);
      }
      if (_lyricsCache.length >= _maxCacheSize) {
        final evictedKey = _lyricsCache.keys.first;
        _lyricsCache.remove(evictedKey);
        _negativeCacheTimes.remove(evictedKey);
      }
      _lyricsCache[cacheKey] = resolved;
      if (resolved == null) {
        _negativeCacheTimes[cacheKey] = DateTime.now();
      } else {
        _negativeCacheTimes.remove(cacheKey);
        unawaited(_writeToDiskCache(cacheKey, resolved));
      }
    }

    return resolved;
  }

  /// Invalidate lyrics cache for a specific song
  static void invalidateSong({int? songId, String? path}) {
    if (songId != null) {
      _lyricsCache.remove('song_$songId');
      _negativeCacheTimes.remove('song_$songId');
      unawaited(_deleteFromDiskCache('song_$songId'));
    }
    if (path != null) {
      _lyricsCache.remove(path);
      _negativeCacheTimes.remove(path);
      unawaited(_deleteFromDiskCache(path));
    }
  }

  /// Clear the lyrics cache (e.g. on tag edit or rescan)
  static void clearCache() {
    _lyricsCache.clear();
    _negativeCacheTimes.clear();
    unawaited(_clearDiskCache());
  }
}
