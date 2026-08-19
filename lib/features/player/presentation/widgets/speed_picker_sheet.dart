// lib/features/player/presentation/widgets/speed_picker_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

class SpeedPickerSheet extends StatelessWidget {
  const SpeedPickerSheet({super.key});

  static const List<double> speedOptions = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    2.5,
    3.0,
  ];

  static String formatSpeed(double speed) {
    if (speed == 0.75 || speed == 1.25 || speed == 2.5) {
      return '${speed}x';
    }
    return '${speed.toStringAsFixed(1)}x';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.bottomSheetRadius,
      ),
      child: BlocBuilder<PlayerCubit, PlayerState>(
        builder: (context, state) {
          final cubit = context.read<PlayerCubit>();
          final currentSpeed = state.playbackSpeed;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 20),
              Text(
                'Playback Speed',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Current speed: ${formatSpeed(currentSpeed)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: speedOptions.map((speed) {
                    final isSelected = (currentSpeed == speed);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(formatSpeed(speed)),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.card,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : AppColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? AppColors.primary : AppColors.outline,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            cubit.setPlaybackSpeed(speed);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
