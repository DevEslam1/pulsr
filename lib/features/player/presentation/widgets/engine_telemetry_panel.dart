// lib/features/player/presentation/widgets/engine_telemetry_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/aura_theme.dart';
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

class _EngineTelemetryPanelState extends State<EngineTelemetryPanel> {
  late bool _isExpanded;
  late final DspTelemetryCubit _cubit;
  bool _ownsCubit = false;

  @override
  void initState() {
    super.initState();
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
      } else {
        _cubit.unsubscribe();
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
              borderRadius: BorderRadius.circular(AppRadii.r16),
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

  Widget _buildHeader(BuildContext context, PulsrPalette p, DspTelemetry telemetry) {
    final rtf = telemetry.rollingRtf;
    final rtfPct = telemetry.rtfPercent;
    final Color rtfColor = rtf > 0.85
        ? p.error
        : rtf > 0.60
            ? p.warning
            : p.success;

    return InkWell(
      onTap: _toggleExpanded,
      borderRadius: BorderRadius.circular(AppRadii.r16),
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
              "DSP Engine Telemetry",
              style: TextStyle(
                fontSize: 13,
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
                  borderRadius: BorderRadius.circular(AppRadii.r4),
                  border: Border.all(color: p.error, width: 0.8),
                ),
                child: Text(
                  "DEGRADED",
                  style: TextStyle(
                    color: p.error,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Text(
              'RTF: ${rtfPct.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12,
                color: rtfColor,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              _isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 20,
              color: p.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedBody(BuildContext context, PulsrPalette p, DspTelemetry telemetry) {
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
          _buildLimiterMeter(p, telemetry.limiterGrDb),
          const SizedBox(height: AppSpacing.sm),
          _buildMultibandMeter(p, telemetry.multibandGrDb),
          const SizedBox(height: AppSpacing.sm),
          _buildDynEqMeter(p, telemetry.dynEqGrDb),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _buildLimiterMeter(PulsrPalette p, double limiterGrDb) {
    final clampedGr = limiterGrDb.clamp(-24.0, 0.0);
    final ratio = (-clampedGr / 24.0).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Limiter Reduction",
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 11,
              ),
            ),
            Text(
              '${limiterGrDb.toStringAsFixed(1)} dB',
              style: TextStyle(
                color: limiterGrDb < -0.1 ? p.warning : p.textSecondary,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.r4),
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

  Widget _buildMultibandMeter(PulsrPalette p, List<double> mbGr) {
    final bandLabels = ['Low', 'Lo-Mid', 'Hi-Mid', 'High'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Multiband Comp Reduction",
          style: TextStyle(
            color: p.textSecondary,
            fontSize: 11,
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
                      borderRadius: BorderRadius.circular(AppRadii.r4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 5,
                        backgroundColor: p.surfaceContainerHigh.withValues(alpha: 0.4),
                        valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bandLabels[i],
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 9,
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

  Widget _buildDynEqMeter(PulsrPalette p, List<double> dynEqGr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Dynamic EQ Adjustments",
          style: TextStyle(
            color: p.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(8, (i) {
            final adj = i < dynEqGr.length ? dynEqGr[i].clamp(-18.0, 18.0) : 0.0;
            final isCut = adj < 0;
            final ratio = (adj.abs() / 18.0).clamp(0.0, 1.0);
            return Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: i < 7 ? 3.0 : 0.0),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.r4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 4,
                        backgroundColor: p.surfaceContainerHigh.withValues(alpha: 0.4),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isCut ? p.warning : p.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'B${i + 1}',
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 8,
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
