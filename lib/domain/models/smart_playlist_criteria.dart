import 'dart:convert';
import '../../core/utils/error_logger.dart';

enum SmartRuleField {
  playCount('playCount', 'Play Count'),
  genre('genre', 'Genre'),
  year('year', 'Year'),
  dateAdded('dateAdded', 'Date Added'),
  durationMs('durationMs', 'Duration'),
  isFavorite('isFavorite', 'Is Favorite'),
  lastPlayed('lastPlayed', 'Last Played');

  final String key;
  final String label;
  const SmartRuleField(this.key, this.label);

  static SmartRuleField fromKey(String key) {
    return SmartRuleField.values.firstWhere(
      (e) => e.key == key,
      orElse: () => SmartRuleField.playCount,
    );
  }
}

enum SmartOperator {
  equals('equals', '='),
  greaterThan('>', '>'),
  lessThan('<', '<'),
  greaterThanOrEqual('>=', '>='),
  lessThanOrEqual('<=', '<='),
  contains('contains', 'Contains'),
  withinDays('within_days', 'Within Days');

  final String key;
  final String label;
  const SmartOperator(this.key, this.label);

  static SmartOperator fromKey(String key) {
    return SmartOperator.values.firstWhere(
      (e) => e.key == key,
      orElse: () => SmartOperator.equals,
    );
  }
}

class SmartRule {
  final SmartRuleField field;
  final SmartOperator operator;
  final String value;

  const SmartRule({
    required this.field,
    required this.operator,
    required this.value,
  });

  Map<String, dynamic> toJson() {
    return {
      'field': field.key,
      'operator': operator.key,
      'value': value,
    };
  }

  factory SmartRule.fromJson(Map<String, dynamic> json) {
    return SmartRule(
      field: SmartRuleField.fromKey(json['field'] as String? ?? 'playCount'),
      operator: SmartOperator.fromKey(json['operator'] as String? ?? 'equals'),
      value: json['value']?.toString() ?? '',
    );
  }

  SmartRule copyWith({
    SmartRuleField? field,
    SmartOperator? operator,
    String? value,
  }) {
    return SmartRule(
      field: field ?? this.field,
      operator: operator ?? this.operator,
      value: value ?? this.value,
    );
  }
}

class SmartCriteria {
  final List<SmartRule> rules;
  final bool matchAll;
  final int? limit;
  final String? sortBy;
  final bool sortAscending;

  const SmartCriteria({
    this.rules = const [],
    this.matchAll = true,
    this.limit,
    this.sortBy,
    this.sortAscending = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'rules': rules.map((r) => r.toJson()).toList(),
      'matchAll': matchAll,
      'limit': limit,
      'sortBy': sortBy,
      'sortAscending': sortAscending,
    };
  }

  factory SmartCriteria.fromJson(Map<String, dynamic> json) {
    final rulesRaw = json['rules'] as List<dynamic>? ?? [];
    return SmartCriteria(
      rules: rulesRaw.map((r) => SmartRule.fromJson(r as Map<String, dynamic>)).toList(),
      matchAll: json['matchAll'] as bool? ?? true,
      limit: json['limit'] as int?,
      sortBy: json['sortBy'] as String?,
      sortAscending: json['sortAscending'] as bool? ?? false,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory SmartCriteria.fromJsonString(String source) {
    if (source.trim().isEmpty) return const SmartCriteria();
    try {
      return SmartCriteria.fromJson(jsonDecode(source) as Map<String, dynamic>);
    } catch (e, st) {
      ErrorLogger.log('Failed to parse SmartCriteria from JSON string', error: e, stackTrace: st, category: 'SmartCriteria');
      return const SmartCriteria();
    }
  }

  SmartCriteria copyWith({
    List<SmartRule>? rules,
    bool? matchAll,
    int? limit,
    String? sortBy,
    bool? sortAscending,
  }) {
    return SmartCriteria(
      rules: rules ?? this.rules,
      matchAll: matchAll ?? this.matchAll,
      limit: limit ?? this.limit,
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}
