// lib/features/player/presentation/widgets/sync_diagnostics_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../data/audio/audio_effects_channel.dart';
import '../../../../domain/services/usb_exclusive_service.dart';

class SyncDiagnosticsSheet extends StatefulWidget {
  final double sampleRate;

  const SyncDiagnosticsSheet({
    super.key,
    this.sampleRate = 48000.0,
  });

  static Future<void> show(BuildContext context, {double sampleRate = 48000.0}) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => SyncDiagnosticsSheet(sampleRate: sampleRate),
    );
  }

  @override
  State<SyncDiagnosticsSheet> createState() => _SyncDiagnosticsSheetState();
}

class _SyncDiagnosticsSheetState extends State<SyncDiagnosticsSheet> {
  int _pipelineLatencyFrames = 0;
  double _appliedSampleRate = 48000.0;
  double _usbBufferedMs = 0.0;
  Map<String, dynamic> _usbDiagnostics = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _appliedSampleRate = widget.sampleRate > 0 ? widget.sampleRate : 48000.0;
    _fetchDiagnostics();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _fetchDiagnostics();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDiagnostics() async {
    final frames = await AudioEffectsChannel().getPipelineLatencyFrames();
    final appliedRate = await AudioEffectsChannel().getAppliedSampleRate();
    final usbService = UsbExclusiveService();
    final usbMs = await usbService.getBufferedMs();
    final usbDiag = await usbService.getDiagnostics();

    if (mounted) {
      setState(() {
        _pipelineLatencyFrames = frames;
        _appliedSampleRate = appliedRate > 0 ? appliedRate : widget.sampleRate;
        _usbBufferedMs = usbMs;
        _usbDiagnostics = usbDiag;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sr = _appliedSampleRate > 0 ? _appliedSampleRate : (widget.sampleRate > 0 ? widget.sampleRate : 48000.0);
    final dspMs = (_pipelineLatencyFrames / sr) * 1000.0;
    final isUsbStreaming = _usbDiagnostics['isStreamActive'] == true;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Adaptive.sheetConstraints(context).maxWidth,
        ),
        child: Material(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.s20,
                AppSpacing.sm,
                AppSpacing.s20,
                AppSpacing.s28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: p.hairline,
                        borderRadius: BorderRadius.circular(AppRadii.r2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.sync_rounded, color: p.accent, size: 22),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        "Latency & Sync Diagnostics",
                        style: TextStyle(
                          fontSize: AppFontSize.bodyLarge,
                          fontWeight: FontWeight.bold,
                          color: p.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "Real-time output and processing delay metrics reported directly from native hardware sinks.",
                    style: TextStyle(
                      fontSize: AppFontSize.bodySmall,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildMetricTile(
                    p: p,
                    icon: Icons.tune_rounded,
                    title: 'DSP Pipeline Delay',
                    subtitle: 'Lookahead Limiter + Resampler group delay + Reverb partitioned delay',
                    value: '${dspMs.toStringAsFixed(2)} ms',
                    detail: '$_pipelineLatencyFrames frames @ ${(sr / 1000.0).toStringAsFixed(1)} kHz',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (isUsbStreaming) ...[
                    _buildMetricTile(
                      p: p,
                      icon: Icons.usb_rounded,
                      title: 'USB Hardware Buffered Delay',
                      subtitle: 'Ring buffer occupancy + URB kernel queue slack',
                      value: '${_usbBufferedMs.toStringAsFixed(1)} ms',
                      detail: 'Underruns: ${_usbDiagnostics['underrunCount'] ?? 0} | Overruns: ${_usbDiagnostics['overrunCount'] ?? 0}',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  _buildMetricTile(
                    p: p,
                    icon: Icons.speed_rounded,
                    title: 'Total Monitored Latency',
                    subtitle: 'Sum of active digital processing & hardware buffering',
                    value: '${(dspMs + (isUsbStreaming ? _usbBufferedMs : 0.0)).toStringAsFixed(2)} ms',
                    detail: isUsbStreaming ? 'Direct USB Exclusive Path' : 'Low-Latency Direct Output',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required PulsrPalette p,
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required String detail,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadii.r16),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: p.accentContainer,
              borderRadius: BorderRadius.circular(AppRadii.r8),
            ),
            child: Icon(icon, color: p.accent, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppFontSize.bodySmall,
                    fontWeight: FontWeight.bold,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: p.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: p.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            style: TextStyle(
              fontSize: AppFontSize.bodyLarge,
              fontWeight: FontWeight.bold,
              color: p.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
