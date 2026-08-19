// lib/features/player/presentation/widgets/equalizer_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../domain/models/eq_preset.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

class EqualizerSheet extends StatelessWidget {
  const EqualizerSheet({super.key});

  static const List<String> _bandLabels = ['60Hz', '230Hz', '910Hz', '3.6kHz', '14kHz'];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        final preset = state.eqPreset;
        final isEnabled = state.isEqEnabled;

        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title + Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Equalizer & Effects',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  Switch.adaptive(
                    value: isEnabled,
                    activeTrackColor: AppColors.primary,
                    activeThumbColor: Colors.white,
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
                    final p = EqPreset.defaultPresets[index];
                    final isSelected = preset.name == p.name;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p.name),
                        selected: isSelected,
                        selectedColor: AppColors.primary.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        onSelected: isEnabled ? (_) => cubit.applyPreset(p) : null,
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
                          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
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
                                activeTrackColor: AppColors.primary,
                                inactiveTrackColor: AppColors.card,
                                thumbColor: Colors.white,
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
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
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
                    color: AppColors.card,
                    borderRadius: AppRadii.cardRadius,
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.speaker_group_rounded, color: AppColors.primary, size: 22),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Bass Boost',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: AppColors.background,
                            thumbColor: Colors.white,
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
        );
      },
    );
  }
}
