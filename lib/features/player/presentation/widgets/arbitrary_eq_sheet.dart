// lib/features/player/presentation/widgets/arbitrary_eq_sheet.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'eq_curve_visualizer.dart';

class ArbitraryEqSheet extends StatefulWidget {
  const ArbitraryEqSheet({super.key});

  @override
  State<ArbitraryEqSheet> createState() => _ArbitraryEqSheetState();
}

class _ArbitraryEqSheetState extends State<ArbitraryEqSheet> {
  late final TextEditingController _textController;
  late bool _linearPhase;

  static const Map<String, String> _presets = {
    'Harman Target Curve':
        'GraphicEq: 20 5.2; 30 5.1; 40 4.8; 60 4.0; 80 3.2; 120 1.8; 200 0.5; 500 0.0; 1000 0.0; 2000 1.8; 3000 3.5; 4000 2.0; 6000 -1.5; 8000 0.0; 12000 -2.0; 20000 -4.0',
    'Sub-Bass Punch & Rumble':
        'GraphicEq: 20 6.0; 30 5.5; 45 4.5; 65 3.0; 90 1.5; 140 0.0; 300 -1.0; 1000 0.0; 4000 0.5; 8000 1.0; 16000 0.0; 20000 0.0',
    'Vocal Clarity & Presence':
        'GraphicEq: 20 -2.0; 60 -1.5; 120 -1.0; 250 0.0; 500 1.0; 1000 2.0; 2500 3.0; 4000 2.5; 6000 1.0; 10000 0.0; 20000 0.0',
    'Acoustic Warmth & Air':
        'GraphicEq: 20 1.5; 80 2.0; 200 1.5; 400 0.5; 1000 0.0; 2500 -1.0; 5000 1.0; 10000 2.5; 16000 3.5; 20000 2.0',
  };

  @override
  void initState() {
    super.initState();
    final cubit = context.read<PlayerCubit>();
    final current = cubit.state.arbitraryEqString;
    _textController = TextEditingController(
      text: current.isNotEmpty ? current : _presets.values.first,
    );
    _textController.addListener(_onTextChanged);
    _linearPhase = cubit.isArbitraryEqLinearPhase;
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  ({List<double> frequencies, List<double> gains}) _parseGraphicEq(
      String text) {
    final clean = text
        .replaceFirst(RegExp(r'^GraphicEq:\s*', caseSensitive: false), '')
        .trim();
    if (clean.isEmpty) {
      return (frequencies: <double>[], gains: <double>[]);
    }
    final entries = clean.split(';');
    final freqs = <double>[];
    final gains = <double>[];
    for (final entry in entries) {
      final parts = entry.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final f = double.tryParse(parts[0]);
        final g = double.tryParse(parts[1]);
        if (f != null && g != null) {
          freqs.add(f);
          gains.add(g);
        }
      }
    }
    return (frequencies: freqs, gains: gains);
  }

  void _apply(BuildContext context) {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      context.read<PlayerCubit>().setArbitraryEqEnabled(true,
          eqString: text, linearPhase: _linearPhase);
      PulsrToast.show(
        context,
        message: context.l10n.appliedGraphicEq,
        icon: Icons.check_circle_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.isArbitraryEqEnabled != curr.isArbitraryEqEnabled ||
          prev.arbitraryEqString != curr.arbitraryEqString,
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        final parsed = _parseGraphicEq(_textController.text);

        return Container(
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
                        Icon(Icons.graphic_eq_rounded, color: p.primary),
                        const SizedBox(width: AppSpacing.s10),
                        Text(
                          context.l10n.arbitraryResponseEq,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.title,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: state.isArbitraryEqEnabled,
                      activeThumbColor: p.primary,
                      onChanged: (val) {
                        cubit.setArbitraryEqEnabled(val,
                            eqString: _textController.text.trim(),
                            linearPhase: _linearPhase);
                      },
                    ),
                  ],
                ),
                Text(
                  AudioFeatureRegistry.arbitraryEq
                      .localized(context.l10n)
                      .subtitle,
                  style: TextStyle(
                      color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s14, vertical: AppSpacing.s10),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer,
                    borderRadius: AppRadii.r14All,
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.linearPhaseFir,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: AppFontSize.bodySmall,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s2),
                            Text(
                              _linearPhase
                                  ? context.l10n.linearPhaseOnDesc
                                  : context.l10n.linearPhaseOffDesc,
                              style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.caption),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: _linearPhase,
                        activeThumbColor: p.primary,
                        onChanged: (val) {
                          setState(() => _linearPhase = val);
                          cubit.setArbitraryEqEnabled(
                            state.isArbitraryEqEnabled,
                            eqString: _textController.text.trim(),
                            linearPhase: val,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // EqualizerAPO format input
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer,
                    borderRadius: AppRadii.r16All,
                    border: Border.all(color: p.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            context.l10n.graphicEqSpec,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            context.l10n.fir512,
                            style: TextStyle(
                              color: p.primary,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // Live read-only EqCurveVisualizer preview
                      ClipRRect(
                        borderRadius: AppRadii.r10All,
                        child: Container(
                          height: 72,
                          color: p.surface,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s8,
                            vertical: AppSpacing.xs,
                          ),
                          child: EqCurveVisualizer(
                            gains: parsed.gains.isNotEmpty
                                ? parsed.gains
                                : List.filled(10, 0.0),
                            frequencies: parsed.frequencies.isNotEmpty
                                ? parsed.frequencies
                                : null,
                            activeColor: p.primary,
                            height: 72,
                            maxGain: parsed.gains.isNotEmpty
                                ? math.max(
                                    12.0,
                                    parsed.gains
                                        .map((g) => g.abs())
                                        .reduce(math.max),
                                  )
                                : 12.0,
                            showGrid: true,
                            showLabels: false,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: _textController,
                        maxLines: 4,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppFontSize.label,
                          color: p.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'GraphicEq: 20 0; 1000 3; 20000 -2',
                          hintStyle: TextStyle(
                            color: p.textTertiary,
                            fontFamily: 'monospace',
                            fontSize: AppFontSize.label,
                          ),
                          filled: true,
                          fillColor: p.surface,
                          contentPadding: const EdgeInsets.all(AppSpacing.sm),
                          border: OutlineInputBorder(
                            borderRadius: AppRadii.r10All,
                            borderSide: BorderSide(color: p.hairline),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: AppRadii.r10All,
                            borderSide: BorderSide(color: p.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              _textController.text =
                                  'GraphicEq: 20 0; 1000 0; 20000 0';
                            },
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            label: Text(context.l10n.resetToFlat),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: p.textSecondary,
                              side: BorderSide(color: p.hairline),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadii.r10All,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          FilledButton.icon(
                            onPressed: () => _apply(context),
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: Text(context.l10n.applyCurve),
                            style: FilledButton.styleFrom(
                              backgroundColor: p.accent,
                              foregroundColor: p.onAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadii.r10All,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),

                Text(
                  context.l10n.presetAcousticTargets,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.s10),
                ..._presets.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _textController.text = entry.value;
                        });
                        cubit.setArbitraryEqEnabled(true,
                            eqString: entry.value, linearPhase: _linearPhase);
                      },
                      borderRadius: AppRadii.r14All,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s14,
                            vertical: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: AppRadii.r14All,
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_graph_rounded,
                              color: p.primary,
                              size: 18,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: AppFontSize.bodySmall,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: p.textTertiary,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
