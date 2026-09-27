// lib/features/library/presentation/widgets/smart_playlist_rule_builder.dart
import 'package:flutter/material.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/db/app_database.dart';

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
}

enum SmartRuleMatchMode {
  all('Match All Rules (AND)'),
  any('Match Any Rule (OR)');

  final String label;
  const SmartRuleMatchMode(this.label);
}

class SmartRule {
  SmartRuleField field;
  SmartRuleOperator operator;
  String value;

  SmartRule({
    this.field = SmartRuleField.artist,
    this.operator = SmartRuleOperator.contains,
    this.value = '',
  });

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
            DropdownButton<SmartRuleMatchMode>(
              value: _matchMode,
              underline: const SizedBox.shrink(),
              items: SmartRuleMatchMode.values.map((mode) {
                return DropdownMenuItem(
                  value: mode,
                  child: Text(
                    mode.label,
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
            if (widget.previewSongs != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                ),
                child: Text(
                  '$_matchingCount matches',
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // Rules List
        ...List.generate(_rules.length, (index) {
          final rule = _rules[index];
          return Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadii.r16),
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
                        initialValue: rule.field,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r10),
                          ),
                        ),
                        items: SmartRuleField.values.map((f) {
                          return DropdownMenuItem(
                              value: f, child: Text(f.label));
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
                        initialValue: rule.operator,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r10),
                          ),
                        ),
                        items: SmartRuleOperator.values.map((op) {
                          return DropdownMenuItem(
                              value: op, child: Text(op.label));
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
                  initialValue: rule.value,
                  decoration: InputDecoration(
                    hintText: 'Enter search value...',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r10),
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
              borderRadius: BorderRadius.circular(AppRadii.r12),
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
