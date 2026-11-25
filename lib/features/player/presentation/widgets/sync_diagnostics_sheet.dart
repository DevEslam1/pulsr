// lib/features/player/presentation/widgets/sync_diagnostics_sheet.dart
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../data/audio/audio_effects_channel.dart';
import '../../../../data/services/usb_exclusive_service.dart';

class SyncDiagnosticsSheet extends StatefulWidget {
  final double sampleRate;

  const SyncDiagnosticsSheet({
    super.key,
    this.sampleRate = 48000.0,
  });

  static Future<void> show(BuildContext context,
      {double sampleRate = 48000.0}) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => SyncDiagnosticsSheet(sampleRate: sampleRate),
    );
  }

  @override
  State<SyncDiagnosticsSheet> createState() => _SyncDiagnosticsSheetState();
}

class _SyncDiagnosticsSheetState extends State<SyncDiagnosticsSheet>
    with WidgetsBindingObserver {
  static const Duration _pollTimeout = Duration(milliseconds: 900);

  int _pipelineLatencyFrames = 0;
  double _appliedSampleRate = 48000.0;
  double _usbBufferedMs = 0.0;
  Map<String, dynamic> _usbDiagnostics = const {};
  Timer? _timer;
  bool _fetchInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appliedSampleRate = widget.sampleRate > 0 ? widget.sampleRate : 48000.0;
    _fetchDiagnostics();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    // M-06 / I-15: Poll every 1s (reduced from 250ms) to save battery
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _fetchDiagnostics();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      _fetchDiagnostics();
    } else {
      _stopTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    super.dispose();
  }

  Future<void> _fetchDiagnostics() async {
    // AUDIT-FIX (P2-18): Serialize slow platform polls with an in-flight
    // guard and per-call timeout so stalled channels cannot stack calls or
    // freeze the 1s poll loop.
    if (_fetchInFlight || !mounted) return;
    _fetchInFlight = true;
    try {
      final effects = AudioEffectsChannel();
      final frames =
          await effects.getPipelineLatencyFrames().timeout(_pollTimeout);
      if (!mounted) return;
      final appliedRate =
          await effects.getAppliedSampleRate().timeout(_pollTimeout);
      if (!mounted) return;
      final usbService = UsbExclusiveService();
      final usbMs = await usbService.getBufferedMs().timeout(_pollTimeout);
      if (!mounted) return;
      final usbDiag = await usbService.getDiagnostics().timeout(_pollTimeout);

      if (mounted) {
        setState(() {
          _pipelineLatencyFrames = frames;
          _appliedSampleRate =
              appliedRate > 0 ? appliedRate : widget.sampleRate;
          _usbBufferedMs = usbMs;
          _usbDiagnostics = usbDiag;
        });
      }
    } catch (e, st) {
      ErrorLogger.log('Sync diagnostics poll failed',
          error: e, stackTrace: st, category: 'SyncDiagnosticsSheet');
    } finally {
      _fetchInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sr = _appliedSampleRate > 0
        ? _appliedSampleRate
        : (widget.sampleRate > 0 ? widget.sampleRate : 48000.0);
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
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
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
                          borderRadius: AppRadii.r2All,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.sync_rounded, color: p.accent, size: 22),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            context.l10n.latencySyncDiagnostics,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppFontSize.bodyLarge,
                              fontWeight: FontWeight.bold,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      context.l10n.latencySyncDiagnosticsDesc,
                      style: TextStyle(
                        fontSize: AppFontSize.bodySmall,
                        color: p.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildMetricTile(
                      p: p,
                      icon: Icons.tune_rounded,
                      title: context.l10n.dspPipelineDelay,
                      subtitle: context.l10n.dspPipelineDelayDesc,
                      value: '${dspMs.toStringAsFixed(2)} ms',
                      detail: context.l10n.syncPipelineFramesDetail(
                        _pipelineLatencyFrames,
                        (sr / 1000.0).toStringAsFixed(1),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (isUsbStreaming) ...[
                      _buildMetricTile(
                        p: p,
                        icon: Icons.usb_rounded,
                        title: context.l10n.usbBufferedDelay,
                        subtitle: context.l10n.usbBufferedDelayDesc,
                        value: '${_usbBufferedMs.toStringAsFixed(1)} ms',
                        detail: context.l10n.syncUsbUnderrunsOverrunsDetail(
                          (_usbDiagnostics['underrunCount'] as num?)?.toInt() ??
                              0,
                          (_usbDiagnostics['overrunCount'] as num?)?.toInt() ??
                              0,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    _buildMetricTile(
                      p: p,
                      icon: Icons.speed_rounded,
                      title: context.l10n.totalMonitoredLatency,
                      subtitle: context.l10n.totalMonitoredLatencyDesc,
                      value:
                          '${(dspMs + (isUsbStreaming ? _usbBufferedMs : 0.0)).toStringAsFixed(2)} ms',
                      detail: isUsbStreaming
                          ? context.l10n.directUsbExclusivePath
                          : context.l10n.lowLatencyDirectOutput,
                    ),
                  ],
                ),
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
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: p.accentContainer,
              borderRadius: AppRadii.r8All,
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
