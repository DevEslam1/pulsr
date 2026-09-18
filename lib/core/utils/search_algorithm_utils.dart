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

  // LRU bounded cache to prevent unbounded retention. Keyed by raw metadata so
  // a retagged song is not served stale normalized text; the superseded entry
  // ages out through LRU eviction.
  static final LinkedHashMap<String, ({String title, String artist, String album})>
      _normCache = LinkedHashMap();

  /// Test-only: drops every cached normalized metadata entry.
  static void clearCache() => _normCache.clear();

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

  static ({String title, String artist, String album}) _normalizedMetadata(
      SongsTableData song) {
    final key = '${song.id}|${song.title}|${song.artist}|${song.album}';
    final cached = _normCache.remove(key);
    if (cached != null) {
      // Refresh LRU recency.
      _normCache[key] = cached;
      return cached;
    }
    final norm = (
      title: normalize(song.title),
      artist: normalize(song.artist),
      album: normalize(song.album),
    );
    if (_normCache.length >= _normCacheMax) {
      _normCache.remove(_normCache.keys.first);
    }
    _normCache[key] = norm;
    return norm;
  }

  /// Filters [songs] against [rawQuery] (already server-side pre-filtered) and
  /// returns relevance-ranked matches capped at [maxResultCount].
  static List<SongsTableData> filterWithFuzzy(
    List<SongsTableData> songs,
    String rawQuery,
    String filter,
  ) {
    final q = rawQuery.length > maxQueryLength
        ? rawQuery.substring(0, maxQueryLength)
        : rawQuery;
    final results = <SongsTableData>[];

    for (final song in songs) {
      if (results.length >= maxResultCount) break;

      final norm = _normalizedMetadata(song);
      final title = norm.title;
      final artist = norm.artist;
      final album = norm.album;

      bool matchesField(String text) {
        if (text.contains(q)) return true;
        // Skip Levenshtein distance check for queries < 3 chars
        if (q.length < 3) return false;
        if (levenshtein(text, q) <= 2) return true;
        // Word-level fuzzy match
        for (final word in text.split(RegExp(r'\s+'))) {
          if (word.length >= 3 && levenshtein(word, q) <= 2) return true;
        }
        return false;
      }

      final matches = switch (filter) {
        'Songs' => matchesField(title),
        'Artists' => matchesField(artist),
        'Albums' => matchesField(album),
        _ => matchesField(title) || matchesField(artist) || matchesField(album),
      };

      if (matches) {
        results.add(song);
      }
    }

    // Relevance ranking: exact title first, then prefix, then exact
    // artist/album, then title word, then contains; stable by title otherwise.
    results.sort((a, b) {
      int score(SongsTableData s) {
        final t = normalize(s.title);
        final ar = normalize(s.artist);
        final al = normalize(s.album);
        if (t == q) return 0;
        if (t.startsWith(q)) return 1;
        if (ar == q || al == q) return 2;
        final titleWord =
            t.split(RegExp(r'\s+')).any((w) => w == q || w.startsWith(q));
        if (titleWord) return 3;
        if (t.contains(q)) return 4;
        if (ar.contains(q) || al.contains(q)) return 5;
        return 6;
      }

      final sa = score(a);
      final sb = score(b);
      if (sa != sb) return sa.compareTo(sb);
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return results;
  }
}
