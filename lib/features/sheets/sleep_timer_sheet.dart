// lib/features/sheets/sleep_timer_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/l10n_extensions.dart';
import '../player/cubit/player_cubit.dart';
import '../player/cubit/player_state.dart';

import '../../core/widgets/pulsr_bottom_sheet.dart';
import '../../core/widgets/pulsr_pressable.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => const SleepTimerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final presets = [15, 30, 45, 60, 90];
    final screenHeight = MediaQuery.sizeOf(context).height;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.sleepTimerRemaining != curr.sleepTimerRemaining,
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        final remainingTracks = cubit.sleepTimerRemainingTracks;
        final isQueueMode = cubit.isEndOfQueueSleepTimer;
        final isActive = state.sleepTimerRemaining != null ||
            remainingTracks != null ||
            isQueueMode;

        return PulsrBottomSheetContainer(
          title: Text(context.l10n.sleepTimer),
          trailing: isActive
              ? PulsrPressable(
                  onTap: () {
                    cubit.cancelSleepTimer();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
                    decoration: BoxDecoration(
                      color: p.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.r8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cancel_rounded, color: p.error, size: 16),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(context.l10n.turnOff,
                            style: TextStyle(
                                color: p.error,
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.label)),
                      ],
                    ),
                  ),
                )
              : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screenHeight * 0.70),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.s10, AppSpacing.s20, AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                            if (isActive)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                                child: Text(
                                  isQueueMode
                                      ? context.l10n.musicWillStopEndOfQueue
                                      : remainingTracks != null
                                          ? (remainingTracks == 1
                                              ? context.l10n
                                                  .musicWillStopEndOfTrack
                                              : context.l10n
                                                  .musicWillStopAfterSongs(
                                                      remainingTracks))
                                          : context.l10n.musicWillStopIn(
                                              state.sleepTimerRemaining!
                                                  .inMinutes,
                                              state.sleepTimerRemaining!
                                                      .inSeconds %
                                                  60),
                                  style: TextStyle(
                                    color: p.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              context.l10n.bySongs,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: AppFontSize.bodySmall,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.skip_next_rounded, size: 14),
                                      const SizedBox(width: AppSpacing.xxs),
                                      Text(context.l10n.endOfTrack),
                                    ],
                                  ),
                                  selected: false,
                                  onSelected: (_) {
                                    cubit.startEndOfTrackTimer();
                                    Navigator.pop(context);
                                  },
                                ),
                                ChoiceChip(
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.queue_music_rounded, size: 14),
                                      const SizedBox(width: AppSpacing.xxs),
                                      Text(context.l10n.endOfQueue),
                                    ],
                                  ),
                                  selected: false,
                                  onSelected: (_) {
                                    cubit.startEndOfQueueTimer();
                                    Navigator.pop(context);
                                  },
                                ),
                                ChoiceChip(
                                  label: Text(context.l10n.songsCount(2)),
                                  selected: false,
                                  onSelected: (_) {
                                    cubit.startAfterNTracksTimer(2);
                                    Navigator.pop(context);
                                  },
                                ),
                                ChoiceChip(
                                  label: Text(context.l10n.songsCount(3)),
                                  selected: false,
                                  onSelected: (_) {
                                    cubit.startAfterNTracksTimer(3);
                                    Navigator.pop(context);
                                  },
                                ),
                                ChoiceChip(
                                  label: Text(context.l10n.songsCount(5)),
                                  selected: false,
                                  onSelected: (_) {
                                    cubit.startAfterNTracksTimer(5);
                                    Navigator.pop(context);
                                  },
                                ),
                                ChoiceChip(
                                  label: Text(context.l10n.songsCount(10)),
                                  selected: false,
                                  onSelected: (_) {
                                    cubit.startAfterNTracksTimer(10);
                                    Navigator.pop(context);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s20),
                            Text(
                              context.l10n.presets,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: AppFontSize.bodySmall,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ...presets.map((mins) {
                                  return ChoiceChip(
                                    label: Text(context.l10n.sleepTimerMinutes(mins)),
                                    selected: false,
                                    onSelected: (_) {
                                      cubit.startSleepTimer(mins);
                                      Navigator.pop(context);
                                    },
                                  );
                                }),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              context.l10n.customTime,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: AppFontSize.bodySmall,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                padding: const EdgeInsets.all(AppSpacing.xs),
                                decoration: BoxDecoration(
                                  color: p.surfaceContainer,
                                  borderRadius: BorderRadius.circular(AppRadii.r8),
                                ),
                                child: Icon(Icons.access_time_rounded,
                                    color: p.accent),
                              ),
                              title: Text(context.l10n.stopAtSpecificTime,
                                  style: TextStyle(color: p.textPrimary)),
                              trailing: Icon(Icons.chevron_right_rounded,
                                  color: p.textSecondary),
                              onTap: () async {
                                final now = TimeOfDay.now();
                                final selectedTime = await showTimePicker(
                                  context: context,
                                  initialTime: now,
                                );
                                if (selectedTime != null && context.mounted) {
                                  final today = DateTime.now();
                                  var stopDate = DateTime(
                                      today.year,
                                      today.month,
                                      today.day,
                                      selectedTime.hour,
                                      selectedTime.minute);
                                  if (stopDate.isBefore(today)) {
                                    stopDate =
                                        stopDate.add(const Duration(days: 1));
                                  }
                                  cubit.startAbsoluteSleepTimer(stopDate);
                                  Navigator.pop(context);
                                }
                              },
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
