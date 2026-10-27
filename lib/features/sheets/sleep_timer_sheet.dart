// lib/features/sheets/sleep_timer_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/l10n_extensions.dart';
import '../player/cubit/player_cubit.dart';
import '../player/cubit/player_state.dart';
import '../../data/audio/sleep_timer_manager.dart';

import '../../core/widgets/pulsr_bottom_sheet.dart';
import '../../core/widgets/pulsr_dialog.dart';
import '../../core/widgets/pulsr_pressable.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => const SleepTimerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final presets = [15, 30, 45, 60, 90];
    final screenHeight = MediaQuery.sizeOf(context).height;

    return BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, state) {
        final sleepTimerRemaining = state.sleepTimerRemaining;
        final cubit = context.read<PlayerCubit>();
        final remainingTracks = cubit.sleepTimerRemainingTracks;
        final isQueueMode = cubit.isEndOfQueueSleepTimer;
        final timerMode = cubit.sleepTimerMode;
        final isActive = sleepTimerRemaining != null ||
            remainingTracks != null ||
            isQueueMode;

        final chipShape = RoundedRectangleBorder(
          borderRadius: AppRadii.r12All,
        );

        return PulsrBottomSheetContainer(
          title: Text(context.l10n.sleepTimer),
          trailing: isActive
              ? PulsrPressable(
                  onTap: () {
                    cubit.cancelSleepTimer();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.s6),
                    decoration: BoxDecoration(
                      color: p.error.withValues(alpha: 0.14),
                      borderRadius: AppRadii.full,
                      border: Border.all(
                        color: p.error.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cancel_rounded, color: p.error, size: 16),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          context.l10n.turnOff,
                          style: TextStyle(
                            color: p.error,
                            fontWeight: FontWeight.w800,
                            fontSize: AppFontSize.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screenHeight * 0.72),
            child: SingleChildScrollView(
              // FIX-M5: Add viewInsets.bottom padding to prevent keyboard obscuring sheet content
              padding: EdgeInsetsDirectional.fromSTEB(
                AppSpacing.s20,
                AppSpacing.s10,
                AppSpacing.s20,
                AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isActive) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.s14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            p.accentContainer,
                            p.accentContainer.withValues(alpha: 0.55),
                          ],
                        ),
                        borderRadius: AppRadii.r16All,
                        border: Border.all(
                          color: p.accent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.bedtime_rounded,
                              color: p.accent,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              isQueueMode
                                  ? context.l10n.musicWillStopEndOfQueue
                                  : remainingTracks != null
                                      ? (remainingTracks == 1
                                          ? context.l10n.musicWillStopEndOfTrack
                                          : context.l10n
                                              .musicWillStopAfterSongs(
                                                  remainingTracks))
                                      : context.l10n.musicWillStopIn(
                                          (sleepTimerRemaining?.inMinutes ?? 0),
                                          (sleepTimerRemaining?.inSeconds ??
                                                  0) %
                                              60),
                              style: TextStyle(
                                color: p.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.body,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Section 1: Presets (Duration)
                  _SectionHeader(
                    icon: Icons.bolt_rounded,
                    label: context.l10n.presets,
                    palette: p,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: p.surfaceContainer.withValues(alpha: 0.65),
                      borderRadius: AppRadii.r16All,
                      border: Border.all(color: p.hairline),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...presets.map((mins) {
                          final isPresetActive =
                              timerMode == SleepTimerMode.duration &&
                                  sleepTimerRemaining != null &&
                                  (sleepTimerRemaining.inSeconds / 60).ceil() ==
                                      mins;
                          return ChoiceChip(
                            shape: chipShape,
                            showCheckmark: false,
                            label: Text(context.l10n.sleepTimerMinutes(mins)),
                            selected: isPresetActive,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              cubit.startSleepTimer(mins);
                              Navigator.pop(context);
                            },
                          );
                        }),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Section 2: By Songs / Queue
                  _SectionHeader(
                    icon: Icons.music_note_rounded,
                    label: context.l10n.bySongs,
                    palette: p,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: p.surfaceContainer.withValues(alpha: 0.65),
                      borderRadius: AppRadii.r16All,
                      border: Border.all(color: p.hairline),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          shape: chipShape,
                          showCheckmark: false,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.skip_next_rounded, size: 14),
                              const SizedBox(width: AppSpacing.xxs),
                              Text(context.l10n.endOfTrack),
                            ],
                          ),
                          // FIX BUG-5: Show as selected when end-of-track
                          // timer is active so the user has visual feedback.
                          selected: timerMode == SleepTimerMode.endOfTrack,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            cubit.startEndOfTrackTimer();
                            Navigator.pop(context);
                          },
                        ),
                        ChoiceChip(
                          shape: chipShape,
                          showCheckmark: false,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.queue_music_rounded, size: 14),
                              const SizedBox(width: AppSpacing.xxs),
                              Text(context.l10n.endOfQueue),
                            ],
                          ),
                          // FIX BUG-6: Show as selected when end-of-queue
                          // timer is active.
                          selected: isQueueMode,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            cubit.startEndOfQueueTimer();
                            Navigator.pop(context);
                          },
                        ),
                        ChoiceChip(
                          shape: chipShape,
                          showCheckmark: false,
                          label: Text(context.l10n.songsCount(2)),
                          selected: timerMode == SleepTimerMode.afterNTracks &&
                              remainingTracks == 2,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            cubit.startAfterNTracksTimer(2);
                            Navigator.pop(context);
                          },
                        ),
                        ChoiceChip(
                          shape: chipShape,
                          showCheckmark: false,
                          label: Text(context.l10n.songsCount(3)),
                          selected: timerMode == SleepTimerMode.afterNTracks &&
                              remainingTracks == 3,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            cubit.startAfterNTracksTimer(3);
                            Navigator.pop(context);
                          },
                        ),
                        ChoiceChip(
                          shape: chipShape,
                          showCheckmark: false,
                          label: Text(context.l10n.songsCount(5)),
                          selected: timerMode == SleepTimerMode.afterNTracks &&
                              remainingTracks == 5,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            cubit.startAfterNTracksTimer(5);
                            Navigator.pop(context);
                          },
                        ),
                        ChoiceChip(
                          shape: chipShape,
                          showCheckmark: false,
                          label: Text(context.l10n.songsCount(10)),
                          selected: timerMode == SleepTimerMode.afterNTracks &&
                              remainingTracks == 10,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            cubit.startAfterNTracksTimer(10);
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Section 3: Custom Time
                  _SectionHeader(
                    icon: Icons.tune_rounded,
                    label: context.l10n.customTime,
                    palette: p,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    decoration: BoxDecoration(
                      color: p.surfaceContainer.withValues(alpha: 0.65),
                      borderRadius: AppRadii.r16All,
                      border: Border.all(color: p.hairline),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs),
                            leading: Container(
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              decoration: BoxDecoration(
                                color: p.accentContainer,
                                borderRadius: AppRadii.r10All,
                              ),
                              child: Icon(Icons.timer_outlined,
                                  color: p.accent, size: 20),
                            ),
                            title: Text(
                              context.l10n.customDurationMinutes,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: AppFontSize.body,
                              ),
                            ),
                            trailing: Icon(Icons.chevron_right_rounded,
                                color: p.textSecondary),
                            onTap: () async {
                              final minutes =
                                  await _showCustomMinutesDialog(context);
                              if (minutes != null &&
                                  minutes > 0 &&
                                  context.mounted) {
                                cubit.startSleepTimer(minutes);
                                Navigator.pop(context);
                              }
                            },
                          ),
                          Divider(
                              color: p.hairline,
                              height: 1,
                              indent: AppSpacing.sm,
                              endIndent: AppSpacing.sm),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs),
                            leading: Container(
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              decoration: BoxDecoration(
                                color: p.accentContainer,
                                borderRadius: AppRadii.r10All,
                              ),
                              child: Icon(Icons.access_time_rounded,
                                  color: p.accent, size: 20),
                            ),
                            title: Text(
                              context.l10n.stopAtSpecificTime,
                              style: TextStyle(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: AppFontSize.body,
                              ),
                            ),
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<int?> _showCustomMinutesDialog(BuildContext context) {
    return PulsrDialogHelper.showCustomDialog<int>(
      context,
      useRootNavigator: false,
      builder: (ctx) => const _CustomMinutesDialog(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final PulsrPalette palette;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: palette.accent),
        const SizedBox(width: AppSpacing.s6),
        Text(
          label,
          style: TextStyle(
            color: palette.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: AppFontSize.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _CustomMinutesDialog extends StatefulWidget {
  const _CustomMinutesDialog();

  @override
  State<_CustomMinutesDialog> createState() => _CustomMinutesDialogState();
}

class _CustomMinutesDialogState extends State<_CustomMinutesDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PulsrDialog(
      title: Text(context.l10n.customTime),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        onChanged: (_) {
          if (_errorText != null) {
            setState(() => _errorText = null);
          }
        },
        decoration: InputDecoration(
          labelText: context.l10n.sleepTimerDurationMinutes,
          hintText: context.l10n.sleepTimerMinutesHint,
          suffixText: context.l10n.minuteAbbreviation,
          errorText: _errorText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final val = int.tryParse(_controller.text.trim());
            if (val != null && val > 0 && val <= 720) {
              Navigator.pop(context, val);
            } else {
              setState(() {
                _errorText = context.l10n.sleepTimerInvalidRange;
              });
            }
          },
          child: Text(context.l10n.ok),
        ),
      ],
    );
  }
}
