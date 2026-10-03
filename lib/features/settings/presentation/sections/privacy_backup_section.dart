part of '../settings_screen.dart';

mixin SettingsPrivacyBackupSection
    on
        SettingsSectionPrimitives,
        SettingsCategoryMetadata,
        State<SettingsScreen> {
  Widget _buildPrivacyBackupSection(BuildContext context) {
    final p = context.palette;

    return _section(
      context,
      context.l10n.privacyAndData,
      context.l10n.settingsPrivacySectionSubtitle,
      [
        const BackupSection(),
        _divider(p),
        _navTile(
          context,
          Icons.equalizer_outlined,
          context.l10n.settingsScrobblingTitle,
          context.l10n.settingsScrobblingSubtitle,
          onTap: () => showScrobblerSettingsModal(context),
        ),
        _divider(p),
        _navTile(
          context,
          Icons.bar_chart_rounded,
          context.l10n.settingsScrobbleStatsTitle,
          context.l10n.settingsScrobbleStatsSubtitle,
          onTap: () => context.push('/scrobble-stats'),
        ),
        if (AppConfig.isCloudSyncAllowed) ...[
          _divider(p),
          _navTile(
            context,
            Icons.cloud_sync_rounded,
            context.l10n.settingsCloudBackupDashboard,
            context.l10n.settingsCloudBackupDashboardSubtitle,
            onTap: () => context.push('/cloud-backup-dashboard'),
          ),
        ],
        _divider(p),
        _navTile(
          context,
          Icons.security_rounded,
          context.l10n.privacyGuarantee,
          context.l10n.privacyGuaranteeSubtitle,
          onTap: () => showPrivacyGuaranteeSheet(context),
        ),
      ],
      key: _catById('privacy').key,
    );
  }
}
