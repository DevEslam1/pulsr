// lib/features/settings/presentation/widgets/experience_mode_section.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// Lets the user switch between the curated Normal experience and the full
/// Professional control surface. This is the single switch that reveals or
/// hides advanced settings across the app.
class ExperienceModeSection extends StatelessWidget {
  const ExperienceModeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final mode = context
        .select<SettingsCubit, ExperienceMode>((c) => c.state.experienceMode);
    final cubit = context.read<SettingsCubit>();
    final isPro = mode == ExperienceMode.professional;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(
            l10n.experienceModeSubtitle,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: AppFontSize.label,
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ExperienceMode>(
            showSelectedIcon: true,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
            segments: [
              ButtonSegment<ExperienceMode>(
                value: ExperienceMode.normal,
                label: Text(l10n.experienceModeNormal),
                icon: const Icon(Icons.auto_awesome_rounded),
              ),
              ButtonSegment<ExperienceMode>(
                value: ExperienceMode.professional,
                label: Text(l10n.experienceModeProfessional),
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                final newMode = selection.first;
                cubit.setExperienceMode(newMode);
                if (newMode == ExperienceMode.professional) {
                  PulsrToast.show(
                    context,
                    title: 'Professional Mode',
                    message: 'Advanced DSP, bit-perfect streaming, and pro audio controls unlocked.',
                    icon: Icons.tune_rounded,
                  );
                }
              }
            },
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        SizedBox(
          height: 38,
          child: AnimatedSwitcher(
            duration: context.motionMs(200),
            child: Text(
              isPro
                  ? l10n.experienceModeProfessionalDesc
                  : l10n.experienceModeNormalDesc,
              key: ValueKey<bool>(isPro),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.label,
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: p.surfaceContainerHigh.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(AppRadii.r10),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isPro ? Icons.tune_rounded : Icons.auto_awesome_rounded,
                    size: 15,
                    color: isPro ? p.accent : p.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      isPro
                          ? l10n.experienceModeProfessional
                          : l10n.experienceModeNormal,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(

                        horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
                    decoration: BoxDecoration(
                      color: (isPro ? p.accent : p.textTertiary)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadii.r6),
                    ),
                    child: Text(
                      isPro ? 'PRO' : l10n.experienceModeNormal.toUpperCase(),
                      style: TextStyle(
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w700,
                        color: isPro ? p.accent : p.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              AnimatedSwitcher(
                duration: context.motionMs(200),
                child: Text(
                  isPro
                      ? l10n.settingsDspInspectorDesc
                      : l10n.smartAudioSubtitle,
                  key: ValueKey<bool>(isPro),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: p.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        _WhatChangesExpander(isPro: isPro),
      ],
    );
  }
}

class _WhatChangesExpander extends StatefulWidget {
  final bool isPro;
  const _WhatChangesExpander({required this.isPro});

  @override
  State<_WhatChangesExpander> createState() => _WhatChangesExpanderState();
}

class _WhatChangesExpanderState extends State<_WhatChangesExpander> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final changes = [
      (
        'Equalizer & DSP',
        'Parametric 10-Band EQ, Q-factor & Room Correction',
        'Curated Smart Audio Presets',
      ),
      (
        'USB DAC & Output',
        'Bit-Perfect hardware lock, DSD DoP streaming',
        'System AudioTrack (32-bit float)',
      ),
      (
        'Playback & Crossfade',
        'Fine-grained 0-12s curve & latency calibration',
        'Standard 3s smooth crossfade',
      ),
      (
        'Gain & Loudness',
        'ReplayGain dB calibration & manual pre-amp',
        'Automatic perceived loudness leveling',
      ),
      (
        'Visualizers',
        'Milkdrop preset interpreter & Custom JSON',
        'Classic Wave & Radial Frequency styles',
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.r10),
        border: Border.all(color: p.hairline.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadii.r10),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    size: 15,
                    color: p.accent,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      "What changes?",
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: context.motionMs(200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: p.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Column(
                children: [
                  Divider(height: 1, color: p.hairline.withValues(alpha: 0.4)),
                  const SizedBox(height: AppSpacing.xs),
                  for (final item in changes) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 13,
                            color: widget.isPro ? p.accent : p.textTertiary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${item.$1}: ',
                                    style: TextStyle(
                                      fontSize: AppFontSize.tiny,
                                      fontWeight: FontWeight.w800,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: widget.isPro ? item.$2 : item.$3,
                                    style: TextStyle(
                                      fontSize: AppFontSize.tiny,
                                      color: p.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: context.motionMs(240),
          ),
        ],
      ),
    );
  }
}
