// lib/features/settings/presentation/widgets/experience_mode_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
    final mode = context
        .select<SettingsCubit, ExperienceMode>((c) => c.state.experienceMode);
    final cubit = context.read<SettingsCubit>();
    final isPro = mode == ExperienceMode.professional;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<ExperienceMode>(
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
        const SizedBox(height: 8),
        Text(
          isPro
              ? l10n.experienceModeProfessionalDesc
              : l10n.experienceModeNormalDesc,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
