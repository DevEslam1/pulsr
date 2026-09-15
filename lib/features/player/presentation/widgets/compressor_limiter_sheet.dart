// lib/features/player/presentation/widgets/compressor_limiter_sheet.dart
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../data/audio/equalizer_manager.dart';

class CompressorLimiterSheet extends StatefulWidget {
  final EqualizerManager equalizerManager;

  const CompressorLimiterSheet({super.key, required this.equalizerManager});

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

  /// Ratio / attack / make-up are honored only by the Android HAL
  /// DynamicsProcessing limiter; the native C++ stage is a brickwall limiter.
  late final bool _advancedSupported;

  @override
  void initState() {
    super.initState();
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
    _advancedSupported =
        widget.equalizerManager.isCompressorAdvancedParamsSupported;
  }

  Future<void> _applyMbc() async {
    await widget.equalizerManager.setMultibandCompressor(
      _mbcEnabled,
      f0: _mbcF0,
      f1: _mbcF1,
      f2: _mbcF2,
    );
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

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, color: p.primary),
                    const SizedBox(width: 10),
                    Text(context.l10n.studioCompressor,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
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
            const SizedBox(height: 8),
            Text(context.l10n.studioCompressorDesc,
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            if (!_advancedSupported) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.hairline),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: p.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(context.l10n.compressorLimitDesc,
                        style: TextStyle(
                            color: p.textTertiary,
                            fontSize: 11,
                            height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

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

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.textPrimary,
                  side: BorderSide(color: p.primary.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
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
            const SizedBox(height: 28),
            Divider(color: p.hairline),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, color: p.primary),
                    const SizedBox(width: 10),
                    Text(context.l10n.compressorTitle,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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
            const SizedBox(height: 4),
            Text(context.l10n.compressorDesc,
              style: TextStyle(color: p.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
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
          ],
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: enabled ? p.textPrimary : p.textTertiary,
                  fontSize: 14,
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (defaultValue != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.settings_backup_restore,
                          size: 16,
                          color: isDefault || !enabled
                              ? p.textSecondary.withValues(alpha: 0.35)
                              : p.primary),
                      tooltip: context.l10n.dspResetToDefault,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
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
