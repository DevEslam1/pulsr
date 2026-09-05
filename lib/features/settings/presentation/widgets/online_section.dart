// lib/features/settings/presentation/widgets/online_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/ytm_account_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../auth/presentation/ytm_web_login_sheet.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import 'settings_section.dart';
import 'settings_tiles.dart';

/// YouTube Music account + online behavior (ytmEnabled builds).
class YtmOnlineSection extends StatelessWidget {
  final SettingsState state;

  const YtmOnlineSection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    return SettingsSection(
      icon: Icons.language_rounded,
      title: context.l10n.youtubeMusicAndOnline,
      children: [
        () {
          final ytmAccount = getIt<YtmAccountService>();
          return ValueListenableBuilder<bool>(
            valueListenable: ytmAccount.loginState,
            builder: (context, isLoggedIn, _) {
              if (!isLoggedIn) {
                return SettingsNavTile(
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
                return SettingsNavTile(
                  Icons.account_circle_rounded,
                  context.l10n.ytmConnected,
                  '${ytmAccount.accountName ?? "Connected"} • Tap to manage',
                  onTap: () => _showYtmAccountDisconnectDialog(context),
                );
              }
            },
          );
        }(),
        settingsCardDivider(p),
        SettingsNavTile(
          Icons.language_rounded,
          context.l10n.openYtmWeb,
          context.l10n.openYtmWebSubtitle,
          onTap: () => _showYtmWebOptionsSheet(context),
        ),
        settingsCardDivider(p),
        SettingsSwitchTile(
          Icons.cloud_off_rounded,
          context.l10n.offlineOnlyMode,
          context.l10n.offlineOnlySubtitle,
          value: state.offlineOnlyMode,
          onChanged: cubit.setOfflineOnlyMode,
        ),
        if (!state.offlineOnlyMode) ...[
          settingsCardDivider(p),
          SettingsSwitchTile(
            Icons.wifi_rounded,
            context.l10n.wifiOnlyMode,
            context.l10n.wifiOnlySubtitle,
            value: state.wifiOnlyMode,
            onChanged: cubit.setWifiOnlyMode,
          ),
          settingsCardDivider(p),
          SettingsNavTile(
            Icons.travel_explore_rounded,
            context.l10n.searchYtm,
            context.l10n.searchYtmSubtitle,
            onTap: () => context.push('/ytm-search'),
          ),
          settingsCardDivider(p),
          SettingsNavTile(
            Icons.wifi_tethering_rounded,
            context.l10n.streamingQuality,
            _getQualityTitle(state.streamingQuality),
            onTap: () => _showQualityPickerSheet(context, cubit,
                isStreaming: true, currentQuality: state.streamingQuality),
          ),
          settingsCardDivider(p),
          SettingsNavTile(
            Icons.downloading_rounded,
            context.l10n.downloadQuality,
            _getQualityTitle(state.downloadQuality),
            onTap: () => _showQualityPickerSheet(context, cubit,
                isStreaming: false, currentQuality: state.downloadQuality),
          ),
          settingsCardDivider(p),
          SettingsNavTile(
            Icons.precision_manufacturing_rounded,
            context.l10n.extractionEngine,
            _getExtractorEngineTitle(state.extractorEngine),
            onTap: () => _showExtractorEnginePickerSheet(context, cubit,
                currentEngine: state.extractorEngine),
          ),
          if (state.extractorEngine != ExtractorEngine.onDevice) ...[
            settingsCardDivider(p),
            SettingsNavTile(
              Icons.dns_rounded,
              context.l10n.ytdlpConfig,
              state.ytdlpBackendUrl,
              onTap: () =>
                  _showYtdlpConfigDialog(context, cubit, state),
            ),
          ],
          settingsCardDivider(p),
          SettingsNavTile(
            Icons.vpn_lock_rounded,
            context.l10n.proxySettings,
            state.proxyEnabled
                ? '${state.proxyType.displayName} • ${state.proxyHost.isNotEmpty ? "${state.proxyHost}:${state.proxyPort}" : "Enabled"}'
                : 'Disabled • Tap to configure HTTP / SOCKS5',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.proxyEnabled)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: p.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                Icon(Icons.chevron_right_rounded,
                    color: p.textTertiary, size: 20),
              ],
            ),
            onTap: () => context.push('/proxy-settings'),
          ),
        ],
      ],
    );
  }

  String _getQualityTitle(YtmAudioQuality quality) {
    switch (quality) {
      case YtmAudioQuality.high:
        return 'High (~160+ kbps • Best)';
      case YtmAudioQuality.medium:
        return 'Medium (~128 kbps)';
      case YtmAudioQuality.low:
        return 'Low (~64 kbps • Data Saver)';
    }
  }

  String _getExtractorEngineTitle(ExtractorEngine engine) {
    switch (engine) {
      case ExtractorEngine.auto:
        return 'Auto (Remote + On-Device Fallback)';
      case ExtractorEngine.remoteYtdlp:
        return 'Remote yt-dlp Backend';
      case ExtractorEngine.onDevice:
        return 'On-Device Extractor (Native / NewPipe)';
    }
  }

  void _showExtractorEnginePickerSheet(
    BuildContext context,
    SettingsCubit cubit, {
    required ExtractorEngine currentEngine,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor =
        Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
        context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
        context.palette.textSecondary;

    final options = [
      (
        engine: ExtractorEngine.auto,
        title: 'Auto (Recommended)',
        subtitle:
            'Uses remote yt-dlp backend with automatic fallback to on-device extractor',
        icon: Icons.auto_mode_rounded,
      ),
      (
        engine: ExtractorEngine.remoteYtdlp,
        title: 'Remote yt-dlp Backend',
        subtitle:
            'Resolves via cloud server with proxy pool & cookie rotation to prevent bot bans',
        icon: Icons.cloud_done_rounded,
      ),
      (
        engine: ExtractorEngine.onDevice,
        title: 'On-Device Extractor',
        subtitle:
            'Extracts directly on your device via NewPipe / InnerTube (no remote server)',
        icon: Icons.phone_android_rounded,
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Stream Extraction Engine',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final isSelected = opt.engine == currentEngine;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected
                      ? primaryColor.withValues(alpha: 0.12)
                      : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(opt.icon,
                        color: isSelected ? primaryColor : textSecondary),
                    title: Text(opt.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isSelected ? primaryColor : textPrimary)),
                    subtitle: Text(opt.subtitle,
                        style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: primaryColor)
                        : null,
                    onTap: () {
                      cubit.setExtractorEngine(opt.engine);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showQualityPickerSheet(
    BuildContext context,
    SettingsCubit cubit, {
    required bool isStreaming,
    required YtmAudioQuality currentQuality,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor =
        Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ??
        context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
        context.palette.textSecondary;

    final options = [
      (
        quality: YtmAudioQuality.high,
        title: 'High Quality',
        subtitle: isStreaming
            ? 'Highest available bitrate (~160+ kbps) for crystal clear sound'
            : 'Highest quality audio files (~160+ kbps M4A)',
        icon: Icons.high_quality_rounded,
      ),
      (
        quality: YtmAudioQuality.medium,
        title: 'Medium Quality',
        subtitle: isStreaming
            ? 'Standard bitrate (~128 kbps) with balanced data usage'
            : 'Standard file size and quality (~128 kbps M4A)',
        icon: Icons.graphic_eq_rounded,
      ),
      (
        quality: YtmAudioQuality.low,
        title: 'Low / Data Saver',
        subtitle: isStreaming
            ? 'Reduced data usage (~64 kbps) for slow connections'
            : 'Smallest file size (~64 kbps)',
        icon: Icons.data_saver_on_rounded,
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                isStreaming
                    ? 'Streaming Audio Quality'
                    : 'Download Audio Quality',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final isSelected = opt.quality == currentQuality;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected
                      ? primaryColor.withValues(alpha: 0.12)
                      : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(opt.icon,
                        color: isSelected ? primaryColor : textSecondary),
                    title: Text(opt.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isSelected ? primaryColor : textPrimary)),
                    subtitle: Text(opt.subtitle,
                        style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: primaryColor)
                        : null,
                    onTap: () {
                      if (isStreaming) {
                        cubit.setStreamingQuality(opt.quality);
                      } else {
                        cubit.setDownloadQuality(opt.quality);
                      }
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showYtmWebOptionsSheet(BuildContext context) {
    final p = context.palette;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Adaptive.sheetConstraints(ctx).maxWidth,
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: Material(
              color: p.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: p.textTertiary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: p.accentContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.language_rounded,
                                color: p.accent, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YouTube Music Web',
                                  style: TextStyle(
                                    color: p.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                  ),
                                ),
                                Text(
                                  'Select a page to open in the in-app browser',
                                  style: TextStyle(
                                      color: p.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ytmWebOptionTile(
                        ctx,
                        icon: Icons.home_rounded,
                        title: 'Home Page',
                        subtitle:
                            'Personalized recommendations, mixes & quick picks',
                        url: 'https://music.youtube.com/?gl=EG&hl=en',
                        p: p,
                      ),
                      _ytmWebOptionTile(
                        ctx,
                        icon: Icons.video_library_rounded,
                        title: 'YouTube Web',
                        subtitle:
                            'Browse all music videos & playlists (no geo-restrictions)',
                        url: 'https://www.youtube.com',
                        p: p,
                      ),
                      _ytmWebOptionTile(
                        ctx,
                        icon: Icons.explore_rounded,
                        title: 'Explore & Charts',
                        subtitle:
                            'Trending songs, top global charts & music videos',
                        url: 'https://music.youtube.com/explore?gl=EG&hl=en',
                        p: p,
                      ),
                      _ytmWebOptionTile(
                        ctx,
                        icon: Icons.library_music_rounded,
                        title: 'Your Library',
                        subtitle:
                            'Saved playlists, albums, songs & subscribed artists',
                        url: 'https://music.youtube.com/library?gl=EG&hl=en',
                        p: p,
                      ),
                      _ytmWebOptionTile(
                        ctx,
                        icon: Icons.favorite_rounded,
                        title: 'Liked Music',
                        subtitle:
                            'Thumbed-up songs synced with your Google account',
                        url: 'https://music.youtube.com/playlist?list=LM&gl=EG&hl=en',
                        p: p,
                      ),
                      _ytmWebOptionTile(
                        ctx,
                        icon: Icons.fiber_new_rounded,
                        title: 'New Releases',
                        subtitle:
                            'Latest album drops, EPs and trending single releases',
                        url: 'https://music.youtube.com/new_releases?gl=EG&hl=en',
                        p: p,
                      ),
                      _ytmWebOptionTile(
                        ctx,
                        icon: Icons.history_rounded,
                        title: 'Listening History',
                        subtitle:
                            'Recently played tracks and stations on your account',
                        url: 'https://music.youtube.com/history?gl=EG&hl=en',
                        p: p,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ytmWebOptionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
    required PulsrPalette p,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.hairline),
          ),
          child: Icon(icon, color: p.accent, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
              color: p.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: p.textSecondary, fontSize: 11.5),
        ),
        trailing: Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: p.textTertiary),
        onTap: () {
          Navigator.pop(context);
          YtmWebLoginSheet.show(
            context,
            initialUrl: url,
            title: title,
            isBrowseMode: true,
          );
        },
      ),
    );
  }

  void _showYtmAccountDisconnectDialog(BuildContext context) {
    final account = getIt<YtmAccountService>();
    final p = context.palette;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surfaceContainerHigh,
        title: Text(context.l10n.ytmAccount,
            style: TextStyle(color: p.textPrimary)),
        content: Text(
          'Connected as: ${account.accountName ?? "User"}\n\nManage your YouTube Music account or disconnect from this device.',
          style: TextStyle(color: p.textSecondary),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              YtmWebLoginSheet.show(
                context,
                isBrowseMode: true,
              );
            },
            icon: Icon(Icons.language_rounded, size: 18, color: p.accent),
            label: Text(context.l10n.openWebPlayer,
                style: TextStyle(color: p.accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel,
                style: TextStyle(color: p.textSecondary)),
          ),
          FilledButton(
            onPressed: () async {
              await account.logout();
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Disconnected from YouTube Music')),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: p.error),
            child: Text(context.l10n.disconnect),
          ),
        ],
      ),
    );
  }

  void _showYtdlpConfigDialog(
      BuildContext context, SettingsCubit cubit, SettingsState state) {
    final urlController = TextEditingController(text: state.ytdlpBackendUrl);
    final tokenController =
        TextEditingController(text: state.ytdlpBackendToken);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return BlocBuilder<SettingsCubit, SettingsState>(
          bloc: cubit,
          builder: (context, liveState) {
            final p = context.palette;
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.dns_rounded, color: p.accent),
                  const SizedBox(width: 10),
                  Text(context.l10n.ytdlpServerConfig),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.ytdlpServerDesc,
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: 'Server Base URL',
                        hintText: 'https://...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tokenController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API Bearer Token',
                        hintText: 'Token',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sync Account Cookies with Backend',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'Allows the backend engine to resolve restricted streams using your logged-in YouTube account. Disabled by default.',
                        style: TextStyle(fontSize: 11, color: p.textSecondary),
                      ),
                      value: liveState.syncCookiesToBackend,
                      onChanged: (val) => cubit.setSyncCookiesToBackend(val),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: liveState.isTestingYtdlpBackend
                              ? null
                              : () {
                                  cubit.setYtdlpBackendUrl(urlController.text);
                                  cubit.setYtdlpBackendToken(
                                      tokenController.text);
                                  cubit.testYtdlpBackend();
                                },
                          icon: liveState.isTestingYtdlpBackend
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.speed_rounded, size: 16),
                          label: const Text('Test Connection'),
                        ),
                        if (liveState.ytdlpBackendCircuitState != null) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: liveState.ytdlpBackendCircuitState ==
                                      'closed'
                                  ? p.success.withValues(alpha: 0.15)
                                  : p.error.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Circuit: ${liveState.ytdlpBackendCircuitState!.toUpperCase()}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: liveState.ytdlpBackendCircuitState ==
                                        'closed'
                                    ? p.success
                                    : p.error,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (liveState.ytdlpBackendStatusMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: p.accentContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          liveState.ytdlpBackendStatusMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: liveState
                                    .ytdlpBackendStatusMessage!
                                    .startsWith('Connected')
                                ? p.success
                                : p.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(context.l10n.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    cubit.setYtdlpBackendUrl(urlController.text);
                    cubit.setYtdlpBackendToken(tokenController.text);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('yt-dlp backend settings saved')),
                    );
                  },
                  child: Text(context.l10n.save),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Proxy-only section used in non-YTM builds (ytmEnabled == false).
class NetworkProxySection extends StatelessWidget {
  final SettingsState state;

  const NetworkProxySection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SettingsSection(
      icon: Icons.vpn_lock_rounded,
      title: context.l10n.networkAndProxy,
      children: [
        SettingsNavTile(
          Icons.vpn_lock_rounded,
          context.l10n.proxySettings,
          state.proxyEnabled
              ? '${state.proxyType.displayName} • ${state.proxyHost.isNotEmpty ? "${state.proxyHost}:${state.proxyPort}" : "Enabled"}'
              : 'Disabled • Tap to configure HTTP / SOCKS5',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.proxyEnabled)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: p.success,
                    shape: BoxShape.circle,
                  ),
                ),
              Icon(Icons.chevron_right_rounded,
                  color: p.textTertiary, size: 20),
            ],
          ),
          onTap: () => context.push('/proxy-settings'),
        ),
      ],
    );
  }
}
