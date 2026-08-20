// lib/data/repositories/smart_playlist_engine.dart
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import '../../domain/models/smart_playlist_criteria.dart';
import '../db/app_database.dart';

@singleton
class SmartPlaylistEngine {
  final AppDatabase _db;

  SmartPlaylistEngine(this._db);

  SimpleSelectStatement<$SongsTableTable, SongsTableData> _buildQuery(SmartCriteria criteria) {
    final query = _db.select(_db.songsTable);

    if (criteria.rules.isNotEmpty) {
      query.where((t) {
        Expression<bool>? combined;
        for (final rule in criteria.rules) {
          final expr = _buildRuleExpression(t, rule);
          if (expr == null) continue;
          if (combined == null) {
            combined = expr;
          } else {
            combined = criteria.matchAll ? (combined & expr) : (combined | expr);
          }
        }
        return combined ?? const Constant(true);
      });
    }

    if (criteria.sortBy != null) {
      final mode = criteria.sortAscending ? OrderingMode.asc : OrderingMode.desc;
      switch (criteria.sortBy) {
        case 'dateAdded':
          query.orderBy([(t) => OrderingTerm(expression: t.dateAdded, mode: mode)]);
          break;
        case 'playCount':
          query.orderBy([(t) => OrderingTerm(expression: t.playCount, mode: mode)]);
          break;
        case 'lastPlayed':
          query.orderBy([(t) => OrderingTerm(expression: t.lastPlayed, mode: mode)]);
          break;
        case 'durationMs':
          query.orderBy([(t) => OrderingTerm(expression: t.durationMs, mode: mode)]);
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

      case SmartRuleField.genre:
        if (valStr.isEmpty) return null;
        final escaped = valStr.replaceAll('\\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_').toLowerCase();
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.genre.lower().equals(valStr.toLowerCase());
          case SmartOperator.contains:
          default:
            return t.genre.lower().like('%$escaped%');
        }

      case SmartRuleField.year:
        if (valInt == null) return null;
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.year.equals(valInt);
          case SmartOperator.greaterThan:
            return t.year.isBiggerThanValue(valInt);
          case SmartOperator.lessThan:
            return t.year.isSmallerThanValue(valInt);
          case SmartOperator.greaterThanOrEqual:
            return t.year.isBiggerOrEqualValue(valInt);
          case SmartOperator.lessThanOrEqual:
            return t.year.isSmallerOrEqualValue(valInt);
          default:
            return t.year.equals(valInt);
        }

      case SmartRuleField.dateAdded:
        if (rule.operator == SmartOperator.withinDays) {
          final days = valInt ?? 30;
          final cutoffMs = DateTime.now().millisecondsSinceEpoch - (days * 86400 * 1000);
          return t.dateAdded.isBiggerOrEqualValue(cutoffMs);
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
          final cutoffMs = DateTime.now().millisecondsSinceEpoch - (days * 86400 * 1000);
          return t.lastPlayed.isBiggerOrEqualValue(cutoffMs);
        }
        if (valInt == null) return null;
        switch (rule.operator) {
          case SmartOperator.equals:
            return t.lastPlayed.equals(valInt);
          case SmartOperator.greaterThan:
            return t.lastPlayed.isBiggerThanValue(valInt);
          case SmartOperator.lessThan:
            return t.lastPlayed.isSmallerThanValue(valInt);
          case SmartOperator.greaterThanOrEqual:
            return t.lastPlayed.isBiggerOrEqualValue(valInt);
          case SmartOperator.lessThanOrEqual:
            return t.lastPlayed.isSmallerOrEqualValue(valInt);
          default:
            return t.lastPlayed.isBiggerOrEqualValue(valInt);
        }
    }
  }

  Future<List<SongsTableData>> evaluateCriteria(SmartCriteria criteria) async {
    final query = _buildQuery(criteria);
    return await query.get();
  }

  Stream<List<SongsTableData>> watchCriteria(SmartCriteria criteria) {
    final query = _buildQuery(criteria);
    return query.watch();
  }
}
