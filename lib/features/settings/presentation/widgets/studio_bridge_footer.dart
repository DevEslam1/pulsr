// lib/features/settings/presentation/widgets/studio_bridge_footer.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';

/// A subtle Normal-mode bridge that tells the user how many Professional
/// ("Studio") controls are hidden in the current section, and offers a single
/// discoverable path to unlock them. Renders nothing in Professional mode.
class StudioBridgeFooter extends StatelessWidget {
  final int hiddenControls;

  const StudioBridgeFooter({super.key, required this.hiddenControls});

  @override
  Widget build(BuildContext context) {
    final mode = context
        .select<SettingsCubit, ExperienceMode>((c) => c.state.experienceMode);
    if (mode == ExperienceMode.professional || hiddenControls <= 0) {
      return const SizedBox.shrink();
    }

    final p = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.r12),
          onTap: () {
            HapticFeedback.selectionClick();
            showStudioExplainerSheet(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: p.accentContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadii.r12),
              border: Border.all(color: p.accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 16, color: p.accent),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    context.l10n.studioControlsAvailable(hiddenControls),
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary,
                    ),
                  ),
                ),
                Text(
                  context.l10n.studioMoreInStudio,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w800,
                    color: p.accent,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: p.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains what Professional mode unlocks, with a single switch CTA.
Future<void> showStudioExplainerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // Root navigator so the single root PulsrModalObserver tracks it and the
    // dock hides even when opened from inside the Settings branch.
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final p = sheetContext.palette;
      final l10n = sheetContext.l10n;
      final unlocks = <(IconData, String)>[
        (Icons.graphic_eq_rounded, l10n.expEqPro),
        (Icons.usb_rounded, l10n.expUsbPro),
        (Icons.compare_arrows_rounded, l10n.expCrossfadePro),
        (Icons.volume_up_rounded, l10n.expGainPro),
        (Icons.bar_chart_rounded, l10n.expVisualizersPro),
      ];
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: p.accent),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.studioExplainerTitle,
                      style: TextStyle(
                        fontSize: AppFontSize.title,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.studioExplainerBody,
                style: TextStyle(
                  fontSize: AppFontSize.bodySmall,
                  height: 1.35,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final (icon, text) in unlocks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 16, color: p.accent),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          text,
                          style: TextStyle(
                            fontSize: AppFontSize.bodySmall,
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    context
                        .read<SettingsCubit>()
                        .setExperienceMode(ExperienceMode.professional);
                    Navigator.of(sheetContext).pop();
                  },
                  icon: const Icon(Icons.tune_rounded),
                  label: Text(l10n.studioSwitchCta),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
