import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import '../../core/utils/error_logger.dart';
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
        bool hasValidRule = false;
        for (final rule in criteria.rules) {
          final expr = _buildRuleExpression(t, rule);
          if (expr == null) continue;
          hasValidRule = true;
          if (combined == null) {
            combined = expr;
          } else {
            combined =
                criteria.matchAll ? (combined & expr) : (combined | expr);
          }
        }
        if (!hasValidRule) return const Constant(false);
        return combined ?? const Constant(true);
      });
    }

    if (criteria.sortBy != null) {
      final mode =
          criteria.sortAscending ? OrderingMode.asc : OrderingMode.desc;
      switch (criteria.sortBy) {
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

    if (criteria.limit != null && criteria.limit! > 0) {
      query.limit(criteria.limit!);
    }

    return query;
  }

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
        return t.codec.isIn(
                const ['FLAC', 'ALAC', 'WAV', 'AIFF', 'PCM', 'DSF', 'DFF']) |
            (t.bitDepth.isNotNull() & t.bitDepth.isBiggerOrEqualValue(24)) |
            t.path.lower().like('%.flac') |
            t.path.lower().like('%.wav') |
            t.path.lower().like('%.alac') |
            t.path.lower().like('%.aiff') |
            t.path.lower().like('%.dsf') |
            t.path.lower().like('%.dff');

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
        ErrorLogger.log('BPM smart rule ignored — BPM column not indexed, rule will be skipped until enrichment', category: 'SmartPlaylist');
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
    final query = _buildQuery(criteria);
    return await query.get();
  }

  @override
  Stream<List<SongsTableData>> watchCriteria(SmartCriteria criteria) {
    final query = _buildQuery(criteria);
    return query.watch().debounceTime(const Duration(milliseconds: 500));
  }

  @override
  Future<List<SongsTableData>> createPlaybackSnapshot(
      SmartCriteria criteria) async {
    final songs = await evaluateCriteria(criteria);
    return List<SongsTableData>.unmodifiable(songs);
  }
}
