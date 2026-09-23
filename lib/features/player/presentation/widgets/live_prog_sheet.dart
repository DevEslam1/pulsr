// lib/features/player/presentation/widgets/live_prog_sheet.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../data/audio/live_prog_slider_persistence.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class LiveProgSheet extends StatefulWidget {
  const LiveProgSheet({super.key});

  @override
  State<LiveProgSheet> createState() => _LiveProgSheetState();
}

class _LiveProgSheetState extends State<LiveProgSheet> {
  late final TextEditingController _codeController;
  final Map<int, double> _sliderValues = {
    1: 5.0,
    2: 0.5,
    3: 0.0,
    4: 0.0,
    5: 0.0,
    6: 0.0,
    7: 0.0,
    8: 0.0,
  };

  static const Map<String, String> _scriptPresets = {
    'Stereo Sine Tremolo': '''@init
phase = 0;

@sample
freq = slider1;
depth = slider2;
lfo = (sin(phase) + 1.0) * 0.5 * depth + (1.0 - depth);
spl0 = spl0 * lfo;
spl1 = spl1 * lfo;
phase = phase + (2 * 3.141592653589793 * freq / srate);
if (phase > 2 * 3.141592653589793) phase = phase - 2 * 3.141592653589793;''',

    'Analog Soft Saturation': '''@init

@sample
drive = slider1;
spl0 = spl0 * (1.0 + drive);
spl1 = spl1 * (1.0 + drive);
spl0 = spl0 / (1.0 + abs(spl0));
spl1 = spl1 / (1.0 + abs(spl1));''',

    'Dynamic Auto-Panner': '''@init
pan_pos = 0;

@sample
rate = slider1;
pan = sin(pan_pos);
spl0 = spl0 * (0.5 * (1.0 - pan));
spl1 = spl1 * (0.5 * (1.0 + pan));
pan_pos = pan_pos + (2 * 3.141592653589793 * rate / srate);
if (pan_pos > 2 * 3.141592653589793) pan_pos = pan_pos - 2 * 3.141592653589793;''',

    'Gentle Bitcrusher': '''@init

@sample
bits = slider1;
steps = pow(2, bits);
spl0 = floor(spl0 * steps + 0.5) / steps;
spl1 = floor(spl1 * steps + 0.5) / steps;''',

    'Slapback Echo': '''@init
pos = 0;
buf0_0 = 0; buf0_1 = 0; buf0_2 = 0; buf0_3 = 0;
buf1_0 = 0; buf1_1 = 0; buf1_2 = 0; buf1_3 = 0;

@sample
mix = slider2;
spl0 = spl0 + (buf0_0 + buf0_1 + buf0_2 + buf0_3) * 0.125 * mix;
spl1 = spl1 + (buf1_0 + buf1_1 + buf1_2 + buf1_3) * 0.125 * mix;
buf0_3 = buf0_2; buf0_2 = buf0_1; buf0_1 = buf0_0; buf0_0 = spl0;
buf1_3 = buf1_2; buf1_2 = buf1_1; buf1_1 = buf1_0; buf1_0 = spl1;''',

    'Bass Lift': '''@init
lp0 = 0; lp1 = 0;

@sample
amount = slider2;
lp0 = lp0 + 0.08 * (spl0 - lp0);
lp1 = lp1 + 0.08 * (spl1 - lp1);
spl0 = spl0 + lp0 * amount;
spl1 = spl1 + lp1 * amount;''',
  };

  @override
  void initState() {
    super.initState();
    final current = context.read<PlayerCubit>().state.liveProgCode;
    _codeController = TextEditingController(
      text: current.isNotEmpty ? current : _scriptPresets.values.first,
    );
    _restoreSliders();
  }

  Future<void> _restoreSliders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefsKeys.liveProgSliders);
      final saved = decodeLiveProgSliders(raw);
      if (saved.isNotEmpty && mounted) {
        setState(() {
          _sliderValues.addAll(saved);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _compileAndRun(BuildContext context) {
    final code = _codeController.text.trim();
    if (code.isNotEmpty) {
      context.read<PlayerCubit>().setLiveProgEnabled(true, code: code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.eelCompiled)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.isLiveProgEnabled != curr.isLiveProgEnabled ||
          prev.liveProgCode != curr.liveProgCode,
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();

        return Container(
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
                        Icon(Icons.terminal_rounded, color: p.primary),
                        const SizedBox(width: AppSpacing.s10),
                        Text(context.l10n.liveProgDspTitle,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.title,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: state.isLiveProgEnabled,
                      activeThumbColor: p.primary,
                      onChanged: (val) {
                        cubit.setLiveProgEnabled(val,
                            code: _codeController.text.trim());
                      },
                    ),
                  ],
                ),
                Text(
                  AudioFeatureRegistry.liveProg.subtitle,
                  style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                ),
                const SizedBox(height: AppSpacing.md),

                // Script Code Editor
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppRadii.r16),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(context.l10n.eelEditor,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(

                                horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
                            decoration: BoxDecoration(
                              color: p.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppRadii.r6),
                            ),
                            child: Text(context.l10n.bytecodeJit,
                              style: TextStyle(
                                color: p.primary,
                                fontSize: AppFontSize.tiny,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: _codeController,
                        maxLines: 8,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppFontSize.caption,
                          color: p.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: '@init\nphase = 0;\n\n@sample\nspl0 = spl0 * 0.8;',
                          hintStyle: TextStyle(
                            color: p.textTertiary,
                            fontFamily: 'monospace',
                            fontSize: AppFontSize.caption,
                          ),
                          filled: true,
                          fillColor: p.surface,
                          contentPadding: const EdgeInsets.all(AppSpacing.sm),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r10),
                            borderSide: BorderSide(color: p.hairline),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r10),
                            borderSide: BorderSide(color: p.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _compileAndRun(context),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: Text(context.l10n.compileRun),
                            style: FilledButton.styleFrom(
                              backgroundColor: p.accent,
                              foregroundColor: p.onAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadii.r10),
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

                // Real-time Slider Controls (slider1..slider8)
                Text(context.l10n.liveSliders,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (int i = 1; i <= 8; ++i)
                  _buildSlider(
                    label: i == 1
                        ? context.l10n.dspSlider1Label
                        : (i == 2 ? context.l10n.dspSlider2Label : 'slider$i'),
                    value: _sliderValues[i] ?? (i == 1 ? 5.0 : (i == 2 ? 0.5 : 0.0)),
                    min: i == 1 ? 0.1 : 0.0,
                    max: i == 1 ? 20.0 : 1.0,
                    onChanged: (val) {
                      setState(() => _sliderValues[i] = val);
                      cubit.setLiveProgSlider(i, val);
                    },
                    p: p,
                  ),
                const SizedBox(height: AppSpacing.s20),

                Text(context.l10n.exampleScripts,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.s10),
                ..._scriptPresets.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _codeController.text = entry.value;
                        });
                        cubit.setLiveProgEnabled(true, code: entry.value);
                      },
                      borderRadius: BorderRadius.circular(AppRadii.r14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(

                            horizontal: AppSpacing.s14, vertical: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: BorderRadius.circular(AppRadii.r14),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.code_rounded,
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

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required PulsrPalette p,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.r12),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
              ),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: AppFontSize.label,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: p.primary,
              inactiveTrackColor: p.hairline,
              thumbColor: p.primary,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
