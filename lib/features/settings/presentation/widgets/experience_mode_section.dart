// lib/features/settings/presentation/widgets/experience_mode_section.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/widgets/pulsr_segmented_control.dart';
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
          child: PulsrSegmentedControl(
            segments: [
              PulsrSegment(
                label: l10n.experienceModeNormal,
                icon: Icons.auto_awesome_rounded,
              ),
              PulsrSegment(
                label: l10n.experienceModeProfessional,
                icon: Icons.tune_rounded,
              ),
            ],
            selectedIndex: isPro ? 1 : 0,
            onChanged: (i) {
              final newMode =
                  i == 1 ? ExperienceMode.professional : ExperienceMode.normal;
              cubit.setExperienceMode(newMode);
              if (newMode == ExperienceMode.professional) {
                PulsrToast.show(
                  context,
                  title: l10n.professionalMode,
                  message: l10n.professionalModeUnlocked,
                  icon: Icons.tune_rounded,
                );
              }
            },
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        AnimatedSwitcher(
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
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
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

class _WhatChangesExpanderState extends State<_WhatChangesExpander>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PulsrMotion.state,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _WhatChangesExpander oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Collapse so stale Pro/Normal copy is never left showing after a switch.
    if (oldWidget.isPro != widget.isPro && _expanded) {
      _expanded = false;
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final changes = [
      (
        context.l10n.expEqTitle,
        context.l10n.expEqPro,
        context.l10n.expEqNormal,
      ),
      (
        context.l10n.expUsbTitle,
        context.l10n.expUsbPro,
        context.l10n.expUsbNormal,
      ),
      (
        context.l10n.expCrossfadeTitle,
        context.l10n.expCrossfadePro,
        context.l10n.expCrossfadeNormal,
      ),
      (
        context.l10n.expGainTitle,
        context.l10n.expGainPro,
        context.l10n.expGainNormal,
      ),
      (
        context.l10n.expVisualizersTitle,
        context.l10n.expVisualizersPro,
        context.l10n.expVisualizersNormal,
      ),
    ];

    final Widget changesBody = Padding(
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
    );

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.r10),
        border: Border.all(color: p.hairline.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.r10),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _expanded = !_expanded;
                  if (_expanded) {
                    _controller.forward();
                  } else {
                    _controller.reverse();
                  }
                });
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
                        context.l10n.whatChanges,
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
          ),
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              if (_controller.value == 0.0 && !_expanded) {
                return const SizedBox(width: double.infinity);
              }
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _animation.value,
                  child: child,
                ),
              );
            },
            child: changesBody,
          ),
        ],
      ),
    );
  }
}
