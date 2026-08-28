// lib/features/player/presentation/widgets/speed_picker_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
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
    final p = context.palette;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: Adaptive.sheetConstraints(context).maxWidth),
        child: Material(
          color: p.surface,
          borderRadius: AppRadii.bottomSheetRadius,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: BlocBuilder<PlayerCubit, PlayerState>(
              builder: (context, state) {
                final cubit = context.read<PlayerCubit>();
                final currentSpeed = state.playbackSpeed;

                return SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 20),
                      Text(
                        context.l10n.playbackSpeed,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: p.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.currentSpeed(formatSpeed(currentSpeed)),
                        style: TextStyle(color: p.textSecondary, fontSize: 13),
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
                                selectedColor: p.accent.withValues(alpha: 0.2),
                                backgroundColor: p.surfaceContainer,
                                labelStyle: TextStyle(
                                  color: isSelected ? p.accent : p.textPrimary,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                                side: BorderSide(
                                  color: isSelected ? p.accent : p.hairline,
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
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
