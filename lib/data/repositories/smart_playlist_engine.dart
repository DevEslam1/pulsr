import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import '../../core/di/injection.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/search_algorithm_utils.dart';
import '../audio/audio_handler.dart';
import '../audio/bpm_override_store.dart';
import '../audio/song_rating_store.dart';
import '../../domain/models/smart_playlist_criteria.dart';
import '../../domain/repositories/smart_playlist_engine_interface.dart';
import '../db/app_database.dart';

@Singleton(as: ISmartPlaylistEngine)
class SmartPlaylistEngine implements ISmartPlaylistEngine {
  final AppDatabase _db;
  final SongRatingStore? _injectedRatingStore;
  final PulsrAudioHandler? _injectedAudioHandler;
  final BpmOverrideStore? _injectedBpmOverrideStore;

  SmartPlaylistEngine(
    this._db, {
    @ignoreParam SongRatingStore? ratingStore,
    @ignoreParam PulsrAudioHandler? audioHandler,
    @ignoreParam BpmOverrideStore? bpmOverrideStore,
  })  : _injectedRatingStore = ratingStore,
        _injectedAudioHandler = audioHandler,
        _injectedBpmOverrideStore = bpmOverrideStore;

  @override
  List<SmartRule> validateRules(SmartCriteria criteria) {
    final invalid = <SmartRule>[];
    for (final rule in criteria.rules) {
      final valStr = rule.value.trim();
      if (_isDartRule(rule.field)) {
        if (rule.field == SmartRuleField.rating) {
          if (rule.operator == SmartOperator.between) {
            final b = _parseIntBetween(valStr);
            if (b == null || b.$1 < 0 || b.$2 > 5) invalid.add(rule);
          } else {
            final r = int.tryParse(valStr);
            if (r == null || r < 0 || r > 5) invalid.add(rule);
          }
        } else if (rule.field == SmartRuleField.bpm) {
          if (rule.operator == SmartOperator.between) {
            final b = _parseDoubleBetween(valStr);
            if (b == null || b.$1 <= 0) invalid.add(rule);
          } else {
            final b = double.tryParse(valStr);
            if (b == null || b <= 0) invalid.add(rule);
          }
        }
        continue;
      }
      switch (rule.field) {
        case SmartRuleField.playCount:
        case SmartRuleField.decade:
        case SmartRuleField.year:
        case SmartRuleField.durationMs:
        case SmartRuleField.bitrate:
          if (rule.operator == SmartOperator.between) {
            if (_parseIntBetween(valStr) == null) invalid.add(rule);
          } else if (int.tryParse(valStr) == null) {
            invalid.add(rule);
          }
          break;
        case SmartRuleField.dateAdded:
        case SmartRuleField.lastPlayed:
          if (rule.operator == SmartOperator.withinDays) {
            if (valStr.isNotEmpty && int.tryParse(valStr) == null) {
              invalid.add(rule);
            }
          } else if (rule.operator == SmartOperator.between) {
            if (_parseIntBetween(valStr) == null) invalid.add(rule);
          } else if (int.tryParse(valStr) == null) {
            invalid.add(rule);
          }
          break;
        case SmartRuleField.loudnessRange:
          if (rule.operator == SmartOperator.between) {
            if (_parseDoubleBetween(valStr) == null) invalid.add(rule);
          } else if (double.tryParse(valStr) == null) {
            invalid.add(rule);
          }
          break;
        case SmartRuleField.artist:
        case SmartRuleField.album:
        case SmartRuleField.title:
        case SmartRuleField.genre:
          if (valStr.isEmpty) invalid.add(rule);
          break;
        case SmartRuleField.isLossless:
        case SmartRuleField.isFavorite:
          break;
        default:
          break;
      }
    }
    return invalid;
  }

  SimpleSelectStatement<$SongsTableTable, SongsTableData> _buildQuery(
    SmartCriteria criteria, {
    Set<int>? allowedIds,
    bool applyLimit = true,
  }) {
    final query = _db.select(_db.songsTable)
      ..where((t) =>
          t.isMissing.equals(false) &
          t.source.equals(SongSource.local) &
          t.path.like('ytmusic://%').not() &
          (t.cueFile.isNull() | t.cueStartMs.isNotNull()));

    if (allowedIds != null) {
      if (allowedIds.isEmpty) {
        query.where((_) => const Constant(false));
      } else {
        query.where((t) => t.id.isIn(allowedIds));
      }
    }

    if (criteria.rules.isNotEmpty) {
      query.where((t) {
        Expression<bool>? combined;
        var ignoredRule = false;
        for (final rule in criteria.rules) {
          // Rating/BPM and Unicode text rules live outside Drift's SQL
          // capabilities: skipped here and applied as Dart post-filters below.
          if (_isDartPostRule(rule)) continue;
          final expr = _buildRuleExpression(t, rule);
          if (expr == null) {
            ignoredRule = true;
            ErrorLogger.log(
              'Smart playlist: ignoring unsupported rule '
              '${rule.field.name} ${rule.operator.name} "${rule.value}"',
              category: 'SmartPlaylist',
            );
            // Fail closed: a rule that cannot be built must never widen the
            // result to the whole library under AND.
            if (criteria.matchAll) return const Constant(false);
            continue;
          }
          if (combined == null) {
            combined = expr;
          } else {
            combined =
                criteria.matchAll ? (combined & expr) : (combined | expr);
          }
        }
        if (combined == null) {
          // matchAny where every rule was unbuildable matches nothing; with
          // only Dart-backed rules the Dart post-step still filters.
          return ignoredRule ? const Constant(false) : const Constant(true);
        }
        return combined;
      });
    }

    if (criteria.sortBy != null) {
      final mode =
          criteria.sortAscending ? OrderingMode.asc : OrderingMode.desc;
      // 'rating' and 'bpm' are prefs-backed: SQL keeps a stable base order
      // and the Dart post-step re-sorts. Unknown keys fall back to title.
      switch (criteria.sortBy) {
        case 'artist':
          query.orderBy([
            (t) => OrderingTerm(
                expression: t.artist.collate(Collate.noCase), mode: mode),
            (t) => OrderingTerm(
                expression: t.title.collate(Collate.noCase), mode: mode),
            (t) => OrderingTerm.asc(t.id),
          ]);
          break;
        case 'album':
          query.orderBy([
            (t) => OrderingTerm(
                expression: t.album.collate(Collate.noCase), mode: mode),
            (t) =>
                OrderingTerm(expression: t.discNumber, mode: OrderingMode.asc),
            (t) =>
                OrderingTerm(expression: t.trackNumber, mode: OrderingMode.asc),
            (t) => OrderingTerm(
                expression: t.title.collate(Collate.noCase), mode: mode),
            (t) => OrderingTerm.asc(t.id),
          ]);
          break;
        case 'rating':
        case 'bpm':
          query.orderBy([
            (t) => OrderingTerm(expression: t.title.collate(Collate.noCase)),
            (t) => OrderingTerm.asc(t.id),
          ]);
          break;
        case 'dateAdded':
          query.orderBy([
            (t) => OrderingTerm(expression: t.dateAdded, mode: mode),
            (t) => OrderingTerm.asc(t.id),
          ]);
          break;
        case 'playCount':
          query.orderBy([
            (t) => OrderingTerm(expression: t.playCount, mode: mode),
            (t) => OrderingTerm.asc(t.id),
          ]);
          break;
        case 'lastPlayed':
          query.orderBy([
            (t) => OrderingTerm(expression: t.lastPlayed, mode: mode),
            (t) => OrderingTerm.asc(t.id),
          ]);
          break;
        case 'durationMs':
          query.orderBy([
            (t) => OrderingTerm(expression: t.durationMs, mode: mode),
            (t) => OrderingTerm.asc(t.id),
          ]);
          break;
        case 'year':
          query.orderBy([
            (t) => OrderingTerm(expression: t.year, mode: mode),
            (t) => OrderingTerm.asc(t.id),
          ]);
          break;
        case 'title':
        default:
          query.orderBy([
            (t) => OrderingTerm(
                expression: t.title.collate(Collate.noCase), mode: mode),
            (t) => OrderingTerm.asc(t.id),
          ]);
          break;
      }
    }

    // When prefs-backed rules or sorts exist, the limit is applied in Dart
    // AFTER filtering/sorting so SQL doesn't drop candidates prematurely.
    final needsDartPost = criteria.rules.any(_isDartPostRule) ||
        criteria.sortBy == 'rating' ||
        criteria.sortBy == 'bpm';
    if (applyLimit &&
        !needsDartPost &&
        criteria.limit != null &&
        criteria.limit! > 0) {
      query.limit(criteria.limit!);
    }

    return query;
  }

  /// Rules whose source of truth is not a Drift column (SharedPreferences):
  /// they are excluded from the SQL shape and applied as Dart post-filters.
  bool _isDartRule(SmartRuleField field) =>
      field == SmartRuleField.rating || field == SmartRuleField.bpm;

  bool _isTextRule(SmartRuleField field) =>
      field == SmartRuleField.artist ||
      field == SmartRuleField.album ||
      field == SmartRuleField.title ||
      field == SmartRuleField.genre;

  bool _isAscii(String value) {
    for (final unit in value.codeUnits) {
      if (unit > 0x7F) return false;
    }
    return true;
  }

  /// Text rules whose value is non-ASCII cannot rely on SQLite's lower(), which
  /// folds ASCII only: they are fetched as candidates and compared with the
  /// app-wide [SearchAlgorithmUtils.normalize]. ASCII-valued rules keep the SQL
  /// fast path.
  bool _needsDartTextRule(SmartRule rule) {
    if (!_isTextRule(rule.field)) return false;
    if (rule.operator != SmartOperator.equals &&
        rule.operator != SmartOperator.contains &&
        rule.operator != SmartOperator.notContains &&
        rule.operator != SmartOperator.startsWith) {
      return false;
    }
    return !_isAscii(rule.value);
  }

  bool _isDartPostRule(SmartRule rule) =>
      _isDartRule(rule.field) || _needsDartTextRule(rule);

  /// Escapes LIKE metacharacters (%, _, \) so user input matches literally.
  /// Use with `escapeChar: r'\'`.
  static String _likeEscape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

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
        final escaped = _likeEscape(valStr.toLowerCase());
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.artist.lower().equals(valStr.toLowerCase());
          case SmartOperator.notContains:
            return t.artist.lower().like('%$escaped%', escapeChar: r'\').not();
          case SmartOperator.startsWith:
            return t.artist.lower().like('$escaped%', escapeChar: r'\');
          case SmartOperator.contains:
          default:
            return t.artist.lower().like('%$escaped%', escapeChar: r'\');
        }

      case SmartRuleField.album:
        if (valStr.isEmpty) return null;
        final escaped = _likeEscape(valStr.toLowerCase());
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.album.lower().equals(valStr.toLowerCase());
          case SmartOperator.notContains:
            return t.album.lower().like('%$escaped%', escapeChar: r'\').not();
          case SmartOperator.startsWith:
            return t.album.lower().like('$escaped%', escapeChar: r'\');
          case SmartOperator.contains:
          default:
            return t.album.lower().like('%$escaped%', escapeChar: r'\');
        }

      case SmartRuleField.title:
        if (valStr.isEmpty) return null;
        final escaped = _likeEscape(valStr.toLowerCase());
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.title.lower().equals(valStr.toLowerCase());
          case SmartOperator.notContains:
            return t.title.lower().like('%$escaped%', escapeChar: r'\').not();
          case SmartOperator.startsWith:
            return t.title.lower().like('$escaped%', escapeChar: r'\');
          case SmartOperator.contains:
          default:
            return t.title.lower().like('%$escaped%', escapeChar: r'\');
        }

      case SmartRuleField.isLossless:
        // Guard the nullable codec with isNotNull so an un-enriched row yields
        // FALSE (not NULL); otherwise `NOT(lossless)` silently drops it.
        final losslessExpr = (t.codec.isNotNull() &
                t.codec.isIn(const [
                  'FLAC',
                  'ALAC',
                  'WAV',
                  'AIFF',
                  'PCM',
                  'DSF',
                  'DFF'
                ])) |
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
        final escaped = _likeEscape(valStr.toLowerCase());
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.genre.isNotNull() &
                t.genre.lower().equals(valStr.toLowerCase());
          case SmartOperator.notContains:
            return t.genre.isNull() |
                t.genre.lower().like('%$escaped%', escapeChar: r'\').not();
          case SmartOperator.startsWith:
            return t.genre.isNotNull() &
                t.genre.lower().like('$escaped%', escapeChar: r'\');
          case SmartOperator.contains:
          default:
            return t.genre.isNotNull() &
                t.genre.lower().like('%$escaped%', escapeChar: r'\');
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
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final cutoffSec = (nowMs ~/ 1000) - (days * 86400);
          final cutoffMs = nowMs - (days * 86400 * 1000);
          return (t.dateAdded.isSmallerOrEqualValue(10000000000) &
                  t.dateAdded.isBiggerOrEqualValue(cutoffSec)) |
              (t.dateAdded.isBiggerThanValue(10000000000) &
                  t.dateAdded.isBiggerOrEqualValue(cutoffMs));
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
          // last_played is written in milliseconds (recordPlayHistory), unlike
          // date_added which is MediaStore seconds. Comparing it to a seconds
          // cutoff matched every track, so use a millisecond cutoff here.
          final cutoffMs =
              DateTime.now().millisecondsSinceEpoch - (days * 86400 * 1000);
          return t.lastPlayed.isNotNull() &
              t.lastPlayed.isBiggerOrEqualValue(cutoffMs);
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
          case SmartOperator.greaterThanOrEqual:
            return t.loudnessRange.isNotNull() &
                t.loudnessRange.isBiggerOrEqualValue(valDouble);
          case SmartOperator.lessThanOrEqual:
            return t.loudnessRange.isNotNull() &
                t.loudnessRange.isSmallerOrEqualValue(valDouble);
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
          case SmartOperator.greaterThanOrEqual:
            return t.bitrateKbps.isNotNull() &
                t.bitrateKbps.isBiggerOrEqualValue(valInt);
          case SmartOperator.lessThanOrEqual:
            return t.bitrateKbps.isNotNull() &
                t.bitrateKbps.isSmallerOrEqualValue(valInt);
          default:
            return t.bitrateKbps.isNotNull() & t.bitrateKbps.equals(valInt);
        }
    }
  }

  (int, int)? _parseIntBetween(String valStr) {
    // Split only on separators (",", ";", whitespace, "..", "to") so a leading
    // minus survives per operand: "-12, -6" must parse as (-12, -6) rather
    // than losing the signs.
    final normalized = valStr
        .replaceAll(RegExp(r'\bto\b', caseSensitive: false), ' ')
        .replaceAll('..', ' ');
    final parts = normalized
        .split(RegExp(r'[,;\s]+'))
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
    final normalized = valStr
        .replaceAll(RegExp(r'\bto\b', caseSensitive: false), ' ')
        .replaceAll('..', ' ');
    final parts = normalized
        .split(RegExp(r'[,;\s]+'))
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
    final dartRules = criteria.rules.where(_isDartPostRule).toList();
    if (dartRules.isEmpty) {
      final list = await _buildQuery(criteria).get();
      return _postProcess(list, criteria, const []);
    }
    if (criteria.matchAll) {
      final narrowedIds = _narrowIdsForDartRules(dartRules, matchAll: true);
      if (narrowedIds != null && narrowedIds.isEmpty) {
        return const <SongsTableData>[];
      }
      final base = await _querySongsForIds(criteria, narrowedIds);
      return _postProcess(
        base,
        criteria,
        dartRules,
        forceDartSort: narrowedIds != null && narrowedIds.length > 900,
      );
    }
    // matchAny: union of SQL matches and prefs-backed matches.
    final sqlRules = criteria.rules.where((r) => !_isDartPostRule(r)).toList();
    final base = sqlRules.isEmpty
        ? <SongsTableData>[]
        : await _buildQuery(_withoutDartRules(criteria)).get();
    final narrowedIds = _narrowIdsForDartRules(dartRules, matchAll: false);
    final List<SongsTableData> all;
    if (narrowedIds != null && narrowedIds.isEmpty) {
      all = const <SongsTableData>[];
    } else {
      all = await _querySongsForIds(_allLocal(criteria), narrowedIds);
    }
    final baseIds = base.map((s) => s.id).toSet();
    final merged = List<SongsTableData>.from(base)
      ..addAll(all.where((s) => !baseIds.contains(s.id)));
    return _postProcessAny(merged, baseIds, criteria, dartRules);
  }

  static List<Set<int>> _chunkIds(Set<int> ids, {int chunkSize = 900}) {
    final list = ids.toList(growable: false);
    final chunks = <Set<int>>[];
    for (var i = 0; i < list.length; i += chunkSize) {
      final end = i + chunkSize < list.length ? i + chunkSize : list.length;
      chunks.add(list.sublist(i, end).toSet());
    }
    return chunks;
  }

  Future<List<SongsTableData>> _querySongsForIds(
    SmartCriteria criteria,
    Set<int>? narrowedIds,
  ) async {
    if (narrowedIds == null) {
      return _buildQuery(criteria).get();
    }
    if (narrowedIds.isEmpty) return const [];
    if (narrowedIds.length <= 900) {
      return _buildQuery(criteria, allowedIds: narrowedIds).get();
    }
    final seen = <int>{};
    final combined = <SongsTableData>[];
    for (final chunk in _chunkIds(narrowedIds)) {
      final rows =
          await _buildQuery(criteria, allowedIds: chunk, applyLimit: false)
              .get();
      for (final row in rows) {
        if (seen.add(row.id)) combined.add(row);
      }
    }
    return combined;
  }

  Stream<List<SongsTableData>> _watchSongsForIds(
    SmartCriteria criteria,
    Set<int>? narrowedIds,
  ) {
    if (narrowedIds == null) {
      return _buildQuery(criteria).watch();
    }
    if (narrowedIds.isEmpty) return Stream.value(const <SongsTableData>[]);
    if (narrowedIds.length <= 900) {
      return _buildQuery(criteria, allowedIds: narrowedIds).watch();
    }
    final chunks = _chunkIds(narrowedIds);
    return CombineLatestStream.list<List<SongsTableData>>([
      for (final chunk in chunks)
        _buildQuery(criteria, allowedIds: chunk, applyLimit: false).watch(),
    ]).map((chunkLists) {
      final seen = <int>{};
      final combined = <SongsTableData>[];
      for (final chunk in chunkLists) {
        for (final row in chunk) {
          if (seen.add(row.id)) combined.add(row);
        }
      }
      return combined;
    });
  }

  @override
  Stream<List<SongsTableData>> watchCriteria(SmartCriteria criteria) {
    final dartRules = criteria.rules.where(_isDartPostRule).toList();
    final trigger = _buildExternalTrigger(criteria);

    if (dartRules.isEmpty) {
      Stream<List<SongsTableData>> queryStream = _buildQuery(criteria).watch();
      if (trigger != null) {
        queryStream = Rx.combineLatest2(
          queryStream,
          trigger,
          (list, _) => list,
        );
      }
      final stream =
          queryStream.debounceTime(const Duration(milliseconds: 500));
      if (criteria.sortBy == 'rating' || criteria.sortBy == 'bpm') {
        return stream.map((list) => _postProcess(list, criteria, const []));
      }
      return stream;
    }
    if (criteria.matchAll) {
      var multiChunk = false;
      Stream<List<SongsTableData>> buildMatchAllStream() {
        final narrowedIds = _narrowIdsForDartRules(dartRules, matchAll: true);
        multiChunk = narrowedIds != null && narrowedIds.length > 900;
        return _watchSongsForIds(criteria, narrowedIds);
      }

      final Stream<List<SongsTableData>> queryStream = trigger != null
          ? trigger.switchMap((_) => buildMatchAllStream())
          : buildMatchAllStream();
      return queryStream
          .debounceTime(const Duration(milliseconds: 500))
          .map((list) => _postProcess(
                list,
                criteria,
                dartRules,
                forceDartSort: multiChunk,
              ));
    }
    final sqlRules = criteria.rules.where((r) => !_isDartPostRule(r)).toList();
    final baseStream = sqlRules.isEmpty
        ? Stream.value(<SongsTableData>[])
        : _buildQuery(_withoutDartRules(criteria)).watch();
    Stream<List<SongsTableData>> buildAllStream() {
      final narrowedIds = _narrowIdsForDartRules(dartRules, matchAll: false);
      return _watchSongsForIds(_allLocal(criteria), narrowedIds);
    }

    final Stream<List<SongsTableData>> allStream = trigger != null
        ? trigger.switchMap((_) => buildAllStream())
        : buildAllStream();
    final Stream<(List<SongsTableData>, Set<int>)> combinedStream =
        Rx.combineLatest2(
      baseStream,
      allStream,
      (List<SongsTableData> base, List<SongsTableData> all) {
        final baseIds = base.map((s) => s.id).toSet();
        final merged = List<SongsTableData>.from(base)
          ..addAll(all.where((s) => !baseIds.contains(s.id)));
        return (merged, baseIds);
      },
    );

    return combinedStream.debounceTime(const Duration(milliseconds: 500)).map(
        (parts) => _postProcessAny(parts.$1, parts.$2, criteria, dartRules));
  }

  Stream<void>? _buildExternalTrigger(SmartCriteria criteria) {
    final hasRatingRule =
        criteria.rules.any((r) => r.field == SmartRuleField.rating);
    final hasBpmRule = criteria.rules.any((r) => r.field == SmartRuleField.bpm);
    final hasRatingSort = criteria.sortBy == 'rating';
    final hasBpmSort = criteria.sortBy == 'bpm';

    final triggers = <Stream<void>>[];
    if ((hasRatingRule || hasRatingSort) && _ratingStore != null) {
      triggers.add(_ratingStore!.changes);
    }
    if ((hasBpmRule || hasBpmSort) && _bpmOverrideStore != null) {
      triggers.add(_bpmOverrideStore!.changes);
    }
    if (triggers.isEmpty) return null;
    return Rx.merge(triggers).startWith(null);
  }

  /// [criteria] with Dart-backed rules removed (SQL shape only). The sort
  /// survives because matchAny still needs the base half ordered before the
  /// union; the limit does not, because it must apply after the union.
  SmartCriteria _withoutDartRules(SmartCriteria criteria) => SmartCriteria(
        rules: criteria.rules.where((r) => !_isDartPostRule(r)).toList(),
        matchAll: criteria.matchAll,
        sortBy: criteria.sortBy,
        sortAscending: criteria.sortAscending,
      );

  /// Bare local-songs shape used to resolve prefs-backed matches under matchAny.
  SmartCriteria _allLocal(SmartCriteria criteria) =>
      SmartCriteria(matchAll: criteria.matchAll);

  SongRatingStore? get _ratingStore {
    if (_injectedRatingStore != null) return _injectedRatingStore;
    try {
      if (getIt.isRegistered<SongRatingStore>()) {
        return getIt<SongRatingStore>();
      }
    } catch (_) {}
    return null;
  }

  BpmOverrideStore? get _bpmOverrideStore {
    if (_injectedBpmOverrideStore != null) return _injectedBpmOverrideStore;
    try {
      final handler = _audioHandler;
      if (handler != null) return handler.bpmOverrideStore;
      if (getIt.isRegistered<BpmOverrideStore>()) {
        return getIt<BpmOverrideStore>();
      }
    } catch (_) {}
    return null;
  }

  PulsrAudioHandler? get _audioHandler {
    if (_injectedAudioHandler != null) return _injectedAudioHandler;
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        return getIt<PulsrAudioHandler>();
      }
    } catch (_) {}
    return null;
  }

  /// Pre-computes candidate song IDs from [SongRatingStore] when positive
  /// rating rules constrain the result set to rated tracks (where rating 0
  /// cannot match), avoiding a full-table scan of `songs`.
  Set<int>? _narrowIdsForDartRules(
    List<SmartRule> dartRules, {
    required bool matchAll,
  }) {
    final store = _ratingStore;
    if (store == null) return null;
    final snapshot = store.snapshotRatings();

    if (matchAll) {
      Set<int>? intersection;
      for (final rule in dartRules) {
        if (rule.field != SmartRuleField.rating) continue;
        if (_matchesRatingValue(0, rule)) continue;
        final matching = <int>{};
        for (final entry in snapshot.entries) {
          if (_matchesRatingValue(entry.value, rule)) {
            final id = int.tryParse(entry.key);
            if (id != null) matching.add(id);
          }
        }
        if (intersection == null) {
          intersection = matching;
        } else {
          intersection = intersection.intersection(matching);
        }
        if (intersection.isEmpty) return const <int>{};
      }
      return intersection;
    } else {
      if (dartRules.isEmpty) return null;
      for (final rule in dartRules) {
        if (rule.field != SmartRuleField.rating ||
            _matchesRatingValue(0, rule)) {
          return null;
        }
      }
      final union = <int>{};
      for (final entry in snapshot.entries) {
        if (dartRules.any((r) => _matchesRatingValue(entry.value, r))) {
          final id = int.tryParse(entry.key);
          if (id != null) union.add(id);
        }
      }
      return union;
    }
  }

  /// matchAll post-step: AND-filter by every prefs-backed rule, then rating
  /// sort and limit.
  /// matchAll post-step: AND-filter by every prefs-backed rule, then rating
  /// sort and limit.
  List<SongsTableData> _postProcess(
    List<SongsTableData> songs,
    SmartCriteria criteria,
    List<SmartRule> dartRules, {
    bool forceDartSort = false,
  }) {
    var list = songs;
    final ratingStore = _ratingStore;
    final bpmStore = _bpmOverrideStore;
    final ratingSnapshot =
        ratingStore?.snapshotRatings() ?? const <String, int>{};
    final bpmSnapshot = bpmStore?.snapshot() ?? const <String, double>{};

    if (dartRules.isNotEmpty) {
      list = list
          .where((s) => dartRules.every((r) => _matchesDartRule(
                s,
                r,
                ratingSnapshot: ratingSnapshot,
                bpmSnapshot: bpmSnapshot,
              )))
          .toList();
    }
    if (criteria.sortBy == 'rating' ||
        criteria.sortBy == 'bpm' ||
        (forceDartSort && criteria.sortBy != null)) {
      list = _sortSongsWithSnapshot(
        list,
        criteria,
        ratingSnapshot,
        bpmSnapshot: bpmSnapshot,
      );
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
    final ratingStore = _ratingStore;
    final bpmStore = _bpmOverrideStore;
    final ratingSnapshot =
        ratingStore?.snapshotRatings() ?? const <String, int>{};
    final bpmSnapshot = bpmStore?.snapshot() ?? const <String, double>{};

    var list = merged
        .where((s) =>
            baseIds.contains(s.id) ||
            dartRules.any((r) => _matchesDartRule(
                  s,
                  r,
                  ratingSnapshot: ratingSnapshot,
                  bpmSnapshot: bpmSnapshot,
                )))
        .toList();
    // The union appends Dart-side matches after the SQL half, so every sort
    // key needs a final Dart pass: 'rating'/'bpm' because they are prefs-backed,
    // the rest because the SQL order no longer covers the whole union.
    if (criteria.sortBy != null) {
      list = _sortSongsWithSnapshot(
        list,
        criteria,
        ratingSnapshot,
        bpmSnapshot: bpmSnapshot,
      );
    }
    if (criteria.limit != null && criteria.limit! > 0) {
      list = list.take(criteria.limit!).toList();
    }
    return list;
  }

  /// Star rating (0–5, prefs-backed) for [song].
  int _ratingOf(SongsTableData song, [SongRatingStore? store]) {
    try {
      final s = store ?? _ratingStore;
      if (s != null) {
        return s.getRating(song.id.toString());
      }
    } catch (_) {}
    return 0;
  }

  /// Evaluates one rating rule (numeric operators + between) in Dart using a snapshot.
  bool _matchesRating(SongsTableData song, SmartRule rule,
      {Map<String, int>? ratingSnapshot}) {
    final rating = ratingSnapshot != null
        ? (ratingSnapshot[song.id.toString()] ?? 0)
        : _ratingOf(song);
    return _matchesRatingValue(rating, rule);
  }

  bool _matchesRatingValue(int rating, SmartRule rule) {
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

  /// Dispatches a Dart-evaluated rule (prefs-backed or non-ASCII text) to its
  /// concrete evaluator.
  bool _matchesDartRule(
    SongsTableData song,
    SmartRule rule, {
    Map<String, int>? ratingSnapshot,
    Map<String, double>? bpmSnapshot,
  }) =>
      switch (rule.field) {
        SmartRuleField.rating =>
          _matchesRating(song, rule, ratingSnapshot: ratingSnapshot),
        SmartRuleField.bpm => _matchesBpm(song, rule, bpmSnapshot: bpmSnapshot),
        SmartRuleField.artist => _matchesText(song.artist, rule),
        SmartRuleField.album => _matchesText(song.album, rule),
        SmartRuleField.title => _matchesText(song.title, rule),
        SmartRuleField.genre => _matchesText(song.genre ?? '', rule),
        _ => false,
      };

  /// Unicode-aware text match used when SQL lower() cannot fold the value.
  bool _matchesText(String value, SmartRule rule) {
    final target = SearchAlgorithmUtils.normalize(rule.value);
    final haystack = SearchAlgorithmUtils.normalize(value);
    final lowerTarget = rule.value.trim().toLowerCase();
    final lowerHaystack = value.toLowerCase();
    return switch (rule.operator) {
      SmartOperator.equals =>
        haystack == target || lowerHaystack == lowerTarget,
      SmartOperator.notContains =>
        !haystack.contains(target) && !lowerHaystack.contains(lowerTarget),
      SmartOperator.startsWith =>
        haystack.startsWith(target) || lowerHaystack.startsWith(lowerTarget),
      _ => haystack.contains(target) || lowerHaystack.contains(lowerTarget),
    };
  }

  /// Manual BPM override (40–240, prefs-backed) for [song], or null.
  double? _bpmOf(SongsTableData song, [BpmOverrideStore? store]) {
    try {
      final s = store ?? _bpmOverrideStore;
      if (s != null) {
        return s.getBpmForTrack(PulsrAudioHandler.trackKeyFor(song));
      }
    } catch (_) {}
    return null;
  }

  /// Evaluates one BPM rule (numeric operators + between) in Dart.
  bool _matchesBpm(SongsTableData song, SmartRule rule,
      {Map<String, double>? bpmSnapshot}) {
    final bpm = bpmSnapshot != null
        ? bpmSnapshot[PulsrAudioHandler.trackKeyFor(song)]
        : _bpmOf(song);
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

  /// Sorts by rating using snapshot map.
  List<SongsTableData> _sortByRatingSnapshot(
    List<SongsTableData> songs, {
    bool ascending = false,
    Map<String, int> ratingSnapshot = const {},
  }) {
    int ratingFor(SongsTableData s) => ratingSnapshot[s.id.toString()] ?? 0;

    final sorted = List<SongsTableData>.from(songs);
    sorted.sort((a, b) {
      final cmp = ratingFor(a).compareTo(ratingFor(b));
      if (cmp != 0) return ascending ? cmp : -cmp;
      final titleCmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return titleCmp != 0 ? titleCmp : a.id.compareTo(b.id);
    });
    return sorted;
  }

  List<SongsTableData> _sortByBpmSnapshot(
    List<SongsTableData> songs, {
    bool ascending = true,
    Map<String, double> bpmSnapshot = const {},
  }) {
    double? bpmFor(SongsTableData s) =>
        bpmSnapshot[PulsrAudioHandler.trackKeyFor(s)];

    final sorted = List<SongsTableData>.from(songs);
    sorted.sort((a, b) {
      final ba = bpmFor(a);
      final bb = bpmFor(b);
      if (ba == null && bb == null) {
        final titleCmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return titleCmp != 0 ? titleCmp : a.id.compareTo(b.id);
      }
      if (ba == null) return 1;
      if (bb == null) return -1;
      final cmp = ba.compareTo(bb);
      if (cmp != 0) return ascending ? cmp : -cmp;
      final titleCmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return titleCmp != 0 ? titleCmp : a.id.compareTo(b.id);
    });
    return sorted;
  }

  List<SongsTableData> _sortSongsWithSnapshot(
    List<SongsTableData> songs,
    SmartCriteria criteria,
    Map<String, int> ratingSnapshot, {
    Map<String, double> bpmSnapshot = const {},
  }) {
    final sortBy = criteria.sortBy;
    if (sortBy == null) return songs;
    if (sortBy == 'rating') {
      return _sortByRatingSnapshot(
        songs,
        ascending: criteria.sortAscending,
        ratingSnapshot: ratingSnapshot,
      );
    }
    if (sortBy == 'bpm') {
      return _sortByBpmSnapshot(
        songs,
        ascending: criteria.sortAscending,
        bpmSnapshot: bpmSnapshot,
      );
    }
    return _sortSongs(songs, criteria, null, null);
  }

  /// Applies [criteria.sortBy]/[criteria.sortAscending] in Dart, used where
  /// the SQL ordering cannot cover the whole candidate set (matchAny/chunked
  /// unions) or the key is prefs-backed (rating/bpm). Unknown keys fall back to
  /// case-insensitive title.
  List<SongsTableData> _sortSongs(
    List<SongsTableData> songs,
    SmartCriteria criteria,
    SongRatingStore? ratingStore, [
    BpmOverrideStore? bpmStore,
  ]) {
    final sortBy = criteria.sortBy;
    if (sortBy == null) return songs;
    if (sortBy == 'rating') {
      return _sortByRatingSnapshot(
        songs,
        ascending: criteria.sortAscending,
        ratingSnapshot: ratingStore?.snapshotRatings() ?? const {},
      );
    }
    if (sortBy == 'bpm') {
      return _sortByBpmSnapshot(
        songs,
        ascending: criteria.sortAscending,
        bpmSnapshot: bpmStore?.snapshot() ?? const {},
      );
    }
    final ascending = criteria.sortAscending;
    int compare(SongsTableData a, SongsTableData b) => switch (sortBy) {
          'artist' => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
          'album' => () {
              final alb =
                  a.album.toLowerCase().compareTo(b.album.toLowerCase());
              if (alb != 0) return ascending ? alb : -alb;
              final disc = (a.discNumber ?? 0).compareTo(b.discNumber ?? 0);
              if (disc != 0) return disc;
              return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
            }(),
          'dateAdded' => (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0),
          'playCount' => a.playCount.compareTo(b.playCount),
          'lastPlayed' => (a.lastPlayed ?? 0).compareTo(b.lastPlayed ?? 0),
          'durationMs' => a.durationMs.compareTo(b.durationMs),
          'year' => (a.year ?? 0).compareTo(b.year ?? 0),
          _ => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        };
    final sorted = List<SongsTableData>.from(songs);
    sorted.sort((a, b) {
      if (sortBy == 'album') {
        final cmp = compare(a, b);
        if (cmp != 0) return cmp;
      } else {
        final cmp = compare(a, b);
        if (cmp != 0) return ascending ? cmp : -cmp;
      }
      final titleCmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      final orientedTitle = ascending ? titleCmp : -titleCmp;
      return orientedTitle != 0 ? orientedTitle : a.id.compareTo(b.id);
    });
    return sorted;
  }
}
