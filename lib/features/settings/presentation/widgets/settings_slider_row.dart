// lib/features/settings/presentation/widgets/settings_slider_row.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';

/// A labeled settings slider with a trailing "restore default" affordance.
///
/// Shows the current value, an info icon (optional) and a compact reset
/// IconButton that calls [onChanged] with [defaultValue]. The reset button is
/// greyed out (disabled) while the current value already equals the default.
class SettingSliderRow extends StatelessWidget {
  final String label;
  final String? subtitle;

  /// Optional handler that renders the Ⓘ info icon next to the label.
  final VoidCallback? onInfo;

  final double value;
  final double min;
  final double max;
  final int? divisions;

  /// The value restored by the reset button (must match the cubit/state
  /// constructor default for this setting).
  final double defaultValue;

  final ValueChanged<double> onChanged;

  /// Formats both the current-value display and the reset tooltip
  /// (e.g. `(v) => '${v.toStringAsFixed(1)}s'`).
  final String Function(double value)? formatValue;

  final bool enabled;

  const SettingSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.onChanged,
    this.subtitle,
    this.onInfo,
    this.divisions,
    this.formatValue,
    this.enabled = true,
  });

  String _fmt(double v) =>
      formatValue != null ? formatValue!(v) : v.toStringAsFixed(1);

  bool get _isDefault => (value - defaultValue).abs() < 0.001;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onInfo != null) ...[
                IconButton(
                  icon: Icon(Icons.info_outline_rounded,
                      size: 16, color: p.textTertiary),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: onInfo,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: enabled ? p.textPrimary : p.textTertiary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
              Text(
                _fmt(value),
                style: TextStyle(
                    color: enabled ? p.accent : p.textTertiary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12),
              ),
              const SizedBox(width: 2),
              IconButton(
                icon: Icon(Icons.settings_backup_restore,
                    size: 18,
                    color: _isDefault || !enabled
                        ? p.textTertiary.withValues(alpha: 0.5)
                        : p.accent),
                tooltip: 'Reset to default (${_fmt(defaultValue)})',
                visualDensity: VisualDensity.compact,
                onPressed:
                    _isDefault || !enabled ? null : () => onChanged(defaultValue),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(subtitle!,
                  style: TextStyle(
                      color: p.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ],
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
