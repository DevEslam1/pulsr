// lib/features/sheets/sleep_timer_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/adaptive.dart';
import '../../core/utils/l10n_extensions.dart';
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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 32),
                  child: BlocBuilder<PlayerCubit, PlayerState>(
                    buildWhen: (prev, curr) =>
                        prev.sleepTimerRemaining != curr.sleepTimerRemaining,
                    builder: (context, state) {
                      final cubit = context.read<PlayerCubit>();
                      final remainingTracks = cubit.sleepTimerRemainingTracks;
                      final isQueueMode = cubit.isEndOfQueueSleepTimer;
                      final isActive = state.sleepTimerRemaining != null ||
                          remainingTracks != null ||
                          isQueueMode;

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
                                  context.l10n.sleepTimer,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
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
                                    icon: Icon(Icons.cancel_rounded,
                                        color: p.error, size: 18),
                                    label: Text(context.l10n.turnOff,
                                        style: TextStyle(color: p.error)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (isActive)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
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
                            const SizedBox(height: 16),
                            Text(
                              context.l10n.bySongs,
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
                              children: [
                                ChoiceChip(
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.skip_next_rounded, size: 14),
                                      const SizedBox(width: 4),
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
                                      const SizedBox(width: 4),
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
                            const SizedBox(height: 20),
                            Text(
                              context.l10n.presets,
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
                            const SizedBox(height: 24),
                            Text(
                              context.l10n.customTime,
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
