// lib/features/player/presentation/widgets/equalizer_sheet.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../domain/models/eq_preset.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

class EqualizerSheet extends StatelessWidget {
  const EqualizerSheet({super.key});

  static const List<String> _bandLabels = ['60Hz', '230Hz', '910Hz', '3.6kHz', '14kHz'];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        final preset = state.eqPreset;
        final isEnabled = state.isEqEnabled;

        if (!Platform.isAndroid) {
          return Material(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: p.hairline,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Icon(Icons.equalizer_rounded, color: p.textTertiary, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Equalizer not available',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The built-in equalizer is only supported on Android devices.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Material(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Title + Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Equalizer & Effects',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.textPrimary),
                    ),
                    Switch.adaptive(
                      value: isEnabled,
                      activeTrackColor: p.accent,
                      activeThumbColor: p.onAccent,
                      onChanged: (val) => cubit.setEqualizerEnabled(val),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Presets Carousel
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: EqPreset.defaultPresets.length,
                    itemBuilder: (context, index) {
                      final presetItem = EqPreset.defaultPresets[index];
                      final isSelected = preset.name == presetItem.name;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(presetItem.name),
                          selected: isSelected,
                          selectedColor: p.accent.withValues(alpha: 0.18),
                          backgroundColor: p.surfaceContainer,
                          labelStyle: TextStyle(
                            color: isSelected ? p.accent : p.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          onSelected: isEnabled ? (_) => cubit.applyPreset(presetItem) : null,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // 5-Band Sliders
                Opacity(
                  opacity: isEnabled ? 1.0 : 0.4,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(5, (index) {
                      final gain = index < preset.gains.length ? preset.gains[index] : 0.0;
                      return Column(
                        children: [
                          Text(
                            '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)}dB',
                            style: TextStyle(fontSize: 10, color: p.textSecondary, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 140,
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                  activeTrackColor: p.accent,
                                  inactiveTrackColor: p.surfaceContainer,
                                  thumbColor: p.accent,
                                ),
                                child: Slider(
                                  value: gain.clamp(-15.0, 15.0),
                                  min: -15.0,
                                  max: 15.0,
                                  onChanged: isEnabled
                                      ? (val) => cubit.setBandGain(index, val)
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _bandLabels[index],
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.textPrimary),
                          ),
                        ],
                      );
                    }),
                  ),
                ),

                const SizedBox(height: 24),

                // Bass Boost
                Opacity(
                  opacity: isEnabled ? 1.0 : 0.4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: AppRadii.cardRadius,
                      border: Border.all(color: p.hairline),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.speaker_group_rounded, color: p.accent, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Bass Boost',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.textPrimary),
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              activeTrackColor: p.accent,
                              inactiveTrackColor: p.surface,
                              thumbColor: p.accent,
                            ),
                            child: Slider(
                              value: preset.bassBoost.clamp(0.0, 1.0),
                              min: 0.0,
                              max: 1.0,
                              onChanged: isEnabled ? (val) => cubit.setBassBoost(val) : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
}
