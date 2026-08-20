// lib/features/sheets/sleep_timer_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/adaptive.dart';
import '../player/cubit/player_cubit.dart';
import '../player/cubit/player_state.dart';

class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final presets = [15, 30, 45, 60, 90];
    final screenHeight = MediaQuery.sizeOf(context).height;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Adaptive.maxSheetWidth,
              maxHeight: screenHeight * 0.75,
            ),
            child: Material(
              color: p.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: BlocBuilder<PlayerCubit, PlayerState>(
                    builder: (context, state) {
                      final cubit = context.read<PlayerCubit>();
                      final isActive = state.sleepTimerRemaining != null;

                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Sleep Timer',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: p.textPrimary,
                                      ),
                                ),
                                if (isActive)
                                  TextButton.icon(
                                    onPressed: () {
                                      cubit.cancelSleepTimer();
                                      Navigator.pop(context);
                                    },
                                    icon: const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 18),
                                    label: const Text('Turn Off', style: TextStyle(color: Colors.redAccent)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (isActive)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(
                                  'Music will stop in ${state.sleepTimerRemaining!.inMinutes}m ${state.sleepTimerRemaining!.inSeconds % 60}s',
                                  style: TextStyle(
                                    color: p.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Text(
                              'Presets',
                              style: TextStyle(
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: presets.map((mins) {
                                return ChoiceChip(
                                  label: Text('$mins min'),
                                  selected: false,
                                  onSelected: (_) {
                                    cubit.startSleepTimer(mins);
                                    Navigator.pop(context);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Custom Time',
                              style: TextStyle(
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: p.surfaceContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.access_time_rounded, color: p.accent),
                              ),
                              title: Text('Stop at specific time', style: TextStyle(color: p.textPrimary)),
                              trailing: Icon(Icons.chevron_right_rounded, color: p.textSecondary),
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
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
