// lib/features/settings/presentation/widgets/settings_tiles.dart
import 'package:flutter/material.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../core/widgets/pulsr_pressable.dart';
import '../../../../core/widgets/pulsr_switch.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// Icon container used as `leading` on settings tiles (was `_iconBox`).
class SettingsIconBox extends StatelessWidget {
  final IconData icon;

  const SettingsIconBox(this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: p.accentContainer,
        borderRadius: BorderRadius.circular(AppRadii.r12),
      ),
      child: Icon(icon, color: p.accent, size: 20),
    );
  }
}

/// Hairline divider between rows inside a settings card (was `_divider`).
Widget settingsCardDivider(PulsrPalette p) =>
    Divider(height: 1, indent: 72, color: p.hairline);

/// Navigation-style settings row (was `_navTile`).
class SettingsNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final AudioFeatureInfo? featureInfo;
  final String? disabledReason;

  const SettingsNavTile(
    this.icon,
    this.title,
    this.subtitle, {
    super.key,
    this.trailing,
    this.onTap,
    this.featureInfo,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDisabled = disabledReason != null && onTap == null;
    return Opacity(
      opacity: isDisabled ? 0.55 : 1.0,
      child: PulsrPressable(
        pressedScale: 0.988,
        onTap: disabledReason != null && onTap == null
            ? () => showAudioFeatureInfoDialog(context,
                featureInfo ?? AudioFeatureRegistry.equalizer,
                conflictReason: disabledReason)
            : onTap,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s2),
          leading: SettingsIconBox(icon),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppFontSize.body,
                    letterSpacing: AppTracking.none,
                  ),
                ),
              ),
              if (featureInfo != null)
                IconButton(
                  icon: Icon(Icons.info_outline_rounded,
                      size: 18, color: p.textTertiary),
                  tooltip: context.l10n.settingsAboutTitle(title),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showAudioFeatureInfoDialog(
                      context, featureInfo!,
                      conflictReason: disabledReason),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.s2),
              Text(
                subtitle,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.label,
                  height: 1.32,
                ),
              ),
              if (disabledReason != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  disabledReason!,
                  style: TextStyle(
                    color: p.error,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          trailing: trailing ??
              Icon(
                Icons.chevron_right_rounded,
                color: p.textTertiary.withValues(alpha: 0.7),
                size: 20,
              ),
        ),
      ),
    );
  }
}

/// Switch-style settings row (was `_switchTile`).
class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final AudioFeatureInfo? featureInfo;
  final String? disabledReason;

  const SettingsSwitchTile(
    this.icon,
    this.title,
    this.subtitle, {
    super.key,
    required this.value,
    required this.onChanged,
    this.featureInfo,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDisabled = disabledReason != null;
    return Opacity(
      opacity: isDisabled ? 0.55 : 1.0,
      child: PulsrPressable(
        pressedScale: 0.988,
        onTap: isDisabled
            ? (disabledReason != null
                ? () => showAudioFeatureInfoDialog(
                      context,
                      featureInfo ?? AudioFeatureRegistry.equalizer,
                      conflictReason: disabledReason,
                    )
                : null)
            : () => onChanged(!value),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s2),
          leading: SettingsIconBox(icon),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppFontSize.body,
                    letterSpacing: AppTracking.none,
                  ),
                ),
              ),
              if (featureInfo != null)
                IconButton(
                  icon: Icon(Icons.info_outline_rounded,
                      size: 18, color: p.textTertiary),
                  tooltip: context.l10n.settingsAboutTitle(title),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showAudioFeatureInfoDialog(
                      context, featureInfo!,
                      conflictReason: disabledReason),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.s2),
              Text(
                subtitle,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.label,
                  height: 1.32,
                ),
              ),
              if (disabledReason != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  disabledReason!,
                  style: TextStyle(
                    color: p.error,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          trailing: PulsrSwitch(
            value: value,
            onChanged: isDisabled ? null : onChanged,
          ),
        ),
      ),
    );
  }
}

/// Feature info dialog (was `_showFeatureInfo`).
void showAudioFeatureInfoDialog(
    BuildContext context, AudioFeatureInfo info,
    {String? conflictReason}) {
  final p = context.palette;
  PulsrDialogHelper.showPulsrDialog<void>(
    context,
    icon: Icon(Icons.info_outline_rounded, color: p.accent, size: 26),
    title: Text(info.title),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(info.subtitle,
            style: TextStyle(
                color: p.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: AppFontSize.label)),
        const SizedBox(height: AppSpacing.s10),
        Text(info.description,
            style:
                TextStyle(color: p.textPrimary, fontSize: AppFontSize.bodySmall, height: 1.4)),
        if (info.conflictsWith != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.s10),
            decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.r10),
                border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: p.warning, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                    child: Text(
                        context.l10n.conflictsWith(info.conflictsWith ?? ''),
                        style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ],
        if (conflictReason != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.s10),
            decoration: BoxDecoration(
                color: p.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.r10),
                border: Border.all(
                    color: p.error.withValues(alpha: 0.4))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.block_rounded, color: p.error, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                    child: Text(conflictReason,
                        style: TextStyle(
                            color: p.error,
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ],
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () =>
            Navigator.of(context, rootNavigator: true).pop(),
        child: Text(context.l10n.gotIt),
      ),
    ],
  );
}
