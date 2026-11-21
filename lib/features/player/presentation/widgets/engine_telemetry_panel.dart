// lib/features/player/presentation/widgets/engine_telemetry_panel.dart
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/audio/audio_effects_channel.dart';
import '../../../../domain/models/dsp_battery_estimate.dart';
import '../../../../domain/models/dsp_telemetry.dart';
import '../../cubit/dsp_telemetry_cubit.dart';

class EngineTelemetryPanel extends StatefulWidget {
  final bool initialExpanded;

  const EngineTelemetryPanel({
    super.key,
    this.initialExpanded = false,
  });

  @override
  State<EngineTelemetryPanel> createState() => _EngineTelemetryPanelState();
}

class _EngineTelemetryPanelState extends State<EngineTelemetryPanel>
    with WidgetsBindingObserver {
  late bool _isExpanded;
  late final DspTelemetryCubit _cubit;
  bool _ownsCubit = false;
  Timer? _batteryTimer;
  DspBatteryEstimate? _batteryEstimate;
  bool _batteryFetchInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isExpanded = widget.initialExpanded;
    final existingCubit = _tryReadCubit(context);
    if (existingCubit != null) {
      _cubit = existingCubit;
      _ownsCubit = false;
    } else {
      _cubit = DspTelemetryCubit();
      _ownsCubit = true;
    }

    if (_isExpanded) {
      _cubit.subscribe();
      _startBatteryPolling();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isExpanded && _batteryTimer == null) {
        _startBatteryPolling();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopBatteryPolling();
    }
  }

  void _startBatteryPolling() {
    _batteryTimer?.cancel();
    _fetchBattery();
    _batteryTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _fetchBattery());
  }

  void _stopBatteryPolling() {
    _batteryTimer?.cancel();
    _batteryTimer = null;
  }

  Future<void> _fetchBattery() async {
    if (_batteryFetchInFlight) return;
    _batteryFetchInFlight = true;
    try {
      final est = await AudioEffectsChannel()
          .getDspBatteryEstimate()
          .timeout(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() => _batteryEstimate = est);
    } catch (e, st) {
      ErrorLogger.log('Failed to fetch DSP battery estimate',
          error: e, stackTrace: st, category: 'Telemetry');
    } finally {
      _batteryFetchInFlight = false;
    }
  }

  DspTelemetryCubit? _tryReadCubit(BuildContext ctx) {
    try {
      return ctx.read<DspTelemetryCubit>();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopBatteryPolling();
    if (_isExpanded) {
      _cubit.unsubscribe();
    }
    if (_ownsCubit) {
      _cubit.close();
    }
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _cubit.subscribe();
        _startBatteryPolling();
      } else {
        _cubit.unsubscribe();
        _stopBatteryPolling();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<DspTelemetryCubit, DspTelemetry>(
        builder: (context, telemetry) {
          return Container(
            margin: const EdgeInsets.symmetric(
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: p.surfaceContainer.withValues(alpha: 0.6),
              borderRadius: AppRadii.r16All,
              border: Border.all(
                color: telemetry.isThrottling
                    ? p.error.withValues(alpha: 0.7)
                    : p.hairline,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context, p, telemetry),
                if (_isExpanded) _buildExpandedBody(context, p, telemetry),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, PulsrPalette p, DspTelemetry telemetry) {
    final rtf = telemetry.rollingRtf;
    final rtfPct = telemetry.rtfPercent;
    final Color rtfColor = rtf > 0.85
        ? p.error
        : rtf > 0.60
            ? p.warning
            : p.success;

    return InkWell(
      onTap: _toggleExpanded,
      borderRadius: AppRadii.r16All,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14,
          vertical: AppSpacing.s10,
        ),
        child: Row(
          children: [
            Icon(
              Icons.speed_rounded,
              size: 20,
              color: rtfColor,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              context.l10n.dspEngineTelemetry,
              style: TextStyle(
                fontSize: AppFontSize.bodySmall,
                color: p.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (telemetry.isAutoDegraded)
              Container(
                margin: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: p.error.withValues(alpha: 0.2),
                  borderRadius: AppRadii.r4All,
                  border: Border.all(color: p.error, width: 0.8),
                ),
                child: Text(
                  context.l10n.dspStatusDegraded,
                  style: TextStyle(
                    color: p.error,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Text(
              context.l10n.rtfPercent(rtfPct.toStringAsFixed(1)),
              style: TextStyle(
                fontSize: AppFontSize.label,
                color: rtfColor,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              _isExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 20,
              color: p.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedBody(
      BuildContext context, PulsrPalette p, DspTelemetry telemetry) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.s14,
        0,
        AppSpacing.s14,
        AppSpacing.s14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 12, color: p.hairline),
          _buildEqAutoHeadroomRow(p, telemetry.eqAutoHeadroomDb),
          const SizedBox(height: AppSpacing.sm),
          _buildLimiterMeter(context, p, telemetry.limiterGrDb),
          const SizedBox(height: AppSpacing.sm),
          _buildMultibandMeter(context, p, telemetry.multibandGrDb),
          const SizedBox(height: AppSpacing.sm),
          _buildDynEqMeter(context, p, telemetry.dynEqGrDb),
          const SizedBox(height: AppSpacing.xs),
          _buildPowerDrainSection(context, p, _batteryEstimate),
        ],
      ),
    );
  }

  Widget _buildPowerDrainSection(
      BuildContext context, PulsrPalette p, DspBatteryEstimate? est) {
    final l10n = context.l10n;
    final isBypassed = est?.lowPowerBypassActive ?? false;
    final mah = est?.estimatedMahPerHour ?? 0.0;
    final breakdown = est?.stageBreakdown ?? const <String, double>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 16, color: p.hairline),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  isBypassed
                      ? Icons.bolt_rounded
                      : Icons.battery_charging_full_rounded,
                  size: 16,
                  color: isBypassed ? p.goldAccent : p.accent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  l10n.telemetryDspPowerConsumption,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isBypassed
                    ? p.goldAccent.withValues(alpha: 0.15)
                    : (mah > 10.0
                        ? p.warning.withValues(alpha: 0.15)
                        : p.accent.withValues(alpha: 0.15)),
                borderRadius: AppRadii.r4All,
                border: Border.all(
                  color: isBypassed
                      ? p.goldAccent.withValues(alpha: 0.4)
                      : (mah > 10.0
                          ? p.warning.withValues(alpha: 0.4)
                          : p.accent.withValues(alpha: 0.3)),
                ),
              ),
              child: Text(
                isBypassed
                    ? l10n.telemetryLowPowerBypassBadge
                    : l10n.telemetryPowerDrainEstimate(mah.toStringAsFixed(1)),
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w800,
                  color: isBypassed
                      ? p.goldAccent
                      : (mah > 10.0 ? p.warning : p.accent),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (isBypassed)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l10n.telemetryLowPowerBypassDesc,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: p.textTertiary,
                height: 1.25,
              ),
            ),
          )
        else if (breakdown.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Text(
              l10n.telemetryStageDrainBreakdown,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: p.textSecondary,
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: breakdown.entries.map((entry) {
              final name = DspBatteryEstimate.stageDisplayName(entry.key);
              final cost = entry.value;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: p.surfaceContainerHigh,
                  borderRadius: AppRadii.r4All,
                  border: Border.all(color: p.hairline),
                ),
                child: Text(
                  l10n.telemetryStageDrainItem(name, cost.toStringAsFixed(1)),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              );
            }).toList(),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l10n.telemetryAllStagesIdle,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                color: p.textTertiary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEqAutoHeadroomRow(PulsrPalette p, double autoHeadroomDb) {
    final active = autoHeadroomDb < -0.05;
    return Builder(
      builder: (context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.l10n.eqAutoHeadroomTitle,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.caption,
            ),
          ),
          Text(
            context.l10n.telemetryDbValue(autoHeadroomDb.toStringAsFixed(1)),
            style: TextStyle(
              color: active ? p.warning : p.textSecondary,
              fontSize: AppFontSize.caption,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimiterMeter(
      BuildContext context, PulsrPalette p, double limiterGrDb) {
    final clampedGr = limiterGrDb.clamp(-24.0, 0.0);
    final ratio = (-clampedGr / 24.0).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.l10n.limiterReduction,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.caption,
              ),
            ),
            Text(
              context.l10n.telemetryDbValue(limiterGrDb.toStringAsFixed(1)),
              style: TextStyle(
                color: limiterGrDb < -0.1 ? p.warning : p.textSecondary,
                fontSize: AppFontSize.caption,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: AppRadii.r4All,
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: p.surfaceContainerHigh.withValues(alpha: 0.4),
            valueColor: AlwaysStoppedAnimation<Color>(
              ratio > 0.5 ? p.error : p.warning,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMultibandMeter(
      BuildContext context, PulsrPalette p, List<double> mbGr) {
    final l10n = context.l10n;
    final bandLabels = [
      l10n.telemetryBandLow,
      l10n.telemetryBandLoMid,
      l10n.telemetryBandHiMid,
      l10n.telemetryBandHigh,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.multibandCompReduction,
          style: TextStyle(
            color: p.textSecondary,
            fontSize: AppFontSize.caption,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(4, (i) {
            final gr = i < mbGr.length ? mbGr[i].clamp(-24.0, 0.0) : 0.0;
            final ratio = (-gr / 24.0).clamp(0.0, 1.0);
            return Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: i < 3 ? 6.0 : 0.0),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: AppRadii.r4All,
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 5,
                        backgroundColor:
                            p.surfaceContainerHigh.withValues(alpha: 0.4),
                        valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bandLabels[i],
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildDynEqMeter(
      BuildContext context, PulsrPalette p, List<double> dynEqGr) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dynamicEqAdjustments,
          style: TextStyle(
            color: p.textSecondary,
            fontSize: AppFontSize.caption,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(8, (i) {
            final adj =
                i < dynEqGr.length ? dynEqGr[i].clamp(-18.0, 18.0) : 0.0;
            final isCut = adj < 0;
            final ratio = (adj.abs() / 18.0).clamp(0.0, 1.0);
            return Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: i < 7 ? 3.0 : 0.0),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: AppRadii.r4All,
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 4,
                        backgroundColor:
                            p.surfaceContainerHigh.withValues(alpha: 0.4),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isCut ? p.warning : p.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.telemetryDynEqBandShort(i + 1),
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
