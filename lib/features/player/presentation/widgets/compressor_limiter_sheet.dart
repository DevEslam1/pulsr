// lib/features/player/presentation/widgets/compressor_limiter_sheet.dart
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _limiterEnabled = widget.equalizerManager.isLimiterEnabled;
    _thresholdDb = widget.equalizerManager.limiterThresholdDb;
    _ratio = widget.equalizerManager.compressorRatio;
    _attackMs = widget.equalizerManager.compressorAttackMs;
    _releaseMs = widget.equalizerManager.limiterReleaseMs;
    _makeupGainDb = widget.equalizerManager.compressorMakeupGainDb;
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
                    Text(
                      'Studio Dynamics Compressor',
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
                    await widget.equalizerManager.setLookaheadLimiter(val, thresholdDb: _thresholdDb, releaseMs: _releaseMs);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Studio-grade lookahead dynamics processing and peak brickwall limiting.',
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // Threshold Slider
            _buildParamRow(
              title: 'Threshold',
              valueDisplay: '${_thresholdDb.toStringAsFixed(1)} dB',
              value: _thresholdDb,
              min: -30.0,
              max: 0.0,
              onChanged: (val) {
                setState(() => _thresholdDb = val);
                _applyParams();
              },
            ),

            // Ratio Slider
            _buildParamRow(
              title: 'Ratio',
              valueDisplay: '${_ratio.toStringAsFixed(1)}:1',
              value: _ratio,
              min: 1.0,
              max: 20.0,
              onChanged: (val) {
                setState(() => _ratio = val);
                _applyParams();
              },
            ),

            // Attack Slider
            _buildParamRow(
              title: 'Attack Time',
              valueDisplay: '${_attackMs.toStringAsFixed(0)} ms',
              value: _attackMs,
              min: 1.0,
              max: 100.0,
              onChanged: (val) {
                setState(() => _attackMs = val);
                _applyParams();
              },
            ),

            // Release Slider
            _buildParamRow(
              title: 'Release Time',
              valueDisplay: '${_releaseMs.toStringAsFixed(0)} ms',
              value: _releaseMs,
              min: 10.0,
              max: 500.0,
              onChanged: (val) {
                setState(() => _releaseMs = val);
                _applyParams();
              },
            ),

            // Makeup Gain Slider
            _buildParamRow(
              title: 'Makeup Gain',
              valueDisplay: '+${_makeupGainDb.toStringAsFixed(1)} dB',
              value: _makeupGainDb,
              min: 0.0,
              max: 12.0,
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                child: const Text('Reset to Studio Defaults'),
              ),
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
    required ValueChanged<double> onChanged,
  }) {
    final p = context.palette;
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
                  color: p.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                valueDisplay,
                style: TextStyle(
                  color: p.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
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
              onChanged: _limiterEnabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}
