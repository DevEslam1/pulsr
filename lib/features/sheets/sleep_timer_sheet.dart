// lib/features/sheets/sleep_timer_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_radii.dart';
import '../player/cubit/player_cubit.dart';
import '../player/cubit/player_state.dart';

class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final presets = [15, 30, 45, 60, 90];

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.bottomSheetRadius,
      ),
      child: BlocBuilder<PlayerCubit, PlayerState>(
        builder: (context, state) {
          final cubit = context.read<PlayerCubit>();
          final isActive = state.sleepTimerRemaining != null;

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sleep Timer',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (isActive)
                    TextButton.icon(
                      onPressed: () {
                        cubit.cancelSleepTimer();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.cancel_rounded, color: AppColors.error, size: 18),
                      label: const Text('Turn Off', style: TextStyle(color: AppColors.error)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Music will gently fade out and pause when the timer ends.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: presets.map((mins) {
                  return InkWell(
                    onTap: () {
                      cubit.startSleepTimer(mins);
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: Text(
                        '$mins min',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: const Icon(Icons.music_note_rounded, color: AppColors.primary, size: 20),
                ),
                title: const Text('End of current track', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Pause when current song completes', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                onTap: () {
                  final remainingSec = (state.duration - state.position).inSeconds.clamp(1, 7200);
                  cubit.startSleepTimer((remainingSec / 60).ceil());
                  Navigator.pop(context);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: const Icon(Icons.schedule_rounded, color: AppColors.primary, size: 20),
                ),
                title: const Text('Set specific time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('e.g. stop playing at 11:30 PM', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                onTap: () async {
                  final now = TimeOfDay.now();
                  final selectedTime = await showTimePicker(
                    context: context,
                    initialTime: now,
                  );
                  if (selectedTime != null && context.mounted) {
                    final today = DateTime.now();
                    var stopDate = DateTime(today.year, today.month, today.day, selectedTime.hour, selectedTime.minute);
                    if (stopDate.isBefore(today)) {
                      stopDate = stopDate.add(const Duration(days: 1));
                    }
                    cubit.startAbsoluteSleepTimer(stopDate);
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
