import 'dart:async';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/widgets/throttled_slider.dart';
// lib/features/player/presentation/widgets/compressor_limiter_sheet.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../data/audio/equalizer_manager.dart';
import '../../../../domain/models/audio_effects_config.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class CompressorLimiterSheet extends StatefulWidget {
  final EqualizerManager equalizerManager;

  const CompressorLimiterSheet({super.key, required this.equalizerManager});

  static Future<void> show(BuildContext context,
      {required EqualizerManager equalizerManager}) {
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

/// Immutable snapshot of every limiter / compressor parameter the sheet shows.
///
/// [EqualizerManager] owns these values: the record is only ever produced by
/// [_CompressorParams.from] (a full manager re-read) and replaced wholesale by
/// [_CompressorLimiterSheetState._apply], so no field can be edited on its own
/// and a rejected write has exactly one place to be undone.
@immutable
class _CompressorParams {
  const _CompressorParams({
    required this.limiterEnabled,
    required this.thresholdDb,
    required this.ratio,
    required this.attackMs,
    required this.releaseMs,
    required this.makeupGainDb,
    required this.mbcEnabled,
    required this.mbcF0,
    required this.mbcF1,
    required this.mbcF2,
    required this.mbcBands,
  });

  /// Reads every parameter out of [manager] in one shot.
  factory _CompressorParams.from(EqualizerManager manager) => _CompressorParams(
        limiterEnabled: manager.isLimiterEnabled,
        thresholdDb: manager.limiterThresholdDb,
        ratio: manager.compressorRatio,
        attackMs: manager.compressorAttackMs,
        releaseMs: manager.limiterReleaseMs,
        makeupGainDb: manager.compressorMakeupGainDb,
        mbcEnabled: manager.isMultibandCompressorEnabled,
        mbcF0: manager.multibandCompressorF0,
        mbcF1: manager.multibandCompressorF1,
        mbcF2: manager.multibandCompressorF2,
        mbcBands: List<MultibandCompressorBandConfig>.unmodifiable(
            manager.multibandCompressorBands),
      );

  final bool limiterEnabled;
  final double thresholdDb;
  final double ratio;
  final double attackMs;
  final double releaseMs;
  final double makeupGainDb;

  // Native 4-band multiband compressor (C++ stage).
  final bool mbcEnabled;
  final double mbcF0;
  final double mbcF1;
  final double mbcF2;
  final List<MultibandCompressorBandConfig> mbcBands;

  _CompressorParams copyWith({
    bool? limiterEnabled,
    double? thresholdDb,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? makeupGainDb,
    bool? mbcEnabled,
    double? mbcF0,
    double? mbcF1,
    double? mbcF2,
    List<MultibandCompressorBandConfig>? mbcBands,
  }) =>
      _CompressorParams(
        limiterEnabled: limiterEnabled ?? this.limiterEnabled,
        thresholdDb: thresholdDb ?? this.thresholdDb,
        ratio: ratio ?? this.ratio,
        attackMs: attackMs ?? this.attackMs,
        releaseMs: releaseMs ?? this.releaseMs,
        makeupGainDb: makeupGainDb ?? this.makeupGainDb,
        mbcEnabled: mbcEnabled ?? this.mbcEnabled,
        mbcF0: mbcF0 ?? this.mbcF0,
        mbcF1: mbcF1 ?? this.mbcF1,
        mbcF2: mbcF2 ?? this.mbcF2,
        mbcBands: mbcBands ?? this.mbcBands,
      );
}

class _CompressorLimiterSheetState extends State<CompressorLimiterSheet> {
  /// The sheet's only local record of parameters, always a manager snapshot.
  late _CompressorParams _params;

  /// Ratio / attack / make-up are honored only by the Android HAL
  /// DynamicsProcessing limiter; the native C++ stage is a brickwall limiter.
  late final bool _advancedSupported;

  @override
  void initState() {
    super.initState();
    _params = _CompressorParams.from(widget.equalizerManager);
    _advancedSupported =
        widget.equalizerManager.isCompressorAdvancedParamsSupported;
  }

  @override
  void didUpdateWidget(covariant CompressorLimiterSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.equalizerManager != widget.equalizerManager) {
      // A different manager is a different source of truth: drop the snapshot.
      _refreshFromManager();
    }
  }

  /// Replaces the whole record with the manager's current values — the only
  /// reader of limiter/compressor parameter state in this sheet. Never patch a
  /// single field here: that is exactly how the sheet drifted before.
  void _refreshFromManager() {
    if (!mounted) return;
    setState(() => _params = _CompressorParams.from(widget.equalizerManager));
  }

  /// The single write path for every control in this sheet.
  ///
  /// [next] is staged so the control reacts immediately, then sent through
  /// [PlayerCubit] (the guarded write path used by the whole app), and the
  /// manager is re-read unconditionally. A guard block, a rollback, a clamp or
  /// a throw must all end with the manager's value on screen, never the staged
  /// one.
  Future<void> _apply(
    _CompressorParams next, {
    required String failureMessage,
    required Future<void> Function(PlayerCubit cubit) write,
  }) async {
    if (!mounted) return;
    setState(() => _params = next);
    try {
      final cubit = context.read<PlayerCubit?>();
      if (cubit != null) await write(cubit);
    } catch (e, st) {
      ErrorLogger.log(failureMessage,
          error: e, stackTrace: st, category: 'CompressorLimiterSheet');
    }
    _refreshFromManager();
  }

  /// Writes the limiter / compressor knobs through [PlayerCubit] only, so DSP
  /// guards, rollback, and telemetry run once with no direct manager write
  /// (AUDIT-FIX P3-25).
  Future<void> _writeParams(PlayerCubit cubit, _CompressorParams p) async {
    if (_advancedSupported) {
      await cubit.setCompressorParams(
        thresholdDb: p.thresholdDb,
        ratio: p.ratio,
        attackMs: p.attackMs,
        releaseMs: p.releaseMs,
        makeupGainDb: p.makeupGainDb,
      );
    } else {
      await cubit.setLookaheadLimiter(
        p.limiterEnabled,
        thresholdDb: p.thresholdDb,
        releaseMs: p.releaseMs,
      );
    }
  }

  Future<void> _applyParams(
      _CompressorParams Function(_CompressorParams current) update) {
    final next = update(_params);
    return _apply(
      next,
      failureMessage: 'Failed to apply limiter/compressor parameters',
      write: (cubit) => _writeParams(cubit, next),
    );
  }

  Future<void> _setLimiterEnabled(bool val) {
    final next = _params.copyWith(limiterEnabled: val);
    return _apply(
      next,
      failureMessage: 'Failed to toggle lookahead limiter',
      write: (cubit) => cubit.setLookaheadLimiter(
        next.limiterEnabled,
        thresholdDb: next.thresholdDb,
        releaseMs: next.releaseMs,
      ),
    );
  }

  Future<void> _applyMbc(
      _CompressorParams Function(_CompressorParams current) update) {
    final next = update(_params);
    return _apply(
      next,
      failureMessage: 'Failed to apply multiband compressor settings',
      write: (cubit) => cubit.setMultibandCompressor(
        next.mbcEnabled,
        f0: next.mbcF0,
        f1: next.mbcF1,
        f2: next.mbcF2,
      ),
    );
  }

  Future<void> _applyMbcBand(int index, MultibandCompressorBandConfig band) {
    if (index < 0 || index >= _params.mbcBands.length) {
      return Future<void>.value();
    }
    final bands = List<MultibandCompressorBandConfig>.of(_params.mbcBands);
    bands[index] = band;
    final next = _params.copyWith(
      mbcBands: List<MultibandCompressorBandConfig>.unmodifiable(bands),
    );
    return _apply(
      next,
      failureMessage: 'Failed to apply multiband compressor band $index',
      write: (cubit) => cubit.setMultibandCompressorBand(index, band),
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
          prev.isMultibandCompressorEnabled !=
              curr.isMultibandCompressorEnabled ||
          prev.multibandCompressorF0 != curr.multibandCompressorF0 ||
          prev.multibandCompressorF1 != curr.multibandCompressorF1 ||
          prev.multibandCompressorF2 != curr.multibandCompressorF2 ||
          prev.multibandCompressorBands != curr.multibandCompressorBands ||
          prev.eqPreset != curr.eqPreset,
      listener: (context, state) => _refreshFromManager(),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.xl),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
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
                    borderRadius: AppRadii.r2All,
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
                      Text(
                        context.l10n.studioCompressor,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Switch.adaptive(
                    value: _params.limiterEnabled,
                    activeThumbColor: p.primary,
                    onChanged: (val) => unawaited(_setLimiterEnabled(val)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.l10n.studioCompressorDesc,
                style: TextStyle(
                    color: p.textSecondary, fontSize: AppFontSize.bodySmall),
              ),
              if (!_advancedSupported) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s10),
                  decoration: BoxDecoration(
                    color: p.surfaceCard,
                    borderRadius: AppRadii.r10All,
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: p.textTertiary),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          context.l10n.compressorLimitDesc,
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
                valueDisplay: '${_params.thresholdDb.toStringAsFixed(1)} dB',
                value: _params.thresholdDb,
                min: -30.0,
                max: 0.0,
                defaultValue: -0.2,
                enabled: _params.limiterEnabled,
                onChanged: (val) => unawaited(
                    _applyParams((cur) => cur.copyWith(thresholdDb: val))),
              ),

              // Ratio Slider (HAL DynamicsProcessing only)
              _buildParamRow(
                title: context.l10n.dspRatio,
                valueDisplay: '${_params.ratio.toStringAsFixed(1)}:1',
                value: _params.ratio,
                min: 1.0,
                max: 20.0,
                defaultValue: 3.0,
                enabled: _params.limiterEnabled && _advancedSupported,
                onChanged: (val) =>
                    unawaited(_applyParams((cur) => cur.copyWith(ratio: val))),
              ),

              // Attack Slider (HAL DynamicsProcessing only)
              _buildParamRow(
                title: context.l10n.dspAttackTime,
                valueDisplay: '${_params.attackMs.toStringAsFixed(0)} ms',
                value: _params.attackMs,
                min: 1.0,
                max: 100.0,
                defaultValue: 15.0,
                enabled: _params.limiterEnabled && _advancedSupported,
                onChanged: (val) => unawaited(
                    _applyParams((cur) => cur.copyWith(attackMs: val))),
              ),

              // Release Slider
              _buildParamRow(
                title: context.l10n.releaseTime,
                valueDisplay: '${_params.releaseMs.toStringAsFixed(0)} ms',
                value: _params.releaseMs,
                min: 10.0,
                max: 500.0,
                defaultValue: 50.0,
                enabled: _params.limiterEnabled,
                onChanged: (val) => unawaited(
                    _applyParams((cur) => cur.copyWith(releaseMs: val))),
              ),

              // Makeup Gain Slider (HAL DynamicsProcessing only)
              _buildParamRow(
                title: context.l10n.dspMakeupGain,
                valueDisplay: '+${_params.makeupGainDb.toStringAsFixed(1)} dB',
                value: _params.makeupGainDb,
                min: 0.0,
                max: 12.0,
                defaultValue: 0.0,
                enabled: _params.limiterEnabled && _advancedSupported,
                onChanged: (val) => unawaited(
                    _applyParams((cur) => cur.copyWith(makeupGainDb: val))),
              ),

              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.textPrimary,
                    side: BorderSide(color: p.primary.withValues(alpha: 0.4)),
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                    shape:
                        RoundedRectangleBorder(borderRadius: AppRadii.r14All),
                  ),
                  onPressed: () => unawaited(_applyParams((cur) => cur.copyWith(
                        thresholdDb: -0.2,
                        ratio: 3.0,
                        attackMs: 15.0,
                        releaseMs: 50.0,
                        makeupGainDb: 0.0,
                      ))),
                  child: Text(context.l10n.resetStudioDefaults),
                ),
              ),
              const SizedBox(height: AppSpacing.s28),
              Divider(color: p.hairline),
              const SizedBox(height: AppSpacing.sm),
              if (widget
                  .equalizerManager.isCompressorAdvancedParamsSupported) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded, color: p.primary),
                        const SizedBox(width: AppSpacing.s10),
                        Text(
                          context.l10n.compressorTitle,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.bodyLarge,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: _params.mbcEnabled,
                      activeThumbColor: p.primary,
                      onChanged: (val) => unawaited(
                          _applyMbc((cur) => cur.copyWith(mbcEnabled: val))),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  context.l10n.compressorDesc,
                  style: TextStyle(
                      color: p.textSecondary, fontSize: AppFontSize.label),
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildParamRow(
                  title: context.l10n.dspCrossoverLow,
                  valueDisplay: '${_params.mbcF0.toStringAsFixed(0)} Hz',
                  value: _params.mbcF0,
                  min: 40.0,
                  max: 500.0,
                  defaultValue: 160.0,
                  enabled: _params.mbcEnabled,
                  onChanged: (val) =>
                      unawaited(_applyMbc((cur) => cur.copyWith(mbcF0: val))),
                ),
                _buildParamRow(
                  title: context.l10n.dspCrossoverMid,
                  valueDisplay: '${_params.mbcF1.toStringAsFixed(0)} Hz',
                  value: _params.mbcF1,
                  min: 200.0,
                  max: 4000.0,
                  defaultValue: 1000.0,
                  enabled: _params.mbcEnabled,
                  onChanged: (val) =>
                      unawaited(_applyMbc((cur) => cur.copyWith(mbcF1: val))),
                ),
                _buildParamRow(
                  title: context.l10n.dspCrossoverHigh,
                  valueDisplay: '${_params.mbcF2.toStringAsFixed(0)} Hz',
                  value: _params.mbcF2,
                  min: 1000.0,
                  max: 16000.0,
                  defaultValue: 5000.0,
                  enabled: _params.mbcEnabled,
                  onChanged: (val) =>
                      unawaited(_applyMbc((cur) => cur.copyWith(mbcF2: val))),
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
                  style: TextStyle(
                      color: p.textSecondary, fontSize: AppFontSize.label),
                ),
                const SizedBox(height: AppSpacing.xs),
                ...List.generate(_params.mbcBands.length, (i) {
                  final bandNames = [
                    context.l10n.mbcBandLow,
                    context.l10n.mbcBandLowMid,
                    context.l10n.mbcBandHighMid,
                    context.l10n.mbcBandHigh,
                  ];
                  final band = _params.mbcBands[i];
                  return Material(
                    color: p.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.r14All,
                      side: BorderSide(color: p.hairline),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: ExpansionTile(
                        dense: true,
                        tilePadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s14,
                            vertical: AppSpacing.s2),
                        childrenPadding: const EdgeInsetsDirectional.fromSTEB(
                            AppSpacing.s14, 0, AppSpacing.s14, AppSpacing.sm),
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
                            enabled: _params.mbcEnabled,
                            onChanged: (val) => unawaited(_applyMbcBand(
                                i, band.copyWith(thresholdDb: val))),
                          ),
                          _buildParamRow(
                            title: context.l10n.dspRatio,
                            valueDisplay: '${band.ratio.toStringAsFixed(1)}:1',
                            value: band.ratio,
                            min: 1.0,
                            max: 20.0,
                            enabled: _params.mbcEnabled,
                            onChanged: (val) => unawaited(
                                _applyMbcBand(i, band.copyWith(ratio: val))),
                          ),
                          _buildParamRow(
                            title: context.l10n.dspMakeupGain,
                            valueDisplay:
                                '+${band.makeupGainDb.toStringAsFixed(1)} dB',
                            value: band.makeupGainDb,
                            min: 0.0,
                            max: 24.0,
                            enabled: _params.mbcEnabled,
                            onChanged: (val) => unawaited(_applyMbcBand(
                                i, band.copyWith(makeupGainDb: val))),
                          ),
                          _buildParamRow(
                            title: context.l10n.dspAttackTime,
                            valueDisplay:
                                '${band.attackMs.toStringAsFixed(1)} ms',
                            value: band.attackMs,
                            min: 0.1,
                            max: 200.0,
                            enabled: _params.mbcEnabled,
                            onChanged: (val) => unawaited(
                                _applyMbcBand(i, band.copyWith(attackMs: val))),
                          ),
                          _buildParamRow(
                            title: context.l10n.releaseTime,
                            valueDisplay:
                                '${band.releaseMs.toStringAsFixed(0)} ms',
                            value: band.releaseMs,
                            min: 5.0,
                            max: 1000.0,
                            enabled: _params.mbcEnabled,
                            onChanged: (val) => unawaited(_applyMbcBand(
                                i, band.copyWith(releaseMs: val))),
                          ),
                          _buildParamRow(
                            title: context.l10n.dspKnee,
                            valueDisplay:
                                '${band.kneeDb.toStringAsFixed(1)} dB',
                            value: band.kneeDb,
                            min: 0.0,
                            max: 12.0,
                            enabled: _params.mbcEnabled,
                            onChanged: (val) => unawaited(
                                _applyMbcBand(i, band.copyWith(kneeDb: val))),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: p.surfaceCard,
                    borderRadius: AppRadii.r12All,
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 20, color: p.textTertiary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          context.l10n.compressorLimitDesc,
                          style: TextStyle(
                            color: p.textTertiary,
                            fontSize: AppFontSize.caption,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
    final step = (max - min) / 20.0;
    final nextVal = (value + step).clamp(min, max);
    final prevVal = (value - step).clamp(min, max);
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
                      fontFeatures: const [FontFeature.tabularFigures()],
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
                      onPressed: isDefault || !enabled
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
              activeTrackColor: p.primary,
              inactiveTrackColor: p.surfaceCard,
              thumbColor: p.primary,
              trackHeight: 4,
            ),
            child: Semantics(
              slider: true,
              excludeSemantics: true,
              enabled: enabled,
              label: title,
              value: valueDisplay,
              increasedValue: nextVal.toStringAsFixed(1),
              decreasedValue: prevVal.toStringAsFixed(1),
              onIncrease: enabled ? () => onChanged(nextVal) : null,
              onDecrease: enabled ? () => onChanged(prevVal) : null,
              child: ThrottledSlider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
