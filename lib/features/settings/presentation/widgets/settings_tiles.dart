// lib/features/settings/presentation/widgets/settings_tiles.dart
import 'package:flutter/material.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/theme/aura_theme.dart';

/// Icon container used as `leading` on settings tiles (was `_iconBox`).
class SettingsIconBox extends StatelessWidget {
  final IconData icon;

  const SettingsIconBox(this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: p.accentContainer,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: p.accent, size: 19),
    );
  }
}

/// Hairline divider between rows inside a settings card (was `_divider`).
Widget settingsCardDivider(PulsrPalette p) =>
    Divider(height: 1, indent: 68, color: p.hairline);

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
      child: ListTile(
        leading: SettingsIconBox(icon),
        title: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            if (featureInfo != null)
              IconButton(
                icon: Icon(Icons.info_outline_rounded, size: 18, color: p.textTertiary),
                tooltip: 'About $title',
                visualDensity: VisualDensity.compact,
                onPressed: () => showAudioFeatureInfoDialog(context, featureInfo!, conflictReason: disabledReason),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: TextStyle(color: p.textSecondary, fontSize: 12)),
            if (disabledReason != null) ...[
              const SizedBox(height: 4),
              Text(disabledReason!, style: TextStyle(color: p.error, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
        trailing: trailing ??
            Icon(Icons.chevron_right_rounded, color: p.textTertiary, size: 20),
        onTap: disabledReason != null && onTap == null
            ? () => showAudioFeatureInfoDialog(context,
                featureInfo ?? AudioFeatureRegistry.equalizer,
                conflictReason: disabledReason)
            : onTap,
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
      child: ListTile(
        leading: SettingsIconBox(icon),
        title: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            if (featureInfo != null)
              IconButton(
                icon: Icon(Icons.info_outline_rounded, size: 18, color: p.textTertiary),
                tooltip: 'About $title',
                visualDensity: VisualDensity.compact,
                onPressed: () => showAudioFeatureInfoDialog(context, featureInfo!, conflictReason: disabledReason),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: TextStyle(color: p.textSecondary, fontSize: 12)),
            if (disabledReason != null) ...[
              const SizedBox(height: 4),
              Text(disabledReason!, style: TextStyle(color: p.error, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
        trailing: Switch.adaptive(
            value: value,
            activeTrackColor: p.accent,
            activeThumbColor: Colors.white,
            onChanged: isDisabled ? null : onChanged),
      ),
    );
  }
}

/// Feature info dialog (was `_showFeatureInfo`).
void showAudioFeatureInfoDialog(
    BuildContext context, AudioFeatureInfo info,
    {String? conflictReason}) {
  final p = context.palette;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.surface,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: p.accentContainer, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.info_outline_rounded, color: p.accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(info.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(info.subtitle, style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 10),
            Text(info.description, style: TextStyle(color: p.textPrimary, fontSize: 13, height: 1.4)),
            if (info.conflictsWith != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.withValues(alpha: 0.4))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Conflicts with: ${info.conflictsWith}', style: TextStyle(color: p.textSecondary, fontSize: 11, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            ],
            if (conflictReason != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.error.withValues(alpha: 0.4))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.block_rounded, color: p.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(conflictReason, style: TextStyle(color: p.error, fontSize: 11, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
    ),
  );
}
