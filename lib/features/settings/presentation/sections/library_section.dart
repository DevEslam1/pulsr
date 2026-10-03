part of '../settings_screen.dart';

mixin SettingsLibrarySection
    on
        SettingsSectionPrimitives,
        SettingsCategoryMetadata,
        State<SettingsScreen> {
  Widget _buildLibrarySection(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;

    return _section(
      context,
      context.l10n.libraryAndScanning,
      context.l10n.settingsLibrarySectionSubtitle,
      [
        _navTile(
          context,
          Icons.folder_off_rounded,
          context.l10n.hiddenAndExcludedFolders,
          state.autoHideSystemMedia
              ? context.l10n.autoFilteringVoiceMemos
              : context.l10n.manageExcludedDirectories,
          onTap: () => context.push('/hidden-folders'),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.refresh_rounded,
          state.isScanning
              ? context.l10n.scanningStorage
              : context.l10n.rescanLibrary,
          state.scanResultCount != null
              ? context.l10n.lastScanTracks(state.scanResultCount!)
              : context.l10n.scanDeviceStorageForAudio,
          trailing: state.isScanning
              ? StreamBuilder<double>(
                  stream: cubit.scanProgress,
                  initialData: 0.0,
                  builder: (context, snapshot) {
                    final progress = (snapshot.data ?? 0.0).clamp(0.0, 1.0);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s10, vertical: AppSpacing.xxs),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        borderRadius: AppRadii.r10All,
                      ),
                      child: Text(
                        '${(progress * 100).round()}%',
                        style: TextStyle(
                          color: p.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: AppFontSize.label,
                        ),
                      ),
                    );
                  },
                )
              : null,
          onTap: state.isScanning ? () {} : () => cubit.rescanLibrary(),
        ),
        if (state.isScanning)
          StreamBuilder<double>(
            stream: cubit.scanProgress,
            initialData: 0.0,
            builder: (context, snapshot) {
              final progress = (snapshot.data ?? 0.0).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
                child: ClipRRect(
                  borderRadius: AppRadii.r4All,
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 4,
                    backgroundColor: p.surfaceContainer,
                    valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                  ),
                ),
              );
            },
          ),
        _divider(p),
        _navTile(
          context,
          Icons.filter_list_rounded,
          context.l10n.shortAudioFilter,
          context.l10n.ignoreFilesUnder(state.minDurationSec),
          trailingBadge: '${state.minDurationSec}s',
          onTap: () =>
              _showDurationFilterDialog(context, cubit, state.minDurationSec),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.manage_search_rounded,
          context.l10n.settingsRebuildSearchIndexTitle,
          context.l10n.settingsRebuildSearchIndexSubtitle,
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            final rebuiltMsg = context.l10n.settingsSearchIndexRebuilt;
            final failedMsg = context.l10n.settingsSearchIndexRebuildFailed;
            final ok = await cubit.rebuildSearchIndex();
            messenger
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(content: Text(ok ? rebuiltMsg : failedMsg)),
              );
          },
        ),
        _divider(p),
        _navTile(
          context,
          Icons.cleaning_services_rounded,
          context.l10n.removeMissingFiles,
          context.l10n.removeMissingFilesSubtitle,
          onTap: () => _removeMissingFiles(context, cubit),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.image_search_rounded,
          context.l10n.fetchMissingArtworkTooltip,
          context.l10n.fetchMissingArtworkBody,
          onTap: () => _fetchMissingArtwork(context),
        ),
      ],
      key: _catById('library').key,
    );
  }
}
