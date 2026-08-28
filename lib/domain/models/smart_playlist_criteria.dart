import 'dart:convert';
import '../../core/utils/error_logger.dart';

enum SmartRuleField {
  playCount('playCount', 'Play Count'),
  artist('artist', 'Artist'),
  album('album', 'Album'),
  title('title', 'Title'),
  genre('genre', 'Genre'),
  year('year', 'Year'),
  decade('decade', 'Decade'),
  isLossless('isLossless', 'Lossless Only'),
  dateAdded('dateAdded', 'Date Added'),
  durationMs('durationMs', 'Duration'),
  isFavorite('isFavorite', 'Is Favorite'),
  lastPlayed('lastPlayed', 'Last Played'),
  bpm('bpm', 'BPM / Tempo'),
  loudnessRange('loudnessRange', 'LRA Dynamic Range'),
  bitrate('bitrate', 'Bitrate (kbps)');

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
  withinDays('within_days', 'Within Days'),
  between('between', 'Between');

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
    this.sortAscending = true,
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
    final rulesList = (json['rules'] as List<dynamic>?)
            ?.map((e) => SmartRule.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return SmartCriteria(
      rules: rulesList,
      matchAll: json['matchAll'] as bool? ?? true,
      limit: json['limit'] as int?,
      sortBy: json['sortBy'] as String?,
      sortAscending: json['sortAscending'] as bool? ?? true,
    );
  }

  factory SmartCriteria.fromJsonString(String jsonString) =>
      tryDecode(jsonString) ?? const SmartCriteria();

  static SmartCriteria? tryDecode(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return null;
    try {
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      return SmartCriteria.fromJson(decoded);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to decode SmartCriteria JSON: $jsonString',
        error: e,
        stackTrace: st,
        category: 'SmartCriteria',
      );
      return null;
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

  String toJsonString() => json.encode(toJson());
  String encode() => json.encode(toJson());

  static const Map<String, SmartCriteria> presetTemplates = {
    'Chill Evening': SmartCriteria(
      rules: [
        SmartRule(
            field: SmartRuleField.genre,
            operator: SmartOperator.contains,
            value: 'chill'),
      ],
      sortBy: 'lastPlayed',
      sortAscending: false,
      limit: 50,
    ),
    'Workout Energy': SmartCriteria(
      rules: [
        SmartRule(
            field: SmartRuleField.genre,
            operator: SmartOperator.contains,
            value: 'electronic'),
      ],
      sortBy: 'playCount',
      sortAscending: false,
      limit: 50,
    ),
    'Lossless Collection': SmartCriteria(
      rules: [
        SmartRule(
            field: SmartRuleField.isLossless,
            operator: SmartOperator.equals,
            value: 'true'),
      ],
      sortBy: 'title',
      sortAscending: true,
    ),
    '90s Gems': SmartCriteria(
      rules: [
        SmartRule(
            field: SmartRuleField.decade,
            operator: SmartOperator.equals,
            value: '1990'),
      ],
      sortBy: 'year',
      sortAscending: true,
      limit: 100,
    ),
    'Recently Added': SmartCriteria(
      rules: [
        SmartRule(
            field: SmartRuleField.dateAdded,
            operator: SmartOperator.withinDays,
            value: '30'),
      ],
      sortBy: 'dateAdded',
      sortAscending: false,
      limit: 50,
    ),
    'Heavy Rotation': SmartCriteria(
      rules: [
        SmartRule(
            field: SmartRuleField.playCount,
            operator: SmartOperator.greaterThanOrEqual,
            value: '10'),
      ],
      sortBy: 'playCount',
      sortAscending: false,
      limit: 50,
    ),
  };
}
