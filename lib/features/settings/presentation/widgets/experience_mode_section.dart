// lib/features/settings/presentation/widgets/experience_mode_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';

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
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.experienceModeSubtitle,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 12.5,
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
              if (selection.isNotEmpty) cubit.setExperienceMode(selection.first);
            },
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              isPro
                  ? l10n.experienceModeProfessionalDesc
                  : l10n.experienceModeNormalDesc,
              key: ValueKey<bool>(isPro),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: p.surfaceContainerHigh.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isPro
                          ? l10n.experienceModeProfessional
                          : l10n.experienceModeNormal,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isPro ? p.accent : p.textTertiary)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isPro ? 'PRO' : l10n.experienceModeNormal.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isPro ? p.accent : p.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  isPro
                      ? l10n.settingsDspInspectorDesc
                      : l10n.smartAudioSubtitle,
                  key: ValueKey<bool>(isPro),
                  style: TextStyle(
                    fontSize: 11,
                    color: p.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
