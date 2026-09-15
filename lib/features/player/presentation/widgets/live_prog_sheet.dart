// lib/features/player/presentation/widgets/live_prog_sheet.dart
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

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
  };

  @override
  void initState() {
    super.initState();
    final current = context.read<PlayerCubit>().state.liveProgCode;
    _codeController = TextEditingController(
      text: current.isNotEmpty ? current : _scriptPresets.values.first,
    );
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
                        Icon(Icons.terminal_rounded, color: p.primary),
                        const SizedBox(width: 10),
                        Text(context.l10n.liveProgDspTitle,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
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
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),

                // Script Code Editor
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
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
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: p.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(context.l10n.bytecodeJit,
                              style: TextStyle(
                                color: p.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _codeController,
                        maxLines: 8,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: p.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: '@init\nphase = 0;\n\n@sample\nspl0 = spl0 * 0.8;',
                          hintStyle: TextStyle(
                            color: p.textTertiary,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                          filled: true,
                          fillColor: p.surface,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: p.hairline),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: p.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _compileAndRun(context),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: Text(context.l10n.compileRun),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: p.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Real-time Slider Controls (slider1, slider2)
                Text(context.l10n.liveSliders,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildSlider(
                  label: context.l10n.dspSlider1Label,
                  value: _sliderValues[1] ?? 5.0,
                  min: 0.1,
                  max: 20.0,
                  onChanged: (val) {
                    setState(() => _sliderValues[1] = val);
                    cubit.setLiveProgSlider(1, val);
                  },
                  p: p,
                ),
                _buildSlider(
                  label: context.l10n.dspSlider2Label,
                  value: _sliderValues[2] ?? 0.5,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (val) {
                    setState(() => _sliderValues[2] = val);
                    cubit.setLiveProgSlider(2, val);
                  },
                  p: p,
                ),
                const SizedBox(height: 20),

                Text(context.l10n.exampleScripts,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ..._scriptPresets.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _codeController.text = entry.value;
                        });
                        cubit.setLiveProgEnabled(true, code: entry.value);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.code_rounded,
                              color: p.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: 13,
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
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
                style: TextStyle(color: p.textSecondary, fontSize: 12),
              ),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
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
