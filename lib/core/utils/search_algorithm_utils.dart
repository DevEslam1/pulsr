import 'dart:collection';
import 'dart:math' as math;

import '../../data/db/app_database.dart';

/// Pure search-matching primitives shared by the search feature: Unicode
/// normalization, a memory-bounded Levenshtein distance, fuzzy field matching
/// and relevance ranking. Deliberately free of Cubit/DI state so it can be
/// unit-tested in isolation (I3).
class SearchAlgorithmUtils {
  SearchAlgorithmUtils._();

  /// Single bound applied to the query at every stage of the pipeline.
  /// The FTS query and the fuzzy post-filter MUST use the same length: if the
  /// post-filter tests a prefix of the real needle it admits false positives.
  static const int maxQueryLength = 64;

  /// Maximum number of matches handed to the UI. Must stay >= the repository
  /// FTS window so the presentation layer never truncates what the data layer
  /// was willing to return.
  static const int maxResultCount = 200;

  static const int _normCacheMax = 1000;

  /// C-04: codec sets used by the format filter chips.
  static const Set<String> _flacCodecs = {'flac'};
  static const Set<String> _mp3Codecs = {'mp3'};
  static const Set<String> _losslessCodecs = {
    'flac',
    'wav',
    'wave',
    'alac',
    'aiff',
    'aif',
    'aifc',
    'dsd',
    'dsf',
    'dff',
    'ape',
    'wv',
  };

  /// True when [song]'s real codec (or, as a fallback, its file extension)
  /// belongs to [codecs]. Used by the FLAC/MP3/Lossless filter chips.
  static bool _codecMatches(SongsTableData song, Set<String> codecs) {
    final codec = (song.codec ?? '').trim().toLowerCase();
    // Trust the real codec from the header when present; only fall back to the
    // file extension when it is unknown, so a renamed file cannot slip through.
    if (codec.isNotEmpty) return codecs.contains(codec);
    final path = song.path.toLowerCase();
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return false;
    return codecs.contains(path.substring(dot + 1));
  }

  static bool _isFormatFilter(String filter) =>
      filter == 'FLAC' || filter == 'MP3' || filter == 'Lossless';

  static bool _formatMatches(SongsTableData song, String filter) {
    switch (filter) {
      case 'FLAC':
        return _codecMatches(song, _flacCodecs);
      case 'MP3':
        return _codecMatches(song, _mp3Codecs);
      case 'Lossless':
        return _codecMatches(song, _losslessCodecs);
      default:
        return true;
    }
  }

  static final RegExp _whitespace = RegExp(r'\s+');

  // LRU bounded cache to prevent unbounded retention. Keyed by raw metadata so
  // a retagged song is not served stale normalized text; the superseded entry
  // ages out through LRU eviction. Word splits are cached alongside the
  // normalized fields so the fuzzy word pass never re-splits per query.
  static final LinkedHashMap<String, _NormMeta> _normCache = LinkedHashMap();

  /// Test-only: drops every cached normalized metadata entry.
  static void clearCache() => _normCache.clear();

  static _NormMeta _normalizeMeta(String title, String artist, String album) {
    final t = normalize(title);
    final a = normalize(artist);
    final b = normalize(album);
    return (
      title: t,
      artist: a,
      album: b,
      titleWords: t.split(_whitespace),
      artistWords: a.split(_whitespace),
      albumWords: b.split(_whitespace),
    );
  }

  static int _trigramHashAt(String s, int i) =>
      (s.codeUnitAt(i) << 32) |
      (s.codeUnitAt(i + 1) << 16) |
      s.codeUnitAt(i + 2);

  /// Hash set of every 3-code-unit window in [s], computed once per query.
  static Set<int> _trigramHashes(String s) {
    final out = <int>{};
    for (var i = 0; i + 3 <= s.length; i++) {
      out.add(_trigramHashAt(s, i));
    }
    return out;
  }

  static bool _sharesTrigram(String text, Set<int> trigrams) {
    for (var i = 0; i + 3 <= text.length; i++) {
      if (trigrams.contains(_trigramHashAt(text, i))) return true;
    }
    return false;
  }

  /// Normalizes Unicode, Arabic diacritics / letter variants, and Latin
  /// accents for fuzzy search.
  static String normalize(String s) {
    var str = s.toLowerCase();
    // 1. Strip Arabic Tashkeel / Harakat
    str = str.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // 2. Normalize Arabic Alef variants & letters
    str = str
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ـ', ''); // Strip Tatweel
    // 3. Normalize common Latin accents
    str = str
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ýÿ]'), 'y')
        .replaceAll('ñ', 'n')
        .replaceAll('ç', 'c');
    return str.trim();
  }

  /// Bounded Levenshtein distance. Uses a two-row buffer O(min(N, M)) instead
  /// of the full (N+1)*(M+1) matrix and early-exits when the length gap alone
  /// already exceeds the tolerated distance (2).
  static int levenshtein(String a, String b) {
    if (a.length > 200 || b.length > 200) return 999;
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final lenDiff = (a.length - b.length).abs();
    if (lenDiff > 2) return lenDiff;

    var s1 = a;
    var s2 = b;
    if (s1.length < s2.length) {
      final temp = s1;
      s1 = s2;
      s2 = temp;
    }

    var prevRow = List<int>.generate(s2.length + 1, (i) => i);
    var currRow = List<int>.filled(s2.length + 1, 0);

    for (var i = 1; i <= s1.length; i++) {
      currRow[0] = i;
      for (var j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        currRow[j] = math.min(
          prevRow[j] + 1,
          math.min(
            currRow[j - 1] + 1,
            prevRow[j - 1] + cost,
          ),
        );
      }
      final temp = prevRow;
      prevRow = currRow;
      currRow = temp;
    }
    return prevRow[s2.length];
  }

  static _NormMeta _normalizedMetadata(SongsTableData song) {
    final key = '${song.id}|${song.title}|${song.artist}|${song.album}';
    final cached = _normCache.remove(key);
    if (cached != null) {
      // Refresh LRU recency.
      _normCache[key] = cached;
      return cached;
    }
    final norm = _normalizeMeta(song.title, song.artist, song.album);
    if (_normCache.length >= _normCacheMax) {
      _normCache.remove(_normCache.keys.first);
    }
    _normCache[key] = norm;
    return norm;
  }

  /// Filters [songs] against [rawQuery] (already server-side pre-filtered) and
  /// returns relevance-ranked matches capped at [maxResults] (defaults to
  /// [maxResultCount]). The query is normalized once and its trigrams are
  /// precomputed once so the per-song matching pass never re-normalizes or
  /// re-splits.
  static List<SongsTableData> filterWithFuzzy(
    List<SongsTableData> songs,
    String rawQuery,
    String filter, {
    int? maxResults,
  }) {
    final bounded = rawQuery.length > maxQueryLength
        ? rawQuery.substring(0, maxQueryLength)
        : rawQuery;
    final q = normalize(bounded);
    final limit = maxResults ?? maxResultCount;
    if (limit <= 0) return const [];
    final qTrigrams = q.length >= 3 ? _trigramHashes(q) : const <int>{};
    final matches = <({SongsTableData song, int score})>[];

    bool matchesField(String text, List<String> words) {
      if (text.contains(q)) return true;
      // Skip Levenshtein distance check for queries < 3 chars.
      if (q.length < 3) return false;
      final diff = (text.length - q.length).abs();
      // Edit distance <= 2 implies a length gap <= 2. For long fields a
      // missing shared trigram is a sound reject: with only two edits the
      // longest unbroken run is >= (length - 2) / 3 > 2 at length >= 9.
      if (diff <= 2 &&
          (text.length < 9 || _sharesTrigram(text, qTrigrams)) &&
          levenshtein(text, q) <= 2) {
        return true;
      }
      // Word-level fuzzy match; words outside the distance window cannot
      // match, so they never reach the DP.
      for (final word in words) {
        if (word.length < 3) continue;
        final lenDiff = word.length - q.length;
        if (lenDiff > 2 || lenDiff < -2) continue;
        if (word.length >= 9 && !_sharesTrigram(word, qTrigrams)) continue;
        if (levenshtein(word, q) <= 2) return true;
      }
      return false;
    }

    for (final song in songs) {
      if (matches.length >= limit) break;

      final norm = _normalizedMetadata(song);

      final matched = switch (filter) {
        'Songs' => matchesField(norm.title, norm.titleWords),
        'Artists' => matchesField(norm.artist, norm.artistWords),
        'Albums' => matchesField(norm.album, norm.albumWords),
        _ => matchesField(norm.title, norm.titleWords) ||
            matchesField(norm.artist, norm.artistWords) ||
            matchesField(norm.album, norm.albumWords),
      };

      // C-04: format chips additionally constrain by codec while still
      // honouring the text query (format filters behave as "All" for fields).
      final formatOk =
          _isFormatFilter(filter) ? _formatMatches(song, filter) : true;

      if (matched && formatOk) {
        matches.add((song: song, score: _relevanceScore(norm, q)));
      }
    }

    // Relevance ranking: exact title first, then prefix, then exact
    // artist/album, then title word, then contains; stable by title otherwise.
    matches.sort((a, b) {
      if (a.score != b.score) return a.score.compareTo(b.score);
      return a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase());
    });
    return [for (final m in matches) m.song];
  }

  static int _relevanceScore(_NormMeta norm, String q) {
    final t = norm.title;
    final ar = norm.artist;
    final al = norm.album;
    if (t == q) return 0;
    if (t.startsWith(q)) return 1;
    if (ar == q || al == q) return 2;
    if (norm.titleWords.any((w) => w == q || w.startsWith(q))) return 3;
    if (t.contains(q)) return 4;
    if (ar.contains(q) || al.contains(q)) return 5;
    return 6;
  }
}

typedef _NormMeta = ({
  String title,
  String artist,
  String album,
  List<String> titleWords,
  List<String> artistWords,
  List<String> albumWords,
});
