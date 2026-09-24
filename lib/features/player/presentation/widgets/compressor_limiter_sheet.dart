// lib/features/player/presentation/widgets/compressor_limiter_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../data/audio/equalizer_manager.dart';
import '../../../../domain/models/audio_effects_config.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class CompressorLimiterSheet extends StatefulWidget {
  final EqualizerManager equalizerManager;

  const CompressorLimiterSheet({super.key, required this.equalizerManager});

  static Future<void> show(BuildContext context, {required EqualizerManager equalizerManager}) {
    final cubit = context.read<PlayerCubit>();
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: CompressorLimiterSheet(equalizerManager: equalizerManager),
      ),
    );
  }

  @override
  State<CompressorLimiterSheet> createState() => _CompressorLimiterSheetState();
}

class _CompressorLimiterSheetState extends State<CompressorLimiterSheet> {
  late bool _limiterEnabled;
  late double _thresholdDb;
  late double _ratio;
  late double _attackMs;
  late double _releaseMs;
  late double _makeupGainDb;

  // Native 4-band multiband compressor (C++ stage).
  late bool _mbcEnabled;
  late double _mbcF0;
  late double _mbcF1;
  late double _mbcF2;
  late List<MultibandCompressorBandConfig> _mbcBands;

  /// Ratio / attack / make-up are honored only by the Android HAL
  /// DynamicsProcessing limiter; the native C++ stage is a brickwall limiter.
  late final bool _advancedSupported;

  @override
  void initState() {
    super.initState();
    _syncFromManager();
    _advancedSupported =
        widget.equalizerManager.isCompressorAdvancedParamsSupported;
  }

  @override
  void didUpdateWidget(covariant CompressorLimiterSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.equalizerManager != widget.equalizerManager) {
      _syncFromManager();
    }
  }

  void _syncFromManager() {
    _limiterEnabled = widget.equalizerManager.isLimiterEnabled;
    _thresholdDb = widget.equalizerManager.limiterThresholdDb;
    _ratio = widget.equalizerManager.compressorRatio;
    _attackMs = widget.equalizerManager.compressorAttackMs;
    _releaseMs = widget.equalizerManager.limiterReleaseMs;
    _makeupGainDb = widget.equalizerManager.compressorMakeupGainDb;
    _mbcEnabled = widget.equalizerManager.isMultibandCompressorEnabled;
    _mbcF0 = widget.equalizerManager.multibandCompressorF0;
    _mbcF1 = widget.equalizerManager.multibandCompressorF1;
    _mbcF2 = widget.equalizerManager.multibandCompressorF2;
    _mbcBands = List.of(widget.equalizerManager.multibandCompressorBands);
  }

  Future<void> _applyMbc() async {
    if (!widget.equalizerManager.isCompressorAdvancedParamsSupported) {
      if (mounted) {
        PulsrToast.show(
          context,
          message: context.l10n.compressorLimitDesc,
        );
      }
      return;
    }
    await widget.equalizerManager.setMultibandCompressor(
      _mbcEnabled,
      f0: _mbcF0,
      f1: _mbcF1,
      f2: _mbcF2,
    );
  }

  Future<void> _applyMbcBand(
      int index, MultibandCompressorBandConfig band) async {
    setState(() => _mbcBands[index] = band);
    await widget.equalizerManager.setMultibandCompressorBand(index, band);
  }

  void _applyParams() {
    widget.equalizerManager.setCompressorParams(
      thresholdDb: _thresholdDb,
      ratio: _ratio,
      attackMs: _attackMs,
      releaseMs: _releaseMs,
      makeupGainDb: _makeupGainDb,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocListener<PlayerCubit, PlayerState>(
      listenWhen: (prev, curr) =>
          prev.dynamicsPreset != curr.dynamicsPreset ||
          prev.isLimiterEnabled != curr.isLimiterEnabled ||
          prev.limiterThresholdDb != curr.limiterThresholdDb ||
          prev.limiterReleaseMs != curr.limiterReleaseMs ||
          prev.eqPreset != curr.eqPreset,
      listener: (context, state) {
        if (mounted) {
          setState(() => _syncFromManager());
        }
      },
      child: Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.xl),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppRadii.r2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, color: p.primary),
                    const SizedBox(width: AppSpacing.s10),
                    Text(context.l10n.studioCompressor,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: AppFontSize.title,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Switch.adaptive(
                  value: _limiterEnabled,
                  activeThumbColor: p.primary,
                  onChanged: (val) async {
                    setState(() => _limiterEnabled = val);
                    await widget.equalizerManager.setLookaheadLimiter(val,
                        thresholdDb: _thresholdDb, releaseMs: _releaseMs);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(context.l10n.studioCompressorDesc,
              style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
            ),
            if (!_advancedSupported) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.all(AppSpacing.s10),
                decoration: BoxDecoration(
                  color: p.surfaceCard,
                  borderRadius: BorderRadius.circular(AppRadii.r10),
                  border: Border.all(color: p.hairline),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: p.textTertiary),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(context.l10n.compressorLimitDesc,
                        style: TextStyle(
                            color: p.textTertiary,
                            fontSize: AppFontSize.caption,
                            height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),

            // Threshold Slider
            _buildParamRow(
              title: context.l10n.dspThreshold,
              valueDisplay: '${_thresholdDb.toStringAsFixed(1)} dB',
              value: _thresholdDb,
              min: -30.0,
              max: 0.0,
              defaultValue: -0.2,
              enabled: _limiterEnabled,
              onChanged: (val) {
                setState(() => _thresholdDb = val);
                _applyParams();
              },
            ),

            // Ratio Slider (HAL DynamicsProcessing only)
            _buildParamRow(
              title: context.l10n.dspRatio,
              valueDisplay: '${_ratio.toStringAsFixed(1)}:1',
              value: _ratio,
              min: 1.0,
              max: 20.0,
              defaultValue: 3.0,
              enabled: _limiterEnabled && _advancedSupported,
              onChanged: (val) {
                setState(() => _ratio = val);
                _applyParams();
              },
            ),

            // Attack Slider (HAL DynamicsProcessing only)
            _buildParamRow(
              title: context.l10n.dspAttackTime,
              valueDisplay: '${_attackMs.toStringAsFixed(0)} ms',
              value: _attackMs,
              min: 1.0,
              max: 100.0,
              defaultValue: 15.0,
              enabled: _limiterEnabled && _advancedSupported,
              onChanged: (val) {
                setState(() => _attackMs = val);
                _applyParams();
              },
            ),

            // Release Slider
            _buildParamRow(
              title: context.l10n.releaseTime,
              valueDisplay: '${_releaseMs.toStringAsFixed(0)} ms',
              value: _releaseMs,
              min: 10.0,
              max: 500.0,
              defaultValue: 50.0,
              enabled: _limiterEnabled,
              onChanged: (val) {
                setState(() => _releaseMs = val);
                _applyParams();
              },
            ),

            // Makeup Gain Slider (HAL DynamicsProcessing only)
            _buildParamRow(
              title: context.l10n.dspMakeupGain,
              valueDisplay: '+${_makeupGainDb.toStringAsFixed(1)} dB',
              value: _makeupGainDb,
              min: 0.0,
              max: 12.0,
              defaultValue: 0.0,
              enabled: _limiterEnabled && _advancedSupported,
              onChanged: (val) {
                setState(() => _makeupGainDb = val);
                _applyParams();
              },
            ),

            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.textPrimary,
                  side: BorderSide(color: p.primary.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r14)),
                ),
                onPressed: () {
                  setState(() {
                    _thresholdDb = -0.2;
                    _ratio = 3.0;
                    _attackMs = 15.0;
                    _releaseMs = 50.0;
                    _makeupGainDb = 0.0;
                  });
                  _applyParams();
                },
                child: Text(context.l10n.resetStudioDefaults),
              ),
            ),
            const SizedBox(height: AppSpacing.s28),
            Divider(color: p.hairline),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, color: p.primary),
                    const SizedBox(width: AppSpacing.s10),
                    Text(context.l10n.compressorTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: AppFontSize.bodyLarge,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Switch.adaptive(
                  value: _mbcEnabled,
                  activeThumbColor: p.primary,
                  onChanged: (val) async {
                    setState(() => _mbcEnabled = val);
                    await _applyMbc();
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(context.l10n.compressorDesc,
              style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildParamRow(
              title: context.l10n.dspCrossoverLow,
              valueDisplay: '${_mbcF0.toStringAsFixed(0)} Hz',
              value: _mbcF0,
              min: 40.0,
              max: 500.0,
              defaultValue: 160.0,
              enabled: _mbcEnabled,
              onChanged: (val) {
                setState(() => _mbcF0 = val);
                _applyMbc();
              },
            ),
            _buildParamRow(
              title: context.l10n.dspCrossoverMid,
              valueDisplay: '${_mbcF1.toStringAsFixed(0)} Hz',
              value: _mbcF1,
              min: 200.0,
              max: 4000.0,
              defaultValue: 1000.0,
              enabled: _mbcEnabled,
              onChanged: (val) {
                setState(() => _mbcF1 = val);
                _applyMbc();
              },
            ),
            _buildParamRow(
              title: context.l10n.dspCrossoverHigh,
              valueDisplay: '${_mbcF2.toStringAsFixed(0)} Hz',
              value: _mbcF2,
              min: 1000.0,
              max: 16000.0,
              defaultValue: 5000.0,
              enabled: _mbcEnabled,
              onChanged: (val) {
                setState(() => _mbcF2 = val);
                _applyMbc();
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.l10n.mbcPerBandTitle,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: AppFontSize.body,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              context.l10n.mbcPerBandSubtitle,
              style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
            ),
            const SizedBox(height: AppSpacing.xs),
            ...List.generate(_mbcBands.length, (i) {
              final bandNames = [
                context.l10n.mbcBandLow,
                context.l10n.mbcBandLowMid,
                context.l10n.mbcBandHighMid,
                context.l10n.mbcBandHigh,
              ];
              final band = _mbcBands[i];
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppRadii.r14),
                  border: Border.all(color: p.hairline),
                ),
                child: ExpansionTile(
                  dense: true,
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.s2),
                  childrenPadding:
                      const EdgeInsetsDirectional.fromSTEB(AppSpacing.s14, 0, AppSpacing.s14, AppSpacing.sm),
                  title: Text(
                    i < bandNames.length ? bandNames[i] : 'Band ${i + 1}',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: AppFontSize.bodySmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${band.thresholdDb.toStringAsFixed(1)} dB · ${band.ratio.toStringAsFixed(1)}:1 · +${band.makeupGainDb.toStringAsFixed(1)} dB',
                    style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                        fontFamily: 'monospace'),
                  ),
                  children: [
                    _buildParamRow(
                      title: context.l10n.dspThreshold,
                      valueDisplay:
                          '${band.thresholdDb.toStringAsFixed(1)} dB',
                      value: band.thresholdDb,
                      min: -60.0,
                      max: 0.0,
                      enabled: _mbcEnabled,
                      onChanged: (val) => _applyMbcBand(
                          i, band.copyWith(thresholdDb: val)),
                    ),
                    _buildParamRow(
                      title: context.l10n.dspRatio,
                      valueDisplay: '${band.ratio.toStringAsFixed(1)}:1',
                      value: band.ratio,
                      min: 1.0,
                      max: 20.0,
                      enabled: _mbcEnabled,
                      onChanged: (val) =>
                          _applyMbcBand(i, band.copyWith(ratio: val)),
                    ),
                    _buildParamRow(
                      title: context.l10n.dspMakeupGain,
                      valueDisplay:
                          '+${band.makeupGainDb.toStringAsFixed(1)} dB',
                      value: band.makeupGainDb,
                      min: 0.0,
                      max: 24.0,
                      enabled: _mbcEnabled,
                      onChanged: (val) => _applyMbcBand(
                          i, band.copyWith(makeupGainDb: val)),
                    ),
                    _buildParamRow(
                      title: context.l10n.dspAttackTime,
                      valueDisplay:
                          '${band.attackMs.toStringAsFixed(1)} ms',
                      value: band.attackMs,
                      min: 0.1,
                      max: 200.0,
                      enabled: _mbcEnabled,
                      onChanged: (val) => _applyMbcBand(
                          i, band.copyWith(attackMs: val)),
                    ),
                    _buildParamRow(
                      title: context.l10n.releaseTime,
                      valueDisplay:
                          '${band.releaseMs.toStringAsFixed(0)} ms',
                      value: band.releaseMs,
                      min: 5.0,
                      max: 1000.0,
                      enabled: _mbcEnabled,
                      onChanged: (val) => _applyMbcBand(
                          i, band.copyWith(releaseMs: val)),
                    ),
                    _buildParamRow(
                      title: context.l10n.dspKnee,
                      valueDisplay:
                          '${band.kneeDb.toStringAsFixed(1)} dB',
                      value: band.kneeDb,
                      min: 0.0,
                      max: 12.0,
                      enabled: _mbcEnabled,
                      onChanged: (val) =>
                          _applyMbcBand(i, band.copyWith(kneeDb: val)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildParamRow({
    required String title,
    required String valueDisplay,
    required double value,
    required double min,
    required double max,
    double? defaultValue,
    bool enabled = true,
    required ValueChanged<double> onChanged,
  }) {
    final p = context.palette;
    final isDefault =
        defaultValue != null && (value - defaultValue).abs() < 0.001;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: enabled ? p.textPrimary : p.textTertiary,
                  fontSize: AppFontSize.body,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    valueDisplay,
                    style: TextStyle(
                      color: enabled ? p.primary : p.textTertiary,
                      fontSize: AppFontSize.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (defaultValue != null) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    IconButton(
                      icon: Icon(Icons.settings_backup_restore,
                          size: 16,
                          color: isDefault || !enabled
                              ? p.textSecondary.withValues(alpha: 0.35)
                              : p.primary),
                      tooltip: context.l10n.dspResetToDefault,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
                      onPressed:
                          isDefault || !enabled ? null : () => onChanged(defaultValue),
                    ),
                  ],
                ],
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: p.primary,
              inactiveTrackColor: p.surfaceCard,
              thumbColor: p.primary,
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}
