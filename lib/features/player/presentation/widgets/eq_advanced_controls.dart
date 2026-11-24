part of 'equalizer_sheet.dart';

/// Shared DSP slider row and crossfeed audition helper.
///
/// The full Pro Rack stage views now live in modular files under `eq/`:
/// `eq/eq_autoeq_viper_tab.dart`, `eq/eq_spatial_hrtf_tab.dart`,
/// `eq/eq_spatial_cards.dart`, `eq/eq_dynamics_saturation_tab.dart`,
/// `eq/eq_dynamics_cards.dart`, and `eq/eq_dynamic_eq_card.dart`.
extension _EqAdvancedControls on _EqualizerSheetState {
  void _triggerCrossfeedAudition(
      BuildContext context, PlayerCubit cubit, PlayerState state) {
    _crossfeedPreAuditionEnabled ??= state.isCrossfeedEnabled;
    _crossfeedAuditionTimer?.cancel();
    final targetEnabled = !state.isCrossfeedEnabled;
    cubit.setCrossfeed(targetEnabled);
    PulsrToast.show(
      context,
      message: context.l10n.eqAuditioningCrossfeed,
      icon: Icons.headphones_rounded,
    );
    _crossfeedAuditionTimer = Timer(const Duration(seconds: 5), () {
      final restore = _crossfeedPreAuditionEnabled;
      _crossfeedPreAuditionEnabled = null;
      _crossfeedAuditionTimer = null;
      if (mounted && restore != null) {
        cubit.setCrossfeed(restore);
      }
    });
  }

  /// Shared label/value header + slider row used by DSP stage cards.
  Widget _buildDspSliderRow({
    required BuildContext context,
    required PulsrPalette p,
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    double? defaultValue,
    int? divisions,
    bool enabled = true,
    required ValueChanged<double> onChanged,
  }) {
    final isDefault =
        defaultValue != null && (value - defaultValue).abs() < 0.001;
    final step = (max - min) / (divisions ?? 20);
    final nextVal = (value + step).clamp(min, max);
    final prevVal = (value - step).clamp(min, max);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: AppFontSize.label,
                    color: enabled ? p.textSecondary : p.textTertiary,
                    fontWeight: FontWeight.w600)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(valueText,
                    style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w700,
                        color: enabled ? p.accent : p.textTertiary)),
                if (defaultValue != null) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  IconButton(
                    icon: Icon(Icons.settings_backup_restore,
                        size: 15,
                        color: !enabled || isDefault
                            ? p.textTertiary.withValues(alpha: 0.35)
                            : p.accent),
                    tooltip: context.l10n.dspResetToDefault,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget),
                    onPressed: !enabled || isDefault
                        ? null
                        : () => onChanged(defaultValue),
                  ),
                ],
              ],
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor:
                enabled ? p.accent : p.textTertiary.withValues(alpha: 0.3),
            inactiveTrackColor: p.surface,
            thumbColor: enabled ? p.accent : p.textTertiary,
          ),
          child: Semantics(
            slider: true,
            excludeSemantics: true,
            enabled: enabled,
            label: label,
            value: valueText,
            increasedValue: nextVal.toStringAsFixed(1),
            decreasedValue: prevVal.toStringAsFixed(1),
            onIncrease: enabled ? () => onChanged(nextVal) : null,
            onDecrease: enabled ? () => onChanged(prevVal) : null,
            child: ThrottledSlider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}
