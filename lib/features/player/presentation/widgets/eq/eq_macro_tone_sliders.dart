part of '../equalizer_sheet.dart';

/// Three macro tone sliders (Bass, Mid, Treble) for Normal Mode Quick Sound Studio.
extension _EqMacroToneSliders on _EqualizerSheetState {
  Widget _buildMacroSliders(
    BuildContext context,
    PlayerCubit cubit,
    PulsrPalette p, {
    double spacing = AppSpacing.s10,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.eqQuickToneDials,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w800,
            letterSpacing: AppTracking.wide,
            color: p.textTertiary,
          ),
        ),
        SizedBox(height: spacing),
        BlocSelector<PlayerCubit, PlayerState, double>(
          selector: _getBassGain,
          builder: (context, val) => _buildMacroSliderRow(
            context: context,
            icon: Icons.speaker_rounded,
            title: context.l10n.eqMacroBassTitle,
            subtitle: context.l10n.eqMacroBassDesc,
            value: val,
            accentColor: p.accent,
            p: p,
            onChanged: (v) => _setBassMacro(cubit, cubit.state, v),
          ),
        ),
        SizedBox(height: spacing),
        BlocSelector<PlayerCubit, PlayerState, double>(
          selector: _getMidGain,
          builder: (context, val) => _buildMacroSliderRow(
            context: context,
            icon: Icons.mic_rounded,
            title: context.l10n.eqMacroMidTitle,
            subtitle: context.l10n.eqMacroMidDesc,
            value: val,
            accentColor: AppColors.accentCyan,
            p: p,
            onChanged: (v) => _setMidMacro(cubit, cubit.state, v),
          ),
        ),
        SizedBox(height: spacing),
        BlocSelector<PlayerCubit, PlayerState, double>(
          selector: _getTrebleGain,
          builder: (context, val) => _buildMacroSliderRow(
            context: context,
            icon: Icons.auto_awesome_rounded,
            title: context.l10n.eqMacroTrebleTitle,
            subtitle: context.l10n.eqMacroTrebleDesc,
            value: val,
            accentColor: AppColors.warning,
            p: p,
            onChanged: (v) => _setTrebleMacro(cubit, cubit.state, v),
          ),
        ),
      ],
    );
  }

  Widget _buildMacroSliderRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required Color accentColor,
    required PulsrPalette p,
    required ValueChanged<double> onChanged,
  }) {
    final gainText = EqSheetMath.formatGainDb(value);
    final surfacePalette = context.playerSurfacePalette;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.s14, AppSpacing.sm, AppSpacing.s14, AppSpacing.xs),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.s6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: AppRadii.r8All,
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppFontSize.bodySmall,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: AppFontSize.caption, color: p.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: AppRadii.r8All,
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  gainText,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Builder(
            builder: (context) {
              final val = value.clamp(-12.0, 12.0);
              final nextVal = (val + 0.5).clamp(-12.0, 12.0);
              final prevVal = (val - 0.5).clamp(-12.0, 12.0);
              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: accentColor,
                  thumbColor: surfacePalette.highContrastInk,
                  overlayColor: accentColor.withValues(alpha: 0.18),
                  trackHeight: 4,
                ),
                child: Semantics(
                  slider: true,
                  excludeSemantics: true,
                  label: title,
                  value: gainText,
                  increasedValue: EqSheetMath.formatGainDb(nextVal),
                  decreasedValue: EqSheetMath.formatGainDb(prevVal),
                  onIncrease: () => onChanged(nextVal),
                  onDecrease: () => onChanged(prevVal),
                  child: Slider(
                    value: val,
                    min: -12.0,
                    max: 12.0,
                    divisions: 48,
                    onChanged: (v) {
                      final step = EqSheetMath.hapticStepFor(v);
                      if (step != _lastMacroHapticStep) {
                        _lastMacroHapticStep = step;
                        PulsrHaptics.selectionClick();
                      }
                      onChanged(v);
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
