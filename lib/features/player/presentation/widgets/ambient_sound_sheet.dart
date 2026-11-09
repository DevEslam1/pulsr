import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/services/ambient_sound_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_switch.dart';
import 'ambient_sound_panel.dart';

/// Modal bottom sheet allowing users to enable, configure, and adjust volume for
/// ambient background sounds (Rain, Fire, Forest, Ocean, etc.).
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
    final p = context.palette;
    final service = AmbientSoundService();

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        return PulsrBottomSheetContainer(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.ambientSounds),
              if (service.isEnabled) ...[
                const SizedBox(width: AppSpacing.xs),
                AmbientStatusBadge(
                  isPlaying: service.isAudioPlaying,
                  palette: p,
                ),
                const SizedBox(width: AppSpacing.xs),
                AmbientActiveBadge(
                  count: service.activeEffects.length,
                  palette: p,
                ),
              ],
            ],
          ),
          subtitle: Text(
            service.isEnabled && service.isSuppressedByQuran
                ? l10n.ambientAllowDuringQuran
                : service.isEnabled && !service.isPlayerPlaying
                    ? l10n.ambientPausedWithPlayer
                    : service.isEnabled
                        ? service.activeEffects.map((e) => e.emoji).join(' ')
                        : l10n.ambientSoundsDesc,
          ),
          trailing: Semantics(
            label: l10n.ambientSounds,
            toggled: service.isEnabled,
            value: service.isEnabled
                ? l10n.semanticsStateOn
                : l10n.semanticsStateOff,
            child: PulsrSwitch(
              value: service.isEnabled,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                unawaited(service.setEnabled(v));
              },
            ),
          ),
          child: const SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: AmbientSoundPanel(
              showContainerDecoration: false,
              showHeader: false,
            ),
          ),
        );
      },
    );
  }
}
