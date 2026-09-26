// lib/features/player/presentation/widgets/speed_picker_sheet.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class SpeedPickerSheet extends StatelessWidget {
  const SpeedPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => const SpeedPickerSheet(),
    );
  }

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

  /// Chips offered for the engine's active range. Falls back to the stable
  /// 0.5-3.0 set; when the advanced 0.1-8.0 range is enabled it adds the
  /// extended steps so the toggle is actually usable.
  static List<double> speedOptionsFor(double min, double max) {
    if (min > max) {
      return speedOptions;
    }
    final base = <double>[
      0.1,
      0.25,
      0.5,
      0.75,
      1.0,
      1.25,
      1.5,
      2.0,
      2.5,
      3.0,
      4.0,
      5.0,
      6.0,
      7.0,
      8.0,
    ];
    final filtered = base.where((s) => s >= min && s <= max).toList();
    return filtered.isNotEmpty ? filtered : speedOptions;
  }

  static const List<double> pitchSemitoneOptions = [
    -6.0,
    -4.0,
    -2.0,
    -1.0,
    0.0,
    1.0,
    2.0,
    4.0,
    6.0,
  ];

  static double semitonesToPitch(double semitones) =>
      math.pow(2.0, semitones / 12.0).toDouble();

  static String formatSpeed(double speed) => '${speed.toStringAsFixed(2)}x';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BlocSelector<PlayerCubit, PlayerState, ({double speed, double pitch})>(
      selector: (state) => (speed: state.playbackSpeed, pitch: state.playbackPitch),
      builder: (context, playback) {
        final cubit = context.read<PlayerCubit>();
        final currentSpeed = playback.speed;
        final currentPitch = playback.pitch;
        final options = speedOptionsFor(
            cubit.minPlaybackSpeed, cubit.maxPlaybackSpeed);
        final semitones = currentPitch == 1.0
            ? 0
            : (12.0 *
                    (currentPitch > 0
                        ? math.log(currentPitch) / math.ln2
                        : 0.0))
                .round();

        return PulsrBottomSheetContainer(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.xs, AppSpacing.s20, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n.playbackSpeed,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: p.textPrimary,
                          ),
                    ),
                    if (currentSpeed != 1.0)
                      TextButton(
                        onPressed: () => cubit.setPlaybackSpeed(1.0),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(context.l10n.reset,
                            style: TextStyle(
                                color: p.accent, fontSize: AppFontSize.bodySmall)),
                      ),
                  ],
                ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            context.l10n.currentSpeed(formatSpeed(currentSpeed)),
                            style:
                                TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                          ),
                          const SizedBox(height: AppSpacing.s14),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: options.map((speed) {
                                final isSelected = (currentSpeed == speed);
                                return Padding(
                                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                                  child: ChoiceChip(
                                    label: Text(formatSpeed(speed)),
                                    selected: isSelected,
                                    selectedColor:
                                        p.accent.withValues(alpha: 0.2),
                                    backgroundColor: p.surfaceContainer,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? p.accent
                                          : p.textPrimary,
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
                          const SizedBox(height: AppSpacing.lg),
                          Divider(color: p.hairline),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(context.l10n.pitchShift,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: p.textPrimary,
                                    ),
                              ),
                              if ((currentPitch - 1.0).abs() > 0.01)
                                TextButton(
                                  onPressed: () => cubit.setPlaybackPitch(1.0),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(context.l10n.reset,
                                      style: TextStyle(
                                          color: p.accent, fontSize: AppFontSize.bodySmall)),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s6),
                          Text(
                            (currentPitch - 1.0).abs() < 0.01
                                ? context.l10n.dspOriginalPitch
                                : '${semitones > 0 ? '+' : ''}$semitones semitones (${currentPitch.toStringAsFixed(2)}x)',
                            style:
                                TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          PulsrSlider(
                            value: currentPitch.clamp(0.5, 2.0),
                            min: 0.5,
                            max: 2.0,
                            divisions: 30,
                            semanticLabel: context.l10n.pitchShift,
                            onChanged: (value) {
                              cubit.setPlaybackPitch(value);
                            },
                          ),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                0.75,
                                0.85,
                                0.9,
                                1.0,
                                1.1,
                                1.15,
                                1.25,
                              ].map((pitch) {
                                final isSelected =
                                    (currentPitch - pitch).abs() < 0.02;
                                final label = pitch == 1.0
                                    ? context.l10n.dspNormal
                                    : '${pitch > 1.0 ? '+' : ''}${((pitch - 1.0) * 100).round()}%';
                                return Padding(
                                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                                  child: ChoiceChip(
                                    label: Text(label),
                                    selected: isSelected,
                                    selectedColor:
                                        p.accent.withValues(alpha: 0.2),
                                    backgroundColor: p.surfaceContainer,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? p.accent
                                          : p.textPrimary,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      fontSize: AppFontSize.label,
                                    ),
                                    side: BorderSide(
                                      color: isSelected ? p.accent : p.hairline,
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        cubit.setPlaybackPitch(pitch);
                                      }
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }
          }
