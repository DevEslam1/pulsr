part of '../settings_screen.dart';

mixin SettingsSectionPrimitives on State<SettingsScreen> {
  Widget _section(
    BuildContext context,
    String title,
    String subtitle,
    List<Widget> children, {
    GlobalKey? key,
    IconData? icon,
  }) {
    return KeyedSubtree(
      key: key,
      child: SettingsSection(
        icon: icon,
        title: title,
        subtitle: subtitle.isNotEmpty ? subtitle : null,
        children: children,
      ),
    );
  }

  Widget _divider(PulsrPalette p) =>
      Divider(height: 1, indent: 72, color: p.hairline);

  Widget _iconBox(BuildContext context, IconData icon) => SettingsIconBox(icon);

  Widget _navTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    Widget? trailing,
    String? trailingBadge,
    VoidCallback? onTap,
  }) {
    final p = context.palette;
    return PulsrPressable(
      pressedScale: 0.988,
      onTap: onTap,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.s2),
        leading: _iconBox(context, icon),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppFontSize.body,
            letterSpacing: AppTracking.none,
          ),
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
          ],
        ),
        trailing: trailing ??
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trailingBadge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                    margin:
                        const EdgeInsetsDirectional.only(end: AppSpacing.s6),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.r6),
                    ),
                    child: Text(
                      trailingBadge,
                      style: TextStyle(
                        color: p.accent,
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w800,
                        letterSpacing: AppTracking.label,
                      ),
                    ),
                  ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: p.textTertiary.withValues(alpha: 0.7),
                  size: 20,
                ),
              ],
            ),
      ),
    );
  }

  Widget _switchTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final p = context.palette;
    return PulsrPressable(
      pressedScale: 0.988,
      onTap: () => onChanged(!value),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.s2),
        leading: _iconBox(context, icon),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppFontSize.body,
            letterSpacing: AppTracking.none,
          ),
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
          ],
        ),
        trailing: PulsrSwitch(
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ==========================================================================
  // Dialogs
  // ==========================================================================

  void _showDurationFilterDialog(
    BuildContext context,
    SettingsCubit cubit,
    int currentSec,
  ) {
    int selected = currentSec;
    PulsrDialogHelper.showPulsrDialog<void>(
      context,
      title: Text(context.l10n.minDuration),
      content: StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.excludeTracksUnder(selected),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.settings_backup_restore,
                      size: 20,
                      color: selected == 30
                          ? Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.38)
                          : context.palette.accent),
                  tooltip: context.l10n.resetToDefault30s,
                  visualDensity: VisualDensity.compact,
                  onPressed: selected == 30
                      ? null
                      : () => setDialogState(() => selected = 30),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            PulsrSlider(
              value: selected.toDouble(),
              min: 0,
              max: 120,
              divisions: 12,
              semanticLabel: context.l10n.excludeTracksUnder(selected),
              onChanged: (val) {
                setDialogState(() => selected = val.toInt());
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.accent,
            foregroundColor: context.palette.onAccent,
          ),
          onPressed: () {
            cubit.setMinDuration(selected);
            Navigator.pop(context);
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
  }

  Future<void> _removeMissingFiles(
    BuildContext context,
    SettingsCubit cubit,
  ) async {
    final l10n = context.l10n;
    final missingCount = await cubit.getMissingFilesCount();
    if (!context.mounted) return;
    final contentText = missingCount > 0
        ? '${l10n.removeMissingFilesConfirmBody}\n\n$missingCount ${missingCount == 1 ? "missing file" : "missing files"}.'
        : l10n.removeMissingFilesConfirmBody;
    final confirmed = await PulsrDialogHelper.showPulsrDialog<bool>(
      context,
      title: Text(l10n.removeMissingFilesConfirmTitle),
      content: Text(contentText),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.remove),
        ),
      ],
    );
    if (confirmed != true) return;
    final removed = await cubit.removeMissingFiles();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.removedMissingTracks(removed)),
      ),
    );
  }

  Future<void> _fetchMissingArtwork(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await PulsrDialogHelper.showPulsrDialog<bool>(
      context,
      title: Text(l10n.fetchMissingArtworkTitle),
      content: Text(l10n.fetchMissingArtworkBody),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.accent,
            foregroundColor: context.palette.onAccent,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.fetchArtwork),
        ),
      ],
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.fetchArtwork)),
    );
    final int count;
    try {
      if (!getIt.isRegistered<MissingArtworkService>()) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.artworkServiceUnavailable)));
        return;
      }
      count =
          await getIt<MissingArtworkService>().fetchAndPersistMissingArtwork();
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.artworkServiceUnavailable)));
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(count > 0
            ? l10n.updatedArtworkForAlbums(count)
            : l10n.noMissingArtworkFound),
      ),
    );
  }
}
