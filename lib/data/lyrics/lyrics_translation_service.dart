import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/lyrics_line.dart';

class LyricsTranslationResult {
  final List<LyricsLine> lines;
  final String sourceLanguage;
  final bool fromCache;
  final bool isSameLanguage;
  final bool isRomanized;

  const LyricsTranslationResult({
    required this.lines,
    this.sourceLanguage = '',
    this.fromCache = false,
    this.isSameLanguage = false,
    this.isRomanized = false,
  });
}

const int _maxMemoryEntries = 24;

/// Service providing on-demand translation and romanization of song lyrics
/// using Google Translate and Google Input Tools endpoints, with 2-level caching
/// (memory LRU + SharedPreferences).
class LyricsTranslationService {
  static const String _translateEndpoint =
      'https://translate.googleapis.com/translate_a/single';
  static const String _inputToolsEndpoint =
      'https://inputtools.google.com/request';
  static const String _cachePrefix = 'lyr_trans_v1_';
  static const String _diskIndexKey = 'lyr_trans_index_v1';
  static const int _maxDiskEntries = 100;
  static const int _maxBatchChars = 3200;

  static final Map<String, _CachedTranslation> _memoryCache = {};
  static Future<void> _diskIndexChain = Future<void>.value();
  static final RegExp _markerRegex = RegExp(r'\uE000[^\uE001]*\uE001');

  final http.Client _client;
  final bool _ownsClient;

  LyricsTranslationService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  /// Generates a deterministic cache key.
  static String _generateCacheKey({
    required String trackId,
    required String targetLang,
    required List<String> texts,
    required bool romanize,
  }) {
    final sb = StringBuffer();
    sb.write(trackId);
    sb.write('|');
    sb.write(romanize ? 'rm' : targetLang);
    for (final t in texts) {
      sb.write('|');
      sb.write(t.trim());
    }
    return sha256.convert(utf8.encode(sb.toString())).toString();
  }

  static void _putMemoryCache(String key, _CachedTranslation entry) {
    _memoryCache.remove(key);
    while (_memoryCache.length >= _maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = entry;
  }

  /// Translates [lines] into [targetLanguage] (e.g. 'en', 'es', 'ja', 'ar').
  Future<LyricsTranslationResult> translateLyrics({
    required List<LyricsLine> lines,
    required String targetLanguage,
    String trackId = '',
  }) async {
    final target = targetLanguage.trim().toLowerCase();
    if (lines.isEmpty || target.isEmpty) {
      return LyricsTranslationResult(lines: lines);
    }

    final slots = lines.map((l) => l.text.trim()).toList();
    final cacheKey = _generateCacheKey(
      trackId: trackId,
      targetLang: target,
      texts: slots,
      romanize: false,
    );

    // 1. Check in-memory cache (LRU touch)
    final mem = _memoryCache.remove(cacheKey);
    if (mem != null) {
      _memoryCache[cacheKey] = mem;
      if (mem.texts.length == lines.length) {
        return _buildResultFromCache(lines, mem, fromMemory: true);
      }
    }

    // 2. Check SharedPreferences cache
    final disk = await _readFromDiskCache(cacheKey);
    if (disk != null && disk.texts.length == lines.length) {
      _putMemoryCache(cacheKey, disk);
      return _buildResultFromCache(lines, disk, fromMemory: false);
    }

    // 3. Batch and perform network translation
    try {
      final batches = _createBatches(slots);
      final List<String> translatedTexts = [];
      String detectedSource = 'auto';

      for (final batch in batches) {
        final answer = await _requestTranslationBatch(batch, target);
        if (answer == null) {
          return LyricsTranslationResult(lines: lines);
        }
        translatedTexts.addAll(answer.translations);
        if (answer.sourceLanguage.isNotEmpty && detectedSource == 'auto') {
          detectedSource = answer.sourceLanguage;
        }
      }

      if (translatedTexts.length != lines.length) {
        return LyricsTranslationResult(lines: lines);
      }

      final isSameLang =
          detectedSource.isNotEmpty && _isSameLanguage(detectedSource, target);

      final entry = _CachedTranslation(
        sourceLanguage: detectedSource,
        targetLanguage: target,
        texts: translatedTexts,
        isRomanized: false,
      );

      _putMemoryCache(cacheKey, entry);
      unawaited(_writeToDiskCache(cacheKey, entry));

      final updatedLines = List<LyricsLine>.generate(lines.length, (i) {
        final orig = lines[i];
        final trans = translatedTexts[i];
        return orig.copyWith(
          translation: trans.isNotEmpty ? trans : orig.translation,
        );
      });

      return LyricsTranslationResult(
        lines: updatedLines,
        sourceLanguage: detectedSource,
        fromCache: false,
        isSameLanguage: isSameLang,
      );
    } catch (e, st) {
      ErrorLogger.log('Lyrics translation error',
          error: e, stackTrace: st, category: 'LyricsTranslation');
      return LyricsTranslationResult(lines: lines);
    }
  }

  /// Romanizes [lines] (transliterates non-Latin scripts to Latin alphabet).
  Future<LyricsTranslationResult> romanizeLyrics({
    required List<LyricsLine> lines,
    String trackId = '',
    String fallbackTargetLanguage = 'en',
  }) async {
    if (lines.isEmpty) return LyricsTranslationResult(lines: lines);

    final slots = lines.map((l) => l.text.trim()).toList();
    // Fast check: if all lines are already predominantly Latin script, skip
    if (!_hasNonLatinLetters(slots)) {
      return LyricsTranslationResult(
        lines: lines,
        isRomanized: true,
        sourceLanguage: 'en',
      );
    }

    final cacheKey = _generateCacheKey(
      trackId: trackId,
      targetLang: 'rm',
      texts: slots,
      romanize: true,
    );

    final mem = _memoryCache.remove(cacheKey);
    if (mem != null) {
      _memoryCache[cacheKey] = mem;
      if (mem.texts.length == lines.length) {
        return _buildResultFromCache(lines, mem, fromMemory: true);
      }
    }

    final disk = await _readFromDiskCache(cacheKey);
    if (disk != null && disk.texts.length == lines.length) {
      _putMemoryCache(cacheKey, disk);
      return _buildResultFromCache(lines, disk, fromMemory: false);
    }

    try {
      final batches = _createBatches(slots);
      final List<String> romanizedTexts = [];
      String detectedSource = 'auto';

      for (final batch in batches) {
        var answer = await _requestRomanizationBatch(
          batch,
          fallbackTargetLanguage,
          onDetectedSource: (src) {
            if (src.isNotEmpty && detectedSource == 'auto') {
              detectedSource = src;
            }
          },
        );
        if (answer == null) {
          // Allow InputTools fallback on batch 1 using detected source or script detection
          var lang = detectedSource != 'auto' ? detectedSource : '';
          if (lang.isEmpty || lang == 'auto') {
            lang = _detectScriptLanguage(batch.texts);
          }
          if (lang.isNotEmpty && lang != 'auto') {
            answer = await _requestInputToolsBatch(batch, lang);
          }
        }
        if (answer == null) {
          return LyricsTranslationResult(lines: lines);
        }
        romanizedTexts.addAll(answer.translations);
        if (answer.sourceLanguage.isNotEmpty && detectedSource == 'auto') {
          detectedSource = answer.sourceLanguage;
        }
      }

      if (romanizedTexts.length != lines.length) {
        return LyricsTranslationResult(lines: lines);
      }

      final entry = _CachedTranslation(
        sourceLanguage: detectedSource,
        targetLanguage: 'Latn',
        texts: romanizedTexts,
        isRomanized: true,
      );

      _putMemoryCache(cacheKey, entry);
      unawaited(_writeToDiskCache(cacheKey, entry));

      final updatedLines = List<LyricsLine>.generate(lines.length, (i) {
        final orig = lines[i];
        final rom = romanizedTexts[i];
        return orig.copyWith(
          romanization: rom.isNotEmpty ? rom : orig.romanization,
        );
      });

      return LyricsTranslationResult(
        lines: updatedLines,
        sourceLanguage: detectedSource,
        fromCache: false,
        isRomanized: true,
      );
    } catch (e, st) {
      ErrorLogger.log('Lyrics romanization error',
          error: e, stackTrace: st, category: 'LyricsTranslation');
      return LyricsTranslationResult(lines: lines);
    }
  }

  LyricsTranslationResult _buildResultFromCache(
    List<LyricsLine> lines,
    _CachedTranslation cached, {
    required bool fromMemory,
  }) {
    final updatedLines = List<LyricsLine>.generate(lines.length, (i) {
      final orig = lines[i];
      final text = cached.texts[i];
      if (cached.isRomanized) {
        return orig.copyWith(
          romanization: text.isNotEmpty ? text : orig.romanization,
        );
      }
      return orig.copyWith(
        translation: text.isNotEmpty ? text : orig.translation,
      );
    });

    return LyricsTranslationResult(
      lines: updatedLines,
      sourceLanguage: cached.sourceLanguage,
      fromCache: true,
      isSameLanguage:
          _isSameLanguage(cached.sourceLanguage, cached.targetLanguage),
      isRomanized: cached.isRomanized,
    );
  }

  List<_Batch> _createBatches(List<String> texts) {
    final batches = <_Batch>[];
    var current = <String>[];
    var length = 0;

    void flush() {
      if (current.isEmpty) return;
      final payload = _buildPayload(current);
      batches.add(_Batch(texts: List.unmodifiable(current), payload: payload));
      current = <String>[];
      length = 0;
    }

    for (final text in texts) {
      final added = text.length + (current.isEmpty ? 0 : 8);
      if (current.isNotEmpty && length + added > _maxBatchChars) {
        flush();
      }
      current.add(text);
      length += added;
    }
    flush();
    return batches;
  }

  String _buildPayload(List<String> texts) {
    final sb = StringBuffer();
    for (int i = 0; i < texts.length; i++) {
      if (i > 0) {
        sb.write('\n\uE000${i.toString().padLeft(4, '0')}\uE001\n');
      }
      sb.write(texts[i].isNotEmpty ? texts[i] : '...');
    }
    return sb.toString();
  }

  Future<_BatchAnswer?> _requestTranslationBatch(
    _Batch batch,
    String targetLang,
  ) async {
    try {
      final uri = Uri.parse(_translateEndpoint);
      final response = await _client.post(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Android; Pulsr)',
        },
        body: {
          'client': 'dict-chrome-ex',
          'sl': 'auto',
          'tl': targetLang,
          'dt': 't',
          'q': batch.payload,
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return null;

      final dynamic data =
          jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (data is! List || data.isEmpty) return null;

      final segments = data[0];
      if (segments is! List) return null;

      final sb = StringBuffer();
      for (final s in segments) {
        if (s is List && s.isNotEmpty && s[0] != null) {
          sb.write(s[0].toString());
        }
      }

      final String fullTranslated = sb.toString();
      final String source =
          (data.length > 2 && data[2] != null) ? data[2].toString() : '';

      final parts =
          fullTranslated.split(_markerRegex).map((s) => s.trim()).toList();
      if (parts.length != batch.texts.length) {
        // Fallback newline splitting if delimiter was touched
        final nlParts = fullTranslated
            .split(RegExp(r'\r?\n'))
            .map((s) => s.trim())
            .toList();
        if (nlParts.length == batch.texts.length) {
          return _BatchAnswer(translations: nlParts, sourceLanguage: source);
        }
        return null;
      }

      return _BatchAnswer(translations: parts, sourceLanguage: source);
    } catch (e, st) {
      ErrorLogger.log('Translation request batch failed',
          error: e, stackTrace: st, category: 'LyricsTranslation');
      return null;
    }
  }

  Future<_BatchAnswer?> _requestRomanizationBatch(
    _Batch batch,
    String targetLang, {
    void Function(String source)? onDetectedSource,
  }) async {
    try {
      final uri = Uri.parse(_translateEndpoint);
      final response = await _client.post(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Android; Pulsr)',
        },
        body: {
          'client': 'dict-chrome-ex',
          'sl': 'auto',
          'tl': targetLang,
          'dt': 'rm',
          'q': batch.payload,
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return null;

      final dynamic data =
          jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (data is! List || data.isEmpty) return null;

      final segments = data[0];
      if (segments is! List) return null;

      final sb = StringBuffer();
      for (final s in segments) {
        if (s is List && s.length > 3 && s[3] != null) {
          sb.write(s[3].toString());
        } else if (s is List && s.isNotEmpty && s[0] != null) {
          // If romanization segment sits at segment[0]
          sb.write(s[0].toString());
        }
      }

      final String fullRomanized = sb.toString();
      final String source =
          (data.length > 2 && data[2] != null) ? data[2].toString() : '';
      if (source.isNotEmpty) {
        onDetectedSource?.call(source);
      }

      final parts =
          fullRomanized.split(_markerRegex).map((s) => s.trim()).toList();
      if (parts.length == batch.texts.length) {
        return _BatchAnswer(translations: parts, sourceLanguage: source);
      }
      return null;
    } catch (e, st) {
      ErrorLogger.log('Romanization request batch failed',
          error: e, stackTrace: st, category: 'LyricsTranslation');
      return null;
    }
  }

  Future<_BatchAnswer?> _requestInputToolsBatch(
    _Batch batch,
    String sourceLanguage,
  ) async {
    try {
      final uri = Uri.parse(_inputToolsEndpoint);
      final response = await _client.post(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Android; Pulsr)',
        },
        body: {
          'text': batch.payload,
          'itc': '$sourceLanguage-t-i0-und',
          'num': '1',
          'cp': '0',
          'cs': '1',
          'ie': 'utf-8',
          'oe': 'utf-8',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final dynamic data =
          jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (data is! List || data.isEmpty || data[0] != 'SUCCESS') return null;

      String resultObj = '';
      if (data.length > 1 && data[1] is List && (data[1] as List).isNotEmpty) {
        final d10 = (data[1] as List)[0];
        if (d10 is List &&
            d10.length > 1 &&
            d10[1] is List &&
            (d10[1] as List).isNotEmpty) {
          resultObj = (d10[1] as List)[0]?.toString() ?? '';
        }
      }
      if (resultObj.isEmpty) return null;

      final parts = resultObj.split(_markerRegex).map((s) => s.trim()).toList();
      if (parts.length == batch.texts.length) {
        return _BatchAnswer(
            translations: parts, sourceLanguage: sourceLanguage);
      }
      return null;
    } catch (e, st) {
      ErrorLogger.log('InputTools request batch failed',
          error: e, stackTrace: st, category: 'LyricsTranslation');
      return null;
    }
  }

  static String _detectScriptLanguage(List<String> texts) {
    for (final text in texts) {
      for (final rune in text.runes) {
        // Japanese: Hiragana / Katakana
        if ((rune >= 0x3040 && rune <= 0x309F) ||
            (rune >= 0x30A0 && rune <= 0x30FF)) {
          return 'ja';
        }
        // Korean: Hangul
        if ((rune >= 0xAC00 && rune <= 0xD7AF) ||
            (rune >= 0x1100 && rune <= 0x11FF)) {
          return 'ko';
        }
        // Arabic
        if (rune >= 0x0600 && rune <= 0x06FF) {
          return 'ar';
        }
        // Cyrillic (Russian)
        if (rune >= 0x0400 && rune <= 0x04FF) {
          return 'ru';
        }
        // Devanagari (Hindi)
        if (rune >= 0x0900 && rune <= 0x097F) {
          return 'hi';
        }
        // Greek
        if (rune >= 0x0370 && rune <= 0x03FF) {
          return 'el';
        }
        // Hebrew
        if (rune >= 0x0590 && rune <= 0x05FF) {
          return 'he';
        }
        // Thai
        if (rune >= 0x0E00 && rune <= 0x0E7F) {
          return 'th';
        }
        // CJK Unified Ideographs (Chinese)
        if (rune >= 0x4E00 && rune <= 0x9FFF) {
          return 'zh';
        }
      }
    }
    return '';
  }

  static bool _hasNonLatinLetters(List<String> texts) {
    for (final text in texts) {
      for (final rune in text.runes) {
        if (_isNonLatinScriptRune(rune)) return true;
      }
    }
    return false;
  }

  static bool _isNonLatinScriptRune(int rune) {
    // Greek, Cyrillic, Armenian, Hebrew, Arabic, Syriac, Thaana, NKo, Indic,
    // Thai, Lao, Tibetan, Myanmar, Georgian, Hangul Jamo, Ethiopic, Khmer, etc.
    if (rune >= 0x0370 && rune <= 0x18AF) return true;
    // Greek Extended
    if (rune >= 0x1F00 && rune <= 0x1FFF) return true;
    // Hiragana, Katakana, Bopomofo, Hangul Compatibility Jamo, Kanbun, etc.
    // (excludes CJK Symbols and Punctuation 0x3000-0x303F)
    if (rune >= 0x3040 && rune <= 0x31FF) return true;
    // CJK Unified Ideographs Extension A & CJK Unified Ideographs
    if (rune >= 0x3400 && rune <= 0x9FFF) return true;
    // Yi & Hangul Syllables
    if (rune >= 0xA000 && rune <= 0xD7AF) return true;
    // CJK Compatibility Ideographs
    if (rune >= 0xF900 && rune <= 0xFAFF) return true;
    // Arabic Presentation Forms A & B
    if ((rune >= 0xFB50 && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF)) {
      return true;
    }
    // Halfwidth Katakana
    if (rune >= 0xFF66 && rune <= 0xFF9D) return true;
    // CJK Unified Ideographs Extensions B-I (excludes Emoji/Symbol blocks 0x1F000-0x1FFFF)
    if (rune >= 0x20000 && rune <= 0x2FA1F) return true;
    return false;
  }

  static bool _isSameLanguage(String src, String tgt) {
    final s = src.toLowerCase().split(RegExp('[-_]')).first;
    final t = tgt.toLowerCase().split(RegExp('[-_]')).first;
    if (s.isEmpty || t.isEmpty) return false;
    return s == t;
  }

  static Future<_CachedTranslation?> _readFromDiskCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$key');
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final texts = (map['texts'] as List).cast<String>();
      return _CachedTranslation(
        sourceLanguage: map['src'] as String? ?? '',
        targetLanguage: map['tgt'] as String? ?? '',
        texts: texts,
        isRomanized: map['rm'] as bool? ?? false,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to read lyrics translation from disk cache',
          error: e, stackTrace: st, category: 'LyricsTranslation');
      return null;
    }
  }

  static Future<void> _writeToDiskCache(
    String key,
    _CachedTranslation entry,
  ) {
    _diskIndexChain = _diskIndexChain.whenComplete(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final map = {
          'src': entry.sourceLanguage,
          'tgt': entry.targetLanguage,
          'texts': entry.texts,
          'rm': entry.isRomanized,
          'ts': DateTime.now().millisecondsSinceEpoch,
        };
        await prefs.setString('$_cachePrefix$key', jsonEncode(map));
        final index = prefs.getStringList(_diskIndexKey) ?? <String>[];
        index.remove(key);
        index.add(key);
        while (index.length > _maxDiskEntries) {
          final evicted = index.removeAt(0);
          await prefs.remove('$_cachePrefix$evicted');
        }
        await prefs.setStringList(_diskIndexKey, index);
      } catch (e, st) {
        ErrorLogger.log('Failed to write lyrics translation to disk cache',
            error: e, stackTrace: st, category: 'LyricsTranslation');
      }
    });
    return _diskIndexChain;
  }

  /// Clears in-memory and disk caches, serialized through _diskIndexChain.
  static Future<void> clearCache() {
    _memoryCache.clear();
    _diskIndexChain = _diskIndexChain.whenComplete(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final keys =
            prefs.getKeys().where((k) => k.startsWith(_cachePrefix)).toList();
        for (final k in keys) {
          await prefs.remove(k);
        }
        await prefs.remove(_diskIndexKey);
      } catch (e, st) {
        ErrorLogger.log('Failed to clear lyrics translation cache',
            error: e, stackTrace: st, category: 'LyricsTranslation');
      }
    });
    return _diskIndexChain;
  }
}

class _Batch {
  final List<String> texts;
  final String payload;
  const _Batch({required this.texts, required this.payload});
}

class _BatchAnswer {
  final List<String> translations;
  final String sourceLanguage;
  const _BatchAnswer({
    required this.translations,
    required this.sourceLanguage,
  });
}

class _CachedTranslation {
  final String sourceLanguage;
  final String targetLanguage;
  final List<String> texts;
  final bool isRomanized;

  const _CachedTranslation({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.texts,
    required this.isRomanized,
  });
}
