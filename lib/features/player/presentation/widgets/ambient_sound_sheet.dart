import 'package:flutter/material.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import 'ambient_sound_panel.dart';

/// Modal bottom sheet allowing users to enable, configure, and adjust volume for
/// ambient background sounds (Rain, Fire).
class AmbientSoundSheet extends StatelessWidget {
  const AmbientSoundSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => const AmbientSoundSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PulsrBottomSheetContainer(
      title: Text(l10n.ambientSounds),
      subtitle: Text(l10n.ambientSoundsDesc),
      child: const SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: AmbientSoundPanel(
          showContainerDecoration: false,
        ),
      ),
    );
  }
}

