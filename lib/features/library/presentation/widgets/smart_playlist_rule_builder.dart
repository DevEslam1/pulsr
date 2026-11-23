// lib/features/library/presentation/widgets/smart_playlist_rule_builder.dart
import 'package:material_ui/material_ui.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/smart_playlist_criteria.dart' as domain;
import '../../../../l10n/generated/app_localizations.dart';

enum SmartRuleField {
  title('Title'),
  artist('Artist'),
  album('Album'),
  genre('Genre'),
  year('Year'),
  duration('Duration'),
  isFavorite('Favorite');

  final String label;
  const SmartRuleField(this.label);

  String localizedLabel(AppLocalizations l) => switch (this) {
        SmartRuleField.title => l.title,
        SmartRuleField.artist => l.artist,
        SmartRuleField.album => l.album,
        SmartRuleField.genre => l.genre,
        SmartRuleField.year => l.year,
        SmartRuleField.duration => l.duration,
        SmartRuleField.isFavorite => l.favorite,
      };

  domain.SmartRuleField toDomain() => switch (this) {
        SmartRuleField.title => domain.SmartRuleField.title,
        SmartRuleField.artist => domain.SmartRuleField.artist,
        SmartRuleField.album => domain.SmartRuleField.album,
        SmartRuleField.genre => domain.SmartRuleField.genre,
        SmartRuleField.year => domain.SmartRuleField.year,
        SmartRuleField.duration => domain.SmartRuleField.durationMs,
        SmartRuleField.isFavorite => domain.SmartRuleField.isFavorite,
      };

  static SmartRuleField fromDomain(domain.SmartRuleField field) =>
      switch (field) {
        domain.SmartRuleField.title => SmartRuleField.title,
        domain.SmartRuleField.artist => SmartRuleField.artist,
        domain.SmartRuleField.album => SmartRuleField.album,
        domain.SmartRuleField.genre => SmartRuleField.genre,
        domain.SmartRuleField.year => SmartRuleField.year,
        domain.SmartRuleField.durationMs => SmartRuleField.duration,
        domain.SmartRuleField.isFavorite => SmartRuleField.isFavorite,
        _ => SmartRuleField.artist,
      };
}

enum SmartRuleOperator {
  contains('contains'),
  notContains('does not contain'),
  equals('is exactly'),
  startsWith('starts with'),
  greaterThan('greater than'),
  lessThan('less than');

  final String label;
  const SmartRuleOperator(this.label);

  String localizedLabel(AppLocalizations l) => switch (this) {
        SmartRuleOperator.contains => l.smartRuleOpContains,
        SmartRuleOperator.notContains => l.smartRuleOpNotContains,
        SmartRuleOperator.equals => l.smartRuleOpEquals,
        SmartRuleOperator.startsWith => l.smartRuleOpStartsWith,
        SmartRuleOperator.greaterThan => l.smartRuleOpGreaterThan,
        SmartRuleOperator.lessThan => l.smartRuleOpLessThan,
      };

  domain.SmartOperator toDomain() => switch (this) {
        SmartRuleOperator.contains => domain.SmartOperator.contains,
        SmartRuleOperator.notContains => domain.SmartOperator.notContains,
        SmartRuleOperator.equals => domain.SmartOperator.equals,
        SmartRuleOperator.startsWith => domain.SmartOperator.startsWith,
        SmartRuleOperator.greaterThan => domain.SmartOperator.greaterThan,
        SmartRuleOperator.lessThan => domain.SmartOperator.lessThan,
      };

  static SmartRuleOperator fromDomain(domain.SmartOperator op) => switch (op) {
        domain.SmartOperator.contains => SmartRuleOperator.contains,
        domain.SmartOperator.notContains => SmartRuleOperator.notContains,
        domain.SmartOperator.equals => SmartRuleOperator.equals,
        domain.SmartOperator.startsWith => SmartRuleOperator.startsWith,
        domain.SmartOperator.greaterThan ||
        domain.SmartOperator.greaterThanOrEqual =>
          SmartRuleOperator.greaterThan,
        domain.SmartOperator.lessThan ||
        domain.SmartOperator.lessThanOrEqual =>
          SmartRuleOperator.lessThan,
        _ => SmartRuleOperator.contains,
      };
}

enum SmartRuleMatchMode {
  all('Match All Rules (AND)'),
  any('Match Any Rule (OR)');

  final String label;
  const SmartRuleMatchMode(this.label);

  String localizedLabel(AppLocalizations l) => switch (this) {
        SmartRuleMatchMode.all => l.smartRuleMatchAllAnd,
        SmartRuleMatchMode.any => l.smartRuleMatchAnyOr,
      };
}

class SmartRule {
  final String id;
  SmartRuleField field;
  SmartRuleOperator operator;
  String value;

  SmartRule({
    String? id,
    this.field = SmartRuleField.artist,
    this.operator = SmartRuleOperator.contains,
    this.value = '',
  }) : id = id ?? UniqueKey().toString();

  static String _secondsToMsValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;
    if (trimmed.contains('..')) {
      final parts = trimmed.split('..');
      if (parts.length == 2) {
        final a = num.tryParse(parts[0].trim());
        final b = num.tryParse(parts[1].trim());
        if (a != null && b != null) {
          return '${(a * 1000).round()}..${(b * 1000).round()}';
        }
      }
      return raw;
    }
    if (trimmed.contains(',')) {
      final parts = trimmed.split(',');
      if (parts.length == 2) {
        final a = num.tryParse(parts[0].trim());
        final b = num.tryParse(parts[1].trim());
        if (a != null && b != null) {
          return '${(a * 1000).round()},${(b * 1000).round()}';
        }
      }
      return raw;
    }
    final sec = num.tryParse(trimmed);
    return sec != null ? (sec * 1000).round().toString() : raw;
  }

  static String _msToSecondsValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;
    if (trimmed.contains('..')) {
      final parts = trimmed.split('..');
      if (parts.length == 2) {
        final a = num.tryParse(parts[0].trim());
        final b = num.tryParse(parts[1].trim());
        if (a != null && b != null) {
          return '${(a ~/ 1000)}..${(b ~/ 1000)}';
        }
      }
      return raw;
    }
    if (trimmed.contains(',')) {
      final parts = trimmed.split(',');
      if (parts.length == 2) {
        final a = num.tryParse(parts[0].trim());
        final b = num.tryParse(parts[1].trim());
        if (a != null && b != null) {
          return '${(a ~/ 1000)},${(b ~/ 1000)}';
        }
      }
      return raw;
    }
    final ms = num.tryParse(trimmed);
    return ms != null ? (ms ~/ 1000).toString() : raw;
  }

  domain.SmartRule toDomain() => domain.SmartRule(
        field: field.toDomain(),
        operator: operator.toDomain(),
        value: field == SmartRuleField.duration
            ? _secondsToMsValue(value)
            : value,
      );

  factory SmartRule.fromDomain(domain.SmartRule domainRule, {String? id}) {
    final mappedField = SmartRuleField.fromDomain(domainRule.field);
    return SmartRule(
      id: id,
      field: mappedField,
      operator: SmartRuleOperator.fromDomain(domainRule.operator),
      value: domainRule.field == domain.SmartRuleField.durationMs
          ? _msToSecondsValue(domainRule.value)
          : domainRule.value,
    );
  }

  bool evaluate(SongsTableData song) {
    final targetValue = switch (field) {
      SmartRuleField.title => song.title,
      SmartRuleField.artist => song.artist,
      SmartRuleField.album => song.album,
      SmartRuleField.genre => song.genre ?? '',
      SmartRuleField.year => song.year?.toString() ?? '',
      SmartRuleField.duration => (song.durationMs ~/ 1000).toString(),
      SmartRuleField.isFavorite => song.isFavorite ? 'true' : 'false',
    };

    final query = value.trim().toLowerCase();
    final target = targetValue.toLowerCase();

    return switch (operator) {
      SmartRuleOperator.contains => target.contains(query),
      SmartRuleOperator.notContains => !target.contains(query),
      SmartRuleOperator.equals => target == query,
      SmartRuleOperator.startsWith => target.startsWith(query),
      SmartRuleOperator.greaterThan =>
        (num.tryParse(target) ?? 0) > (num.tryParse(query) ?? 0),
      SmartRuleOperator.lessThan =>
        (num.tryParse(target) ?? 0) < (num.tryParse(query) ?? 0),
    };
  }
}

/// Visual rule builder for dynamic smart playlists.
class SmartPlaylistRuleBuilder extends StatefulWidget {
  final List<SmartRule> initialRules;
  final SmartRuleMatchMode initialMatchMode;
  final ValueChanged<List<SmartRule>> onRulesChanged;
  final ValueChanged<SmartRuleMatchMode>? onMatchModeChanged;
  final List<SongsTableData>? previewSongs;

  const SmartPlaylistRuleBuilder({
    super.key,
    this.initialRules = const [],
    this.initialMatchMode = SmartRuleMatchMode.all,
    required this.onRulesChanged,
    this.onMatchModeChanged,
    this.previewSongs,
  });

  @override
  State<SmartPlaylistRuleBuilder> createState() =>
      _SmartPlaylistRuleBuilderState();
}

class _SmartPlaylistRuleBuilderState extends State<SmartPlaylistRuleBuilder> {
  late List<SmartRule> _rules;
  late SmartRuleMatchMode _matchMode;

  @override
  void initState() {
    super.initState();
    _rules = widget.initialRules.isNotEmpty
        ? List.from(widget.initialRules)
        : [SmartRule()];
    _matchMode = widget.initialMatchMode;
  }

  @override
  void didUpdateWidget(covariant SmartPlaylistRuleBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // BUG-18: adopt externally-provided rules when the parent swaps the list
    // instance (e.g. loading a different playlist) instead of keeping stale
    // local edits. Identity comparison avoids clobbering user edits when the
    // parent rebuilds with the same list instance.
    if (!identical(oldWidget.initialRules, widget.initialRules)) {
      _rules = widget.initialRules.isNotEmpty
          ? List.from(widget.initialRules)
          : [SmartRule()];
    }
    if (oldWidget.initialMatchMode != widget.initialMatchMode) {
      _matchMode = widget.initialMatchMode;
    }
  }

  void _notify() {
    widget.onRulesChanged(List.unmodifiable(_rules));
    widget.onMatchModeChanged?.call(_matchMode);
  }

  int get _matchingCount {
    if (widget.previewSongs == null || _rules.isEmpty) return 0;
    return widget.previewSongs!.where((song) {
      if (_matchMode == SmartRuleMatchMode.all) {
        return _rules.every((rule) => rule.evaluate(song));
      } else {
        return _rules.any((rule) => rule.evaluate(song));
      }
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Match Mode Selector
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: DropdownButton<SmartRuleMatchMode>(
                value: _matchMode,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: SmartRuleMatchMode.values.map((mode) {
                  return DropdownMenuItem(
                    value: mode,
                    child: Text(
                      mode.localizedLabel(context.l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSize.bodySmall,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                  );
                }).toList(growable: false),
                onChanged: (newMode) {
                  if (newMode != null) {
                    setState(() => _matchMode = newMode);
                    _notify();
                  }
                },
              ),
            ),
            if (widget.previewSongs != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.14),
                  borderRadius: AppRadii.r12All,
                ),
                child: Text(
                  context.l10n.smartRuleMatchCount(_matchingCount),
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // Rules List
        ...List.generate(_rules.length, (index) {
          final rule = _rules[index];
          return Container(
            key: ValueKey(rule.id),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: AppRadii.r16All,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // Field dropdown
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<SmartRuleField>(
                        key: ValueKey('${rule.id}_field'),
                        initialValue: rule.field,
                        isExpanded: true,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm),
                          border: OutlineInputBorder(
                            borderRadius: AppRadii.r10All,
                          ),
                        ),
                        items: SmartRuleField.values.map((f) {
                          return DropdownMenuItem(
                            value: f,
                            child: Text(
                              f.localizedLabel(context.l10n),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(growable: false),
                        onChanged: (newField) {
                          if (newField != null) {
                            setState(() => rule.field = newField);
                            _notify();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // Operator dropdown
                    Expanded(
                      flex: 5,
                      child: DropdownButtonFormField<SmartRuleOperator>(
                        key: ValueKey('${rule.id}_op'),
                        initialValue: rule.operator,
                        isExpanded: true,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm),
                          border: OutlineInputBorder(
                            borderRadius: AppRadii.r10All,
                          ),
                        ),
                        items: SmartRuleOperator.values.map((op) {
                          return DropdownMenuItem(
                            value: op,
                            child: Text(
                              op.localizedLabel(context.l10n),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(growable: false),
                        onChanged: (newOp) {
                          if (newOp != null) {
                            setState(() => rule.operator = newOp);
                            _notify();
                          }
                        },
                      ),
                    ),
                    if (_rules.length > 1) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      IconButton(
                        icon: Icon(Icons.remove_circle_outline_rounded,
                            color: p.favorite, size: 20),
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget,
                        ),
                        tooltip: context.l10n.remove,
                        onPressed: () {
                          setState(() => _rules.removeAt(index));
                          _notify();
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // Value text field
                TextFormField(
                  key: ValueKey('${rule.id}_value'),
                  initialValue: rule.value,
                  decoration: InputDecoration(
                    hintText: context.l10n.enterSearchValue,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.r10All,
                    ),
                  ),
                  onChanged: (val) {
                    rule.value = val;
                    _notify();
                  },
                ),
              ],
            ),
          );
        }),

        // Add Rule Button
        OutlinedButton.icon(
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(context.l10n.addRule),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r12All,
            ),
          ),
          onPressed: () {
            setState(() => _rules.add(SmartRule()));
            _notify();
          },
        ),
      ],
    );
  }
}
