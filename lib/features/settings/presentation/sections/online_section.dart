part of '../settings_screen.dart';

mixin SettingsOnlineSection
    on
        SettingsSectionPrimitives,
        SettingsCategoryMetadata,
        State<SettingsScreen> {
  Widget _buildOnlineSection(
    BuildContext context,
    SettingsState state,
    SettingsCubit cubit,
  ) {
    final p = context.palette;

    return _section(
      context,
      AppConfig.ytmEnabled
          ? context.l10n.youtubeMusicAndOnline
          : context.l10n.networkAndProxy,
      context.l10n.settingsOnlineSectionSubtitle,
      [
        if (AppConfig.ytmEnabled) ...[
          // Account + web-player entries trigger network; hide them when the
          // user has turned on offline-only mode (Home/Search already do).
          if (!state.offlineOnlyMode) ...[
            () {
              final ytmAccount = getIt<YtmAccountService>();
              return ValueListenableBuilder<bool>(
                valueListenable: ytmAccount.loginState,
                builder: (context, isLoggedIn, _) {
                  if (!isLoggedIn) {
                    return _navTile(
                      context,
                      Icons.account_circle_outlined,
                      context.l10n.connectYtmAccount,
                      context.l10n.connectYtmSubtitle,
                      onTap: () async {
                        final ok = await YtmWebLoginSheet.show(context);
                        if (ok == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.l10n.ytmConnected),
                            ),
                          );
                        }
                      },
                    );
                  } else {
                    return _navTile(
                      context,
                      Icons.account_circle_rounded,
                      context.l10n.ytmConnected,
                      '${ytmAccount.accountName ?? context.l10n.castConnected} • ${context.l10n.settingsTapToManage}',
                      trailingBadge: context.l10n.settingsBadgeConnected,
                      onTap: () => showYtmAccountDisconnectDialog(context),
                    );
                  }
                },
              );
            }(),
            _divider(p),
            _navTile(
              context,
              Icons.language_rounded,
              context.l10n.openYtmWeb,
              context.l10n.openYtmWebSubtitle,
              onTap: () => showYtmWebOptionsSheet(context),
            ),
            _divider(p),
          ],
          _switchTile(
            context,
            Icons.cloud_off_rounded,
            context.l10n.offlineOnlyMode,
            context.l10n.offlineOnlySubtitle,
            value: state.offlineOnlyMode,
            onChanged: cubit.setOfflineOnlyMode,
          ),
          if (!state.offlineOnlyMode) ...[
            _divider(p),
            _switchTile(
              context,
              Icons.wifi_rounded,
              context.l10n.wifiOnlyMode,
              context.l10n.wifiOnlySubtitle,
              value: state.wifiOnlyMode,
              onChanged: cubit.setWifiOnlyMode,
            ),
            _divider(p),
            _navTile(
              context,
              Icons.travel_explore_rounded,
              context.l10n.searchYtm,
              context.l10n.searchYtmSubtitle,
              onTap: () => context.push('/ytm-search'),
            ),
            _divider(p),
            _navTile(
              context,
              Icons.wifi_tethering_rounded,
              context.l10n.streamingQuality,
              getQualityTitle(state.streamingQuality, context.l10n),
              trailingBadge: state.streamingQuality.name.toUpperCase(),
              onTap: () => showQualityPickerSheet(
                context,
                cubit,
                isStreaming: true,
                currentQuality: state.streamingQuality,
              ),
            ),
            _divider(p),
            _navTile(
              context,
              Icons.downloading_rounded,
              context.l10n.downloadQuality,
              getQualityTitle(state.downloadQuality, context.l10n),
              trailingBadge: state.downloadQuality.name.toUpperCase(),
              onTap: () => showQualityPickerSheet(
                context,
                cubit,
                isStreaming: false,
                currentQuality: state.downloadQuality,
              ),
            ),
            _divider(p),
            const DownloadConcurrencyTile(),
            _divider(p),
            const DownloadLocationTile(),
            _divider(p),
            _navTile(
              context,
              Icons.folder_zip_rounded,
              context.l10n.downloadsTitle,
              context.l10n.settingsDownloadsSubtitle,
              onTap: () => context.push('/downloads'),
            ),
          ],
          _divider(p),
        ],
        _navTile(
          context,
          Icons.vpn_lock_rounded,
          context.l10n.proxySettings,
          state.proxyEnabled
              ? '${state.proxyType.displayName} • ${state.proxyHost.isNotEmpty ? "${state.proxyHost}:${state.proxyPort}" : context.l10n.settingsProxyEnabled}'
              : context.l10n.settingsProxyDisabledHint,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.proxyEnabled)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                  margin: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: p.success.withValues(alpha: 0.15),
                    borderRadius: AppRadii.r6All,
                  ),
                  child: Text(
                    context.l10n.activeLabel,
                    style: TextStyle(
                      color: p.success,
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              Icon(Icons.chevron_right_rounded,
                  color: p.textTertiary, size: 20),
            ],
          ),
          onTap: () => context.push('/proxy-settings'),
        ),
      ],
      key: _catById('network').key,
    );
  }
}
