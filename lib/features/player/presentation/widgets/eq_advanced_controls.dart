part of 'equalizer_sheet.dart';

/// Shared DSP slider row, crossfeed audition helper, and [ConversionQualityCard].
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

/// Conversion-quality control for the tap-side sample-rate converter.
///
/// The choice is a preference rather than [SettingsState]: it mirrors a native
/// kernel size, so it is read on mount and written straight back to prefs.
/// 64/128/256/512 taps select the tap kernel; 256 is the default. Conversion
/// only runs when the sink rate differs from the track rate, so a bit-perfect
/// path is never altered.
class ConversionQualityCard extends StatefulWidget {
  /// Non-null when bit-perfect playback currently bypasses the DSP chain.
  final String? blockedReason;

  /// False when no native PCM effect chain is loaded on this platform.
  final bool nativeAvailable;

  const ConversionQualityCard({
    super.key,
    this.blockedReason,
    this.nativeAvailable = true,
  });

  @override
  State<ConversionQualityCard> createState() => _ConversionQualityCardState();
}

class _ConversionQualityCardState extends State<ConversionQualityCard> {
  static const int _defaultQuality = 2; // 256 taps, the documented baseline.
  static const TextStyle _labelStyle = TextStyle(
    fontSize: AppFontSize.caption,
    fontWeight: FontWeight.w700,
  );

  int _segment = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final stored = (prefs.getInt(PrefsKeys.tapSrcQuality) ?? _defaultQuality)
        .clamp(0, 3);
    setState(() {
      _segment = stored;
      _loaded = true;
    });
    if (widget.blockedReason == null && widget.nativeAvailable) {
      try {
        await AudioEffectsChannel().setTapSrcQuality(stored);
      } catch (_) {
        // Off Android (or without the DSP bridge) there is nothing to apply.
      }
    }
  }

  Future<void> _select(int quality) async {
    if (quality == _segment) return;
    PulsrHaptics.selectionClick();
    final previous = _segment;
    setState(() => _segment = quality);
    try {
      final applied = await AudioEffectsChannel().setTapSrcQuality(quality);
      if (!applied) throw StateError('tap SRC refused');
    } catch (_) {
      if (mounted) setState(() => _segment = previous);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await prefs.setInt(PrefsKeys.tapSrcQuality, quality);
  }

  static String _tapLabel(BuildContext context, int quality) {
    switch (quality.clamp(0, 3)) {
      case 0:
        return context.l10n.conversionTaps64;
      case 1:
        return context.l10n.conversionTaps128;
      case 2:
        return context.l10n.conversionTaps256;
      default:
        return context.l10n.conversionTaps512;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled =
        widget.blockedReason == null && widget.nativeAvailable && _loaded;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  borderRadius: AppRadii.r8All,
                ),
                child: Icon(Icons.sync_alt_rounded, color: p.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.conversionQuality,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.body,
                          color: p.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      context.l10n.conversionQualityDesc,
                      style: TextStyle(
                          fontSize: AppFontSize.caption, color: p.textTertiary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                ),
              ),
              segments: [
                for (var i = 0; i < 4; i++)
                  ButtonSegment(
                    value: i,
                    label: Text(_tapLabel(context, i), style: _labelStyle),
                  ),
              ],
              selected: {_segment},
              onSelectionChanged: enabled
                  ? (values) {
                      if (values.isNotEmpty) _select(values.first);
                    }
                  : null,
            ),
          ),
          if (widget.blockedReason != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(context.l10n.blockedByBitPerfectShort,
                  style: TextStyle(
                      color: p.error,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600)),
            )
          else if (!widget.nativeAvailable)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s6),
              child: Text(context.l10n.nativeDspUnavailable,
                  style: TextStyle(
                      color: p.textTertiary,
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
