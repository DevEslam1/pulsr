import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import '../../core/di/injection.dart';
import '../../core/utils/error_logger.dart';
import '../audio/audio_handler.dart';
import '../audio/song_rating_store.dart';
import '../../domain/models/smart_playlist_criteria.dart';
import '../../domain/repositories/smart_playlist_engine_interface.dart';
import '../db/app_database.dart';

@Singleton(as: ISmartPlaylistEngine)
class SmartPlaylistEngine implements ISmartPlaylistEngine {
  final AppDatabase _db;

  SmartPlaylistEngine(this._db);

  SimpleSelectStatement<$SongsTableTable, SongsTableData> _buildQuery(
      SmartCriteria criteria) {
    final query = _db.select(_db.songsTable)
      ..where((t) =>
          t.isMissing.equals(false) &
          t.source.equals(SongSource.local) &
          t.path.like('ytmusic://%').not());

    if (criteria.rules.isNotEmpty) {
      query.where((t) {
        Expression<bool>? combined;
        for (final rule in criteria.rules) {
          // Rating and BPM live outside Drift (SharedPreferences): skipped
          // here without noise and applied as a Dart post-filter below.
          if (_isDartRule(rule.field)) continue;
          final expr = _buildRuleExpression(t, rule);
          if (expr == null) {
            ErrorLogger.log(
              'Smart playlist: ignoring unsupported rule '
              '${rule.field.name} ${rule.operator.name} "${rule.value}"',
              category: 'SmartPlaylist',
            );
            continue;
          }
          if (combined == null) {
            combined = expr;
          } else {
            combined =
                criteria.matchAll ? (combined & expr) : (combined | expr);
          }
        }
        return combined ?? const Constant(true);
      });
    }

    if (criteria.sortBy != null) {
      final mode =
          criteria.sortAscending ? OrderingMode.asc : OrderingMode.desc;
      // 'rating' is prefs-backed: SQL keeps a stable base order and the
      // Dart post-step re-sorts. Anything unknown falls back to title.
      switch (criteria.sortBy) {
        case 'rating':
          query.orderBy([(t) => OrderingTerm(expression: t.title)]);
          break;
        case 'dateAdded':
          query.orderBy(
              [(t) => OrderingTerm(expression: t.dateAdded, mode: mode)]);
          break;
        case 'playCount':
          query.orderBy(
              [(t) => OrderingTerm(expression: t.playCount, mode: mode)]);
          break;
        case 'lastPlayed':
          query.orderBy(
              [(t) => OrderingTerm(expression: t.lastPlayed, mode: mode)]);
          break;
        case 'durationMs':
          query.orderBy(
              [(t) => OrderingTerm(expression: t.durationMs, mode: mode)]);
          break;
        case 'year':
          query.orderBy([(t) => OrderingTerm(expression: t.year, mode: mode)]);
          break;
        case 'title':
        default:
          query.orderBy([(t) => OrderingTerm(expression: t.title, mode: mode)]);
          break;
      }
    }

    // When rating rules exist (or rating sort is requested) the limit is
    // applied in Dart AFTER the prefs-backed filter/sort; a SQL limit first
    // would truncate candidates before ratings are even considered.
    final needsDartPost = criteria.rules.any((r) => _isDartRule(r.field)) ||
        criteria.sortBy == 'rating';
    if (!needsDartPost && criteria.limit != null && criteria.limit! > 0) {
      query.limit(criteria.limit!);
    }

    return query;
  }

  /// Rules whose source of truth is not a Drift column (SharedPreferences):
  /// they are excluded from the SQL shape and applied as Dart post-filters.
  bool _isDartRule(SmartRuleField field) =>
      field == SmartRuleField.rating || field == SmartRuleField.bpm;

  Expression<bool>? _buildRuleExpression($SongsTableTable t, SmartRule rule) {
    final valStr = rule.value.trim();
    final valInt = int.tryParse(valStr);

    switch (rule.field) {
      case SmartRuleField.playCount:
        if (rule.operator == SmartOperator.between) {
          final b = _parseIntBetween(valStr);
          return b != null ? t.playCount.isBetweenValues(b.$1, b.$2) : null;
        }
        if (valInt == null) return null;
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.playCount.equals(valInt);
          case SmartOperator.greaterThan:
            return t.playCount.isBiggerThanValue(valInt);
          case SmartOperator.lessThan:
            return t.playCount.isSmallerThanValue(valInt);
          case SmartOperator.greaterThanOrEqual:
            return t.playCount.isBiggerOrEqualValue(valInt);
          case SmartOperator.lessThanOrEqual:
            return t.playCount.isSmallerOrEqualValue(valInt);
          default:
            return t.playCount.equals(valInt);
        }

      case SmartRuleField.artist:
        if (valStr.isEmpty) return null;
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.artist.lower().equals(valStr.toLowerCase());
          case SmartOperator.contains:
          default:
            return t.artist.lower().contains(valStr.toLowerCase());
        }

      case SmartRuleField.album:
        if (valStr.isEmpty) return null;
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.album.lower().equals(valStr.toLowerCase());
          case SmartOperator.contains:
          default:
            return t.album.lower().contains(valStr.toLowerCase());
        }

      case SmartRuleField.title:
        if (valStr.isEmpty) return null;
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.title.lower().equals(valStr.toLowerCase());
          case SmartOperator.contains:
          default:
            return t.title.lower().contains(valStr.toLowerCase());
        }

      case SmartRuleField.isLossless:
        final losslessExpr = t.codec.isIn(
                const ['FLAC', 'ALAC', 'WAV', 'AIFF', 'PCM', 'DSF', 'DFF']) |
            (t.bitDepth.isNotNull() & t.bitDepth.isBiggerOrEqualValue(24)) |
            t.path.lower().like('%.flac') |
            t.path.lower().like('%.wav') |
            t.path.lower().like('%.alac') |
            t.path.lower().like('%.aiff') |
            t.path.lower().like('%.dsf') |
            t.path.lower().like('%.dff');
        final wantLossless = valStr.toLowerCase() != 'false' &&
            valStr != '0' &&
            valStr.toLowerCase() != 'no';
        return wantLossless ? losslessExpr : losslessExpr.not();

      case SmartRuleField.decade:
        if (rule.operator == SmartOperator.between) {
          final b = _parseIntBetween(valStr);
          return b != null
              ? (t.year.isNotNull() & t.year.isBetweenValues(b.$1, b.$2))
              : null;
        }
        if (valInt == null) return null;
        final startYear = (valInt ~/ 10) * 10;
        final endYear = startYear + 9;
        return t.year.isNotNull() &
            t.year.isBiggerOrEqualValue(startYear) &
            t.year.isSmallerOrEqualValue(endYear);

      case SmartRuleField.genre:
        if (valStr.isEmpty) return null;
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.genre.isNotNull() &
                t.genre.lower().equals(valStr.toLowerCase());
          case SmartOperator.contains:
          default:
            return t.genre.isNotNull() &
                t.genre.lower().contains(valStr.toLowerCase());
        }

      case SmartRuleField.year:
        if (rule.operator == SmartOperator.between) {
          final b = _parseIntBetween(valStr);
          return b != null
              ? (t.year.isNotNull() & t.year.isBetweenValues(b.$1, b.$2))
              : null;
        }
        if (valInt == null) return null;
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.year.isNotNull() & t.year.equals(valInt);
          case SmartOperator.greaterThan:
            return t.year.isNotNull() & t.year.isBiggerThanValue(valInt);
          case SmartOperator.lessThan:
            return t.year.isNotNull() & t.year.isSmallerThanValue(valInt);
          case SmartOperator.greaterThanOrEqual:
            return t.year.isNotNull() & t.year.isBiggerOrEqualValue(valInt);
          case SmartOperator.lessThanOrEqual:
            return t.year.isNotNull() & t.year.isSmallerOrEqualValue(valInt);
          default:
            return t.year.isNotNull() & t.year.equals(valInt);
        }

      case SmartRuleField.dateAdded:
        if (rule.operator == SmartOperator.withinDays) {
          final days = valInt ?? 30;
          final cutoffSec =
              DateTime.now().millisecondsSinceEpoch ~/ 1000 - (days * 86400);
          return t.dateAdded.isBiggerOrEqualValue(cutoffSec);
        }
        if (rule.operator == SmartOperator.between) {
          final b = _parseIntBetween(valStr);
          return b != null ? t.dateAdded.isBetweenValues(b.$1, b.$2) : null;
        }
        if (valInt == null) return null;
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.dateAdded.equals(valInt);
          case SmartOperator.greaterThan:
            return t.dateAdded.isBiggerThanValue(valInt);
          case SmartOperator.lessThan:
            return t.dateAdded.isSmallerThanValue(valInt);
          case SmartOperator.greaterThanOrEqual:
            return t.dateAdded.isBiggerOrEqualValue(valInt);
          case SmartOperator.lessThanOrEqual:
            return t.dateAdded.isSmallerOrEqualValue(valInt);
          default:
            return t.dateAdded.isBiggerOrEqualValue(valInt);
        }

      case SmartRuleField.durationMs:
        if (rule.operator == SmartOperator.between) {
          final b = _parseIntBetween(valStr);
          return b != null ? t.durationMs.isBetweenValues(b.$1, b.$2) : null;
        }
        if (valInt == null) return null;
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.durationMs.equals(valInt);
          case SmartOperator.greaterThan:
            return t.durationMs.isBiggerThanValue(valInt);
          case SmartOperator.lessThan:
            return t.durationMs.isSmallerThanValue(valInt);
          case SmartOperator.greaterThanOrEqual:
            return t.durationMs.isBiggerOrEqualValue(valInt);
          case SmartOperator.lessThanOrEqual:
            return t.durationMs.isSmallerOrEqualValue(valInt);
          default:
            return t.durationMs.isBiggerOrEqualValue(valInt);
        }

      case SmartRuleField.isFavorite:
        final boolVal = valStr.toLowerCase() == 'true' || valStr == '1';
        return t.isFavorite.equals(boolVal);

      case SmartRuleField.rating:
        // Prefs-backed star ratings are invisible to SQL: skipped here and
        // applied as a Dart post-filter in evaluateCriteria/watchCriteria.
        return null;

      case SmartRuleField.lastPlayed:
        if (rule.operator == SmartOperator.withinDays) {
          final days = valInt ?? 30;
          final cutoffSec =
              DateTime.now().millisecondsSinceEpoch ~/ 1000 - (days * 86400);
          return t.lastPlayed.isNotNull() &
              t.lastPlayed.isBiggerOrEqualValue(cutoffSec);
        }
        if (rule.operator == SmartOperator.between) {
          final b = _parseIntBetween(valStr);
          return b != null
              ? (t.lastPlayed.isNotNull() &
                  t.lastPlayed.isBetweenValues(b.$1, b.$2))
              : null;
        }
        if (valInt == null) return null;
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.lastPlayed.isNotNull() & t.lastPlayed.equals(valInt);
          case SmartOperator.greaterThan:
            return t.lastPlayed.isNotNull() &
                t.lastPlayed.isBiggerThanValue(valInt);
          case SmartOperator.lessThan:
            return t.lastPlayed.isNotNull() &
                t.lastPlayed.isSmallerThanValue(valInt);
          case SmartOperator.greaterThanOrEqual:
            return t.lastPlayed.isNotNull() &
                t.lastPlayed.isBiggerOrEqualValue(valInt);
          case SmartOperator.lessThanOrEqual:
            return t.lastPlayed.isNotNull() &
                t.lastPlayed.isSmallerOrEqualValue(valInt);
          default:
            return t.lastPlayed.isNotNull() &
                t.lastPlayed.isBiggerOrEqualValue(valInt);
        }

      case SmartRuleField.bpm:
        // BPM overrides live in SharedPreferences, not a Drift column: the
        // SQL builder skips this rule and it is evaluated in Dart via
        // [_matchesDartRule] / [_bpmOf].
        return null;

      case SmartRuleField.loudnessRange:
        if (rule.operator == SmartOperator.between) {
          final b = _parseDoubleBetween(valStr);
          return b != null
              ? (t.loudnessRange.isNotNull() &
                  t.loudnessRange.isBetweenValues(b.$1, b.$2))
              : null;
        }
        final valDouble = double.tryParse(valStr);
        if (valDouble == null) return null;
        switch (rule.operator) {
          case SmartOperator.greaterThan:
            return t.loudnessRange.isNotNull() &
                t.loudnessRange.isBiggerThanValue(valDouble);
          case SmartOperator.lessThan:
            return t.loudnessRange.isNotNull() &
                t.loudnessRange.isSmallerThanValue(valDouble);
          default:
            return t.loudnessRange.isNotNull() &
                t.loudnessRange.equals(valDouble);
        }

      case SmartRuleField.bitrate:
        if (rule.operator == SmartOperator.between) {
          final b = _parseIntBetween(valStr);
          return b != null
              ? (t.bitrateKbps.isNotNull() &
                  t.bitrateKbps.isBetweenValues(b.$1, b.$2))
              : null;
        }
        if (valInt == null) return null;
        switch (rule.operator) {
          case SmartOperator.greaterThan:
            return t.bitrateKbps.isNotNull() &
                t.bitrateKbps.isBiggerThanValue(valInt);
          case SmartOperator.lessThan:
            return t.bitrateKbps.isNotNull() &
                t.bitrateKbps.isSmallerThanValue(valInt);
          default:
            return t.bitrateKbps.isNotNull() & t.bitrateKbps.equals(valInt);
        }
    }
  }

  (int, int)? _parseIntBetween(String valStr) {
    // Fix: previously `RegExp(r'[,.\s-]+|to|\.\.')` had `to` inside char class matching single t/o; now correctly handles "100 to 200" and "100..200"
    final normalized = valStr.replaceAll(RegExp(r'\bto\b', caseSensitive: false), ' ').replaceAll('..', ' ');
    final parts = normalized
        .split(RegExp(r'[,;\s-]+'))
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    if (parts.length >= 2) {
      final minVal = parts[0] <= parts[1] ? parts[0] : parts[1];
      final maxVal = parts[0] <= parts[1] ? parts[1] : parts[0];
      return (minVal, maxVal);
    }
    return null;
  }

  (double, double)? _parseDoubleBetween(String valStr) {
    final normalized = valStr.replaceAll(RegExp(r'\bto\b', caseSensitive: false), ' ').replaceAll('..', ' ');
    final parts = normalized
        .split(RegExp(r'[,;\s-]+'))
        .map((e) => double.tryParse(e.trim()))
        .whereType<double>()
        .toList();
    if (parts.length >= 2) {
      final minVal = parts[0] <= parts[1] ? parts[0] : parts[1];
      final maxVal = parts[0] <= parts[1] ? parts[1] : parts[0];
      return (minVal, maxVal);
    }
    return null;
  }

  @override
  Future<List<SongsTableData>> evaluateCriteria(SmartCriteria criteria) async {
    final dartRules = criteria.rules
        .where((r) => _isDartRule(r.field))
        .toList();
    if (dartRules.isEmpty) {
      var list = await _buildQuery(criteria).get();
      return _postProcess(list, criteria, const []);
    }
    if (criteria.matchAll) {
      final base = await _buildQuery(criteria).get();
      return _postProcess(base, criteria, dartRules);
    }
    // matchAny: union of SQL matches and prefs-backed matches.
    final sqlRules = criteria.rules
        .where((r) => !_isDartRule(r.field))
        .toList();
    final base = sqlRules.isEmpty
        ? <SongsTableData>[]
        : await _buildQuery(_withoutDartRules(criteria)).get();
    final all = await _buildQuery(_allLocal(criteria)).get();
    final baseIds = base.map((s) => s.id).toSet();
    final merged = List<SongsTableData>.from(base)
      ..addAll(all.where((s) => !baseIds.contains(s.id)));
    return _postProcessAny(merged, baseIds, criteria, dartRules);
  }

  @override
  Stream<List<SongsTableData>> watchCriteria(SmartCriteria criteria) {
    final dartRules = criteria.rules
        .where((r) => _isDartRule(r.field))
        .toList();
    if (dartRules.isEmpty) {
      final stream =
          _buildQuery(criteria).watch().debounceTime(const Duration(milliseconds: 500));
      if (criteria.sortBy == 'rating') {
        return stream.map((list) => _postProcess(list, criteria, const []));
      }
      return stream;
    }
    if (criteria.matchAll) {
      return _buildQuery(criteria)
          .watch()
          .debounceTime(const Duration(milliseconds: 500))
          .map((list) => _postProcess(list, criteria, dartRules));
    }
    final sqlRules = criteria.rules
        .where((r) => !_isDartRule(r.field))
        .toList();
    final baseStream = sqlRules.isEmpty
        ? Stream.value(<SongsTableData>[])
        : _buildQuery(_withoutDartRules(criteria)).watch();
    return Rx.combineLatest2(
      baseStream,
      _buildQuery(_allLocal(criteria)).watch(),
      (List<SongsTableData> base, List<SongsTableData> all) {
        final baseIds = base.map((s) => s.id).toSet();
        final merged = List<SongsTableData>.from(base)
          ..addAll(all.where((s) => !baseIds.contains(s.id)));
        return (merged, baseIds);
      },
    )
        .debounceTime(const Duration(milliseconds: 500))
        .map((parts) =>
            _postProcessAny(parts.$1, parts.$2, criteria, dartRules));
  }

  /// [criteria] with prefs-backed rules removed (SQL shape only).
  SmartCriteria _withoutDartRules(SmartCriteria criteria) => SmartCriteria(
        rules: criteria.rules
            .where((r) => !_isDartRule(r.field))
            .toList(),
        matchAll: criteria.matchAll,
        sortAscending: criteria.sortAscending,
      );

  /// Bare local-songs shape used to resolve prefs-backed matches under matchAny.
  SmartCriteria _allLocal(SmartCriteria criteria) =>
      SmartCriteria(matchAll: criteria.matchAll);

  /// matchAll post-step: AND-filter by every prefs-backed rule, then rating
  /// sort and limit.
  List<SongsTableData> _postProcess(
    List<SongsTableData> songs,
    SmartCriteria criteria,
    List<SmartRule> dartRules,
  ) {
    var list = songs;
    if (dartRules.isNotEmpty) {
      list = list
          .where((s) => dartRules.every((r) => _matchesDartRule(s, r)))
          .toList();
    }
    if (criteria.sortBy == 'rating') {
      list = _sortByRating(list, ascending: criteria.sortAscending);
    }
    if (criteria.limit != null && criteria.limit! > 0) {
      list = list.take(criteria.limit!).toList();
    }
    return list;
  }

  /// matchAny post-step over the union of SQL and full-table candidates:
  /// a song is kept when the SQL half already matched it (tracked via
  /// [baseIds]) or when it matches any prefs-backed rule.
  List<SongsTableData> _postProcessAny(
    List<SongsTableData> merged,
    Set<int> baseIds,
    SmartCriteria criteria,
    List<SmartRule> dartRules,
  ) {
    var list = merged
        .where((s) =>
            baseIds.contains(s.id) ||
            dartRules.any((r) => _matchesDartRule(s, r)))
        .toList();
    if (criteria.sortBy == 'rating') {
      list = _sortByRating(list, ascending: criteria.sortAscending);
    }
    if (criteria.limit != null && criteria.limit! > 0) {
      list = list.take(criteria.limit!).toList();
    }
    return list;
  }

  /// Star rating (0–5, prefs-backed) for [song].
  int _ratingOf(SongsTableData song) {
    try {
      if (getIt.isRegistered<SongRatingStore>()) {
        return getIt<SongRatingStore>().getRating(song.id.toString());
      }
    } catch (_) {}
    return 0;
  }

  /// Evaluates one rating rule (numeric operators + between) in Dart.
  bool _matchesRating(SongsTableData song, SmartRule rule) {
    final rating = _ratingOf(song);
    final valStr = rule.value.trim();
    if (rule.operator == SmartOperator.between) {
      final b = _parseIntBetween(valStr);
      if (b == null) return false;
      return rating >= b.$1 && rating <= b.$2;
    }
    final valInt = int.tryParse(valStr);
    if (valInt == null) return false;
    switch (rule.operator) {
      case SmartOperator.equals:
        return rating == valInt;
      case SmartOperator.greaterThan:
        return rating > valInt;
      case SmartOperator.lessThan:
        return rating < valInt;
      case SmartOperator.greaterThanOrEqual:
        return rating >= valInt;
      case SmartOperator.lessThanOrEqual:
        return rating <= valInt;
      default:
        return rating == valInt;
    }
  }

  /// Dispatches a prefs-backed rule to its concrete evaluator.
  bool _matchesDartRule(SongsTableData song, SmartRule rule) =>
      switch (rule.field) {
        SmartRuleField.rating => _matchesRating(song, rule),
        SmartRuleField.bpm => _matchesBpm(song, rule),
        _ => false,
      };

  /// Manual BPM override (40–240, prefs-backed) for [song], or null.
  double? _bpmOf(SongsTableData song) {
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        return getIt<PulsrAudioHandler>()
            .bpmOverrideStore
            .getBpmForTrack(PulsrAudioHandler.trackKeyFor(song));
      }
    } catch (_) {}
    return null;
  }

  /// Evaluates one BPM rule (numeric operators + between) in Dart.
  bool _matchesBpm(SongsTableData song, SmartRule rule) {
    final bpm = _bpmOf(song);
    if (bpm == null) return false;
    final valStr = rule.value.trim();
    if (rule.operator == SmartOperator.between) {
      final b = _parseDoubleBetween(valStr);
      if (b == null) return false;
      return bpm >= b.$1 && bpm <= b.$2;
    }
    final valDouble = double.tryParse(valStr);
    if (valDouble == null) return false;
    switch (rule.operator) {
      case SmartOperator.equals:
        return (bpm - valDouble).abs() < 0.5;
      case SmartOperator.greaterThan:
        return bpm > valDouble;
      case SmartOperator.lessThan:
        return bpm < valDouble;
      case SmartOperator.greaterThanOrEqual:
        return bpm >= valDouble;
      case SmartOperator.lessThanOrEqual:
        return bpm <= valDouble;
      default:
        return (bpm - valDouble).abs() < 0.5;
    }
  }

  /// Sorts by rating (title tiebreak for stability).
  List<SongsTableData> _sortByRating(List<SongsTableData> songs,
      {bool ascending = false}) {
    final sorted = List<SongsTableData>.from(songs);
    sorted.sort((a, b) {
      final cmp = _ratingOf(a).compareTo(_ratingOf(b));
      if (cmp != 0) return ascending ? cmp : -cmp;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return sorted;
  }

  @override
  Future<List<SongsTableData>> createPlaybackSnapshot(
      SmartCriteria criteria) async {
    final songs = await evaluateCriteria(criteria);
    return List<SongsTableData>.unmodifiable(songs);
  }
}
