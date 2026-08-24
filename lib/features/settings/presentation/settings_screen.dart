// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/artwork_cache_manager.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/platform_capabilities.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../auth/cubit/auth_state.dart';
import '../../auth/presentation/auth_sheet.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../../player/presentation/widgets/audio_visualizer.dart';
import '../../player/presentation/widgets/equalizer_sheet.dart';
import '../../sheets/sleep_timer_sheet.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';
import 'hidden_folders_screen.dart';
import 'widgets/backup_section.dart';
import 'widgets/battery_optimization_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();

        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760), // readable on tablets
              child: ListView(
                padding: EdgeInsets.only(bottom: 160, top: 8, left: Adaptive.pagePadding(context), right: Adaptive.pagePadding(context)),
                children: [
                  _buildCloudSyncCard(context),
                  _section(context, 'Audio & Playback', [
                    _navTile(
                      context,
                      Icons.equalizer_rounded,
                      'Equalizer & Sound Effects',
                      PlatformCapabilities.hasEqualizer
                          ? '10-band EQ, bass boost, presets'
                          : 'Not available on this platform',
                      onTap: PlatformCapabilities.hasEqualizer
                          ? () => showModalBottomSheet(
                              context: context,
                              useRootNavigator: true,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const EqualizerSheet())
                          : null,
                    ),
                    _divider(p),
                    _navTile(context, Icons.timer_outlined, 'Sleep Timer', 'Auto pause with gentle fade-out',
                        onTap: () => showModalBottomSheet(context: context, useRootNavigator: true, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const SleepTimerSheet())),
                    _divider(p),
                    _switchTile(context, Icons.graphic_eq_rounded, 'Gapless Playback', 'Continuous audio without silence',
                        value: state.gaplessPlayback, onChanged: cubit.setGapless),
                    _divider(p),
                    _switchTile(context, Icons.play_circle_outline_rounded, 'Resume After Interruption', 'Resume after calls & interruptions',
                        value: state.resumeAfterInterruption, onChanged: cubit.setResumeAfterInterruption),
                    _divider(p),
                    _switchTile(context, Icons.waves_rounded, 'Waveform Seek Bar', 'Waveform visualization in the player',
                        value: state.waveformSeekBarEnabled, onChanged: cubit.setWaveformSeekBar),
                    _divider(p),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Crossfade Duration', style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: p.accentContainer, borderRadius: BorderRadius.circular(8)),
                                child: Text('${state.crossfadeSeconds.toStringAsFixed(1)}s',
                                    style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: 12)),
                              ),
                            ],
                          ),
                          Slider(value: state.crossfadeSeconds, min: 0, max: 12, divisions: 24, onChanged: cubit.setCrossfade),
                        ],
                      ),
                    ),
                    const BatteryOptimizationCard(),
                  ]),
                  _section(context, 'Theme & Appearance', [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<AppThemeMode>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            padding: WidgetStatePropertyAll(
                              EdgeInsets.symmetric(horizontal: 2),
                            ),
                          ),
                          segments: [
                            ButtonSegment(
                              value: AppThemeMode.system,
                              label: Text(
                                'Auto',
                                maxLines: 1,
                                softWrap: false,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              icon: const Icon(Icons.brightness_auto_rounded, size: 15),
                            ),
                            ButtonSegment(
                              value: AppThemeMode.light,
                              label: Text(
                                'Light',
                                maxLines: 1,
                                softWrap: false,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              icon: const Icon(Icons.light_mode_rounded, size: 15),
                            ),
                            ButtonSegment(
                              value: AppThemeMode.dark,
                              label: Text(
                                'Dark',
                                maxLines: 1,
                                softWrap: false,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              icon: const Icon(Icons.dark_mode_rounded, size: 15),
                            ),
                            ButtonSegment(
                              value: AppThemeMode.amoled,
                              label: Text(
                                'AMOLED',
                                maxLines: 1,
                                softWrap: false,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              icon: const Icon(Icons.contrast_rounded, size: 15),
                            ),
                          ],
                          selected: {state.themeMode},
                          onSelectionChanged: (sel) => cubit.setThemeMode(sel.first),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Accent Color', style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: AppColors.customAccents.map((color) {
                                final isSelected = state.customAccentColorValue == color.toARGB32();
                                return Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: GestureDetector(
                                    onTap: () => cubit.setCustomAccentColor(color),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected ? p.textPrimary : Colors.transparent,
                                          width: 2.5,
                                        ),
                                        boxShadow: isSelected
                                            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 1)]
                                            : null,
                                      ),
                                      child: isSelected
                                          ? Icon(
                                              Icons.check_rounded,
                                              size: 20,
                                              color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                            )
                                          : null,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _divider(p),
                    _navTile(context, Icons.art_track_rounded, 'Now Playing Theme', _getThemeModeTitle(state.playerThemeMode),
                        onTap: () => _showThemePickerSheet(context, cubit, state.playerThemeMode)),
                    _divider(p),
                    _navTile(context, Icons.graphic_eq_rounded, 'Visualizer Style', _getVisualizerStyleTitle(state.visualizerStyle),
                        onTap: () => _showVisualizerStylePickerSheet(context, cubit, state.visualizerStyle)),
                    _divider(p),
                    _navTile(context, Icons.palette_outlined, 'Color Source', _getColorSourceTitle(state.themeColorSource),
                        onTap: () => _showColorSourcePickerSheet(context, cubit, state.themeColorSource)),
                  ]),
                  _section(context, 'Gestures', [
                    _navTile(context, Icons.swipe_left_rounded, 'Mini Player Swipe Left', _getMiniPlayerSwipeTitle(state.miniPlayerSwipeLeft),
                        onTap: () => _showMiniPlayerSwipePickerSheet(context, cubit, isLeft: true, currentAction: state.miniPlayerSwipeLeft)),
                    _divider(p),
                    _navTile(context, Icons.swipe_right_rounded, 'Mini Player Swipe Right', _getMiniPlayerSwipeTitle(state.miniPlayerSwipeRight),
                        onTap: () => _showMiniPlayerSwipePickerSheet(context, cubit, isLeft: false, currentAction: state.miniPlayerSwipeRight)),
                    _divider(p),
                    _navTile(context, Icons.touch_app_rounded, 'Now Playing Double-Tap', _getNowPlayingDoubleTapTitle(state.nowPlayingDoubleTap),
                        onTap: () => _showNowPlayingDoubleTapPickerSheet(context, cubit, state.nowPlayingDoubleTap)),
                    _divider(p),
                    _navTile(context, Icons.gesture_rounded, 'Artwork Swipe', _getNowPlayingArtworkSwipeTitle(state.nowPlayingArtworkSwipe),
                        onTap: () => _showNowPlayingArtworkSwipePickerSheet(context, cubit, state.nowPlayingArtworkSwipe)),
                  ]),
                  _section(context, 'Library & Scanning', [
                    _navTile(context, Icons.folder_off_rounded, 'Hidden & Excluded Folders',
                        state.autoHideSystemMedia ? 'Auto-filtering voice memos • Custom paths' : 'Manage excluded directories',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HiddenFoldersScreen()))),
                    _divider(p),
                    _navTile(context, Icons.refresh_rounded,
                        state.isScanning ? 'Scanning storage…' : 'Rescan Media Library',
                        state.scanResultCount != null ? 'Last scan: ${state.scanResultCount} tracks' : 'Scan device storage for audio',
                        trailing: state.isScanning
                            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                            : null,
                        onTap: state.isScanning ? () {} : () => cubit.rescanLibrary()),
                    _divider(p),
                    _navTile(context, Icons.filter_list_rounded, 'Short Audio Filter', 'Ignore files under ${state.minDurationSec}s',
                        onTap: () => _showDurationFilterDialog(context, cubit, state.minDurationSec)),
                  ]),
                  if (AppConfig.ytmEnabled)
                    _section(context, 'YouTube Music & Online', [
                      () {
                        final ytmAccount = getIt<YtmAccountService>();
                        return ValueListenableBuilder<bool>(
                          valueListenable: ytmAccount.loginState,
                          builder: (context, isLoggedIn, _) {
                            if (!isLoggedIn) {
                              return _navTile(
                                context,
                                Icons.account_circle_outlined,
                                'Connect YouTube Music Account',
                                'Sign in to auto-sync your Liked Music library',
                                onTap: () async {
                                  final ok = await YtmWebLoginSheet.show(context);
                                  // loginState notifier fires automatically in
                                  // saveSession — no manual setState needed.
                                  if (ok == true && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('YouTube Music connected!'),
                                      ),
                                    );
                                  }
                                },
                              );
                            } else {
                              return _navTile(
                                context,
                                Icons.account_circle_rounded,
                                'YouTube Music Connected',
                                '${ytmAccount.accountName ?? "Connected"} • Tap to manage',
                                onTap: () =>
                                    _showYtmAccountDisconnectDialog(context),
                              );
                            }
                          },
                        );
                      }(),
                      _divider(p),
                      _switchTile(context, Icons.cloud_off_rounded, 'Offline Only Mode',
                          'Disable online features, streaming & web queries',
                          value: state.offlineOnlyMode, onChanged: cubit.setOfflineOnlyMode),
                      if (!state.offlineOnlyMode) ...[
                        _divider(p),
                        _switchTile(context, Icons.wifi_rounded, 'Wi-Fi Only Mode',
                            'Only stream and download when on Wi-Fi',
                            value: state.wifiOnlyMode, onChanged: cubit.setWifiOnlyMode),
                        _divider(p),
                        _navTile(context, Icons.travel_explore_rounded, 'Search YouTube Music',
                            'Search, stream & download songs',
                            onTap: () => context.push('/ytm-search')),
                        _divider(p),
                        _navTile(context, Icons.wifi_tethering_rounded, 'Streaming Quality',
                            _getQualityTitle(state.streamingQuality),
                            onTap: () => _showQualityPickerSheet(context, cubit, isStreaming: true, currentQuality: state.streamingQuality)),
                        _divider(p),
                        _navTile(context, Icons.downloading_rounded, 'Download Quality',
                            _getQualityTitle(state.downloadQuality),
                            onTap: () => _showQualityPickerSheet(context, cubit, isStreaming: false, currentQuality: state.downloadQuality)),
                      ],
                    ]),
                  _section(context, 'Storage & Cache', [
                    const _CacheSection(),
                  ]),
                  _section(context, 'Privacy & Data', [
                    const BackupSection(),
                    _divider(p),
                    _navTile(context, Icons.security_rounded, 'Privacy Guarantee', '100% offline. Zero telemetry, zero tracking.', onTap: () {}),
                  ]),
                  _section(context, 'About', [
                    _navTile(context, Icons.info_outline_rounded, 'Pulsr Music', 'Version 1.0.0 • Pure Offline Sound', onTap: () {}),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- premium section + tile helpers ----------
  Widget _section(BuildContext context, String title, List<Widget> children) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 0, 10),
            child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.textTertiary)),
          ),
          Material(
            color: p.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: p.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _divider(PulsrPalette p) => Divider(height: 1, indent: 68, color: p.hairline);

  Widget _iconBox(BuildContext context, IconData icon) {
    final p = context.palette;
    return Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
        color: p.accentContainer,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: p.accent, size: 19),
    );
  }

  Widget _navTile(BuildContext context, IconData icon, String title, String subtitle,
      {Widget? trailing, VoidCallback? onTap}) {
    final p = context.palette;
    return ListTile(
      leading: _iconBox(context, icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: p.textSecondary, fontSize: 12)),
      trailing: trailing ?? Icon(Icons.chevron_right_rounded, color: p.textTertiary, size: 20),
      onTap: onTap,
    );
  }

  Widget _switchTile(BuildContext context, IconData icon, String title, String subtitle,
      {required bool value, required ValueChanged<bool> onChanged}) {
    final p = context.palette;
    return ListTile(
      leading: _iconBox(context, icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: p.textSecondary, fontSize: 12)),
      trailing: Switch.adaptive(value: value, activeTrackColor: p.accent, activeThumbColor: Colors.white, onChanged: onChanged),
    );
  }

  void _showDurationFilterDialog(BuildContext context, SettingsCubit cubit, int currentSec) {
    int selected = currentSec;
    final primaryColor = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Filter Short Audio'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Exclude tracks under $selected seconds (filters voice notes):'),
              const SizedBox(height: 12),
              Slider(
                value: selected.toDouble(),
                min: 0,
                max: 120,
                divisions: 12,
                activeColor: primaryColor,
                onChanged: (val) {
                  setDialogState(() => selected = val.toInt());
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              cubit.setMinDuration(selected);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _getThemeModeTitle(PlayerThemeMode mode) {
    switch (mode) {
      case PlayerThemeMode.classic:
        return 'Classic Standard';
      case PlayerThemeMode.card:
        return 'Card Glass Overlay';
      case PlayerThemeMode.circle:
        return 'Vinyl Circle (Spinning)';
      case PlayerThemeMode.minimal:
        return 'Minimalist Waveform';
    }
  }

  String _getVisualizerStyleTitle(VisualizerStyle style) {
    switch (style) {
      case VisualizerStyle.off:
        return 'Disabled';
      case VisualizerStyle.bar:
        return 'Bar (Classic Frequency Spectrum)';
      case VisualizerStyle.wave:
        return 'Wave (Smooth Line Spectrum)';
      case VisualizerStyle.circular:
        return 'Circular (Radial Spectrum)';
    }
  }

  void _showThemePickerSheet(
    BuildContext context,
    SettingsCubit cubit,
    PlayerThemeMode currentMode,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor = Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? context.palette.textSecondary;

    final themes = [
      (
        mode: PlayerThemeMode.classic,
        title: 'Classic Standard',
        subtitle: 'Traditional high-definition layout with ambient glow',
        icon: Icons.square_outlined,
      ),
      (
        mode: PlayerThemeMode.card,
        title: 'Card Glass Overlay',
        subtitle: 'Full-bleed background artwork with frosted glass controls',
        icon: Icons.layers_rounded,
      ),
      (
        mode: PlayerThemeMode.circle,
        title: 'Vinyl Circle',
        subtitle: 'Centered circular artwork with continuous spinning animation',
        icon: Icons.album_rounded,
      ),
      (
        mode: PlayerThemeMode.minimal,
        title: 'Minimalist Waveform',
        subtitle: 'Spacious studio focus on dynamic audio waveform visualizer',
        icon: Icons.graphic_eq_rounded,
      ),
    ];

    showModalBottomSheet(
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
                'Select Player Theme',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...themes.map((t) {
              final isSelected = t.mode == currentMode;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      t.icon,
                      color: isSelected ? primaryColor : textSecondary,
                    ),
                    title: Text(
                      t.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isSelected ? primaryColor : textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      t.subtitle,
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: primaryColor)
                        : null,
                    onTap: () {
                      cubit.setPlayerThemeMode(t.mode);
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

  String _getColorSourceTitle(ThemeColorSource source) {
    switch (source) {
      case ThemeColorSource.system:
        return 'Material You (Wallpaper)';
      case ThemeColorSource.artwork:
        return 'Album Artwork';
      case ThemeColorSource.custom:
        return 'Custom Accent';
    }
  }

  void _showColorSourcePickerSheet(
    BuildContext context,
    SettingsCubit cubit,
    ThemeColorSource currentSource,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor = Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? context.palette.textSecondary;

    final sources = [
      (
        source: ThemeColorSource.system,
        title: 'Material You (Wallpaper)',
        subtitle: 'Follow the system wallpaper palette on Android 12+ • falls back to album art on older devices',
        icon: Icons.wallpaper_rounded,
      ),
      (
        source: ThemeColorSource.artwork,
        title: 'Album Artwork',
        subtitle: 'Adapt colors from the current track\'s album art (changes per song)',
        icon: Icons.album_rounded,
      ),
      (
        source: ThemeColorSource.custom,
        title: 'Custom Accent',
        subtitle: 'Use the fixed accent color you pick above',
        icon: Icons.color_lens_rounded,
      ),
    ];

    showModalBottomSheet(
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
                'App Color Source',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...sources.map((s) {
              final isSelected = s.source == currentSource;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      s.icon,
                      color: isSelected ? primaryColor : textSecondary,
                    ),
                    title: Text(
                      s.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isSelected ? primaryColor : textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      s.subtitle,
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: primaryColor)
                        : null,
                    onTap: () {
                      cubit.setThemeColorSource(s.source);
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

  void _showVisualizerStylePickerSheet(
    BuildContext context,
    SettingsCubit cubit,
    VisualizerStyle currentStyle,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor = Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? context.palette.textSecondary;

    final styles = [
      (
        style: VisualizerStyle.bar,
        title: 'BAR',
        subtitle: 'Classic vertical frequency bars with smooth height animation',
        icon: Icons.bar_chart_rounded,
      ),
      (
        style: VisualizerStyle.wave,
        title: 'WAVE',
        subtitle: 'Smooth continuous Bézier waveform line with ambient gradient fill',
        icon: Icons.waves_rounded,
      ),
      (
        style: VisualizerStyle.circular,
        title: 'CIRCULAR',
        subtitle: 'Futuristic radial frequency bars surrounding album centerpiece',
        icon: Icons.motion_photos_on_rounded,
      ),
      (
        style: VisualizerStyle.off,
        title: 'OFF',
        subtitle: 'Disable audio visualizer spectrum animation',
        icon: Icons.align_vertical_bottom_rounded,
      ),
    ];

    showModalBottomSheet(
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
                'Audio Visualizer Style',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...styles.map((s) {
              final isSelected = s.style == currentStyle;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      s.icon,
                      color: isSelected ? primaryColor : textSecondary,
                    ),
                    title: Text(
                      s.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isSelected ? primaryColor : textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      s.subtitle,
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: primaryColor)
                        : null,
                    onTap: () {
                      cubit.setVisualizerStyle(s.style);
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

  String _getMiniPlayerSwipeTitle(MiniPlayerSwipeAction action) {
    switch (action) {
      case MiniPlayerSwipeAction.next:
        return 'Next Track';
      case MiniPlayerSwipeAction.prev:
        return 'Previous Track';
      case MiniPlayerSwipeAction.volume:
        return 'Adjust Volume';
      case MiniPlayerSwipeAction.none:
        return 'Disabled';
    }
  }

  String _getNowPlayingDoubleTapTitle(NowPlayingDoubleTapAction action) {
    switch (action) {
      case NowPlayingDoubleTapAction.toggleFavorite:
        return 'Toggle Favorite';
      case NowPlayingDoubleTapAction.toggleLyrics:
        return 'Toggle Lyrics';
      case NowPlayingDoubleTapAction.none:
        return 'Disabled';
    }
  }

  String _getNowPlayingArtworkSwipeTitle(NowPlayingArtworkSwipeAction action) {
    switch (action) {
      case NowPlayingArtworkSwipeAction.nextPrev:
        return 'Next / Previous Track';
      case NowPlayingArtworkSwipeAction.none:
        return 'Disabled';
    }
  }

  void _showMiniPlayerSwipePickerSheet(
    BuildContext context,
    SettingsCubit cubit, {
    required bool isLeft,
    required MiniPlayerSwipeAction currentAction,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor = Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? context.palette.textSecondary;

    final options = [
      (
        action: MiniPlayerSwipeAction.next,
        title: 'Next Track',
        subtitle: 'Skip to the next song in the queue',
        icon: Icons.skip_next_rounded,
      ),
      (
        action: MiniPlayerSwipeAction.prev,
        title: 'Previous Track',
        subtitle: 'Skip to the previous song or restart track',
        icon: Icons.skip_previous_rounded,
      ),
      (
        action: MiniPlayerSwipeAction.volume,
        title: 'Adjust Volume',
        subtitle: isLeft ? 'Lower playback volume' : 'Raise playback volume',
        icon: isLeft ? Icons.volume_down_rounded : Icons.volume_up_rounded,
      ),
      (
        action: MiniPlayerSwipeAction.none,
        title: 'Disabled',
        subtitle: 'Ignore swipe gesture',
        icon: Icons.block_rounded,
      ),
    ];

    showModalBottomSheet(
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
                isLeft ? 'MiniPlayer Swipe Left Action' : 'MiniPlayer Swipe Right Action',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final isSelected = opt.action == currentAction;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(opt.icon, color: isSelected ? primaryColor : textSecondary),
                    title: Text(opt.title, style: TextStyle(fontWeight: FontWeight.w700, color: isSelected ? primaryColor : textPrimary)),
                    subtitle: Text(opt.subtitle, style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: isSelected ? Icon(Icons.check_circle_rounded, color: primaryColor) : null,
                    onTap: () {
                      if (isLeft) {
                        cubit.setMiniPlayerSwipeLeft(opt.action);
                      } else {
                        cubit.setMiniPlayerSwipeRight(opt.action);
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

  void _showNowPlayingDoubleTapPickerSheet(
    BuildContext context,
    SettingsCubit cubit,
    NowPlayingDoubleTapAction currentAction,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor = Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? context.palette.textSecondary;

    final options = [
      (
        action: NowPlayingDoubleTapAction.toggleFavorite,
        title: 'Toggle Favorite',
        subtitle: 'Add or remove active song from favorites',
        icon: Icons.favorite_rounded,
      ),
      (
        action: NowPlayingDoubleTapAction.toggleLyrics,
        title: 'Toggle Lyrics',
        subtitle: 'Show or hide synchronized lyrics overlay',
        icon: Icons.lyrics_rounded,
      ),
      (
        action: NowPlayingDoubleTapAction.none,
        title: 'Disabled',
        subtitle: 'Ignore double-tap gesture',
        icon: Icons.block_rounded,
      ),
    ];

    showModalBottomSheet(
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
                'Now Playing Double-Tap Action',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final isSelected = opt.action == currentAction;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(opt.icon, color: isSelected ? primaryColor : textSecondary),
                    title: Text(opt.title, style: TextStyle(fontWeight: FontWeight.w700, color: isSelected ? primaryColor : textPrimary)),
                    subtitle: Text(opt.subtitle, style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: isSelected ? Icon(Icons.check_circle_rounded, color: primaryColor) : null,
                    onTap: () {
                      cubit.setNowPlayingDoubleTap(opt.action);
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

  void _showNowPlayingArtworkSwipePickerSheet(
    BuildContext context,
    SettingsCubit cubit,
    NowPlayingArtworkSwipeAction currentAction,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor = Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? context.palette.textSecondary;

    final options = [
      (
        action: NowPlayingArtworkSwipeAction.nextPrev,
        title: 'Next / Previous Track',
        subtitle: 'Swipe left for next track, swipe right for previous track',
        icon: Icons.swipe_rounded,
      ),
      (
        action: NowPlayingArtworkSwipeAction.none,
        title: 'Disabled',
        subtitle: 'Ignore horizontal swipe on album artwork',
        icon: Icons.block_rounded,
      ),
    ];

    showModalBottomSheet(
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
                'Now Playing Artwork Swipe',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final isSelected = opt.action == currentAction;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(opt.icon, color: isSelected ? primaryColor : textSecondary),
                    title: Text(opt.title, style: TextStyle(fontWeight: FontWeight.w700, color: isSelected ? primaryColor : textPrimary)),
                    subtitle: Text(opt.subtitle, style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: isSelected ? Icon(Icons.check_circle_rounded, color: primaryColor) : null,
                    onTap: () {
                      cubit.setNowPlayingArtworkSwipe(opt.action);
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

  void _showQualityPickerSheet(
    BuildContext context,
    SettingsCubit cubit, {
    required bool isStreaming,
    required YtmAudioQuality currentQuality,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor = Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? context.palette.textSecondary;

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

    showModalBottomSheet(
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
                isStreaming ? 'Streaming Audio Quality' : 'Download Audio Quality',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            ...options.map((opt) {
              final isSelected = opt.quality == currentQuality;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? primaryColor : outlineColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(opt.icon, color: isSelected ? primaryColor : textSecondary),
                    title: Text(opt.title, style: TextStyle(fontWeight: FontWeight.w700, color: isSelected ? primaryColor : textPrimary)),
                    subtitle: Text(opt.subtitle, style: TextStyle(fontSize: 12, color: textSecondary)),
                    trailing: isSelected ? Icon(Icons.check_circle_rounded, color: primaryColor) : null,
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

  Widget _buildCloudSyncCard(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        final authCubit = context.read<AuthCubit>();
        final user = state.user;
        final isSyncing = state.syncStatus == SyncStatus.syncing;

        String syncSubtitle = 'Sign in to back up favorites & playlists';
        if (user != null) {
          if (state.lastSyncedAt != null) {
            final diff = DateTime.now().difference(state.lastSyncedAt!);
            if (diff.inMinutes < 1) {
              syncSubtitle = 'Last synced: Just now';
            } else if (diff.inHours < 1) {
              syncSubtitle = 'Last synced: ${diff.inMinutes}m ago';
            } else {
              syncSubtitle = 'Last synced: ${diff.inHours}h ago';
            }
          } else {
            syncSubtitle = 'Connected • Ready to sync';
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 20, top: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: user != null ? p.accent.withValues(alpha: 0.15) : p.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.hairline),
                    ),
                    child: user?.photoURL != null
                        ? ClipOval(
                            child: Image.network(
                              user!.photoURL!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, color: p.accent),
                            ),
                          )
                        : Icon(user != null ? Icons.person_rounded : Icons.cloud_outlined, color: p.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? user?.email ?? 'Cloud Sync & Backup',
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          syncSubtitle,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (user == null) ...[
                    FilledButton(
                      onPressed: () => AuthSheet.show(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: 'Sync Now',
                      icon: isSyncing
                          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                          : Icon(Icons.sync_rounded, color: p.accent),
                      onPressed: isSyncing ? null : () => authCubit.syncNow(),
                    ),
                    IconButton(
                      tooltip: 'Sign Out',
                      icon: Icon(Icons.logout_rounded, color: p.textTertiary, size: 20),
                      onPressed: () => authCubit.signOut(),
                    ),
                  ],
                ],
              ),
              if (state.syncError != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.syncError!,
                  style: TextStyle(color: p.error, fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showYtmAccountDisconnectDialog(BuildContext context) {
    final account = getIt<YtmAccountService>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('YouTube Music Account'),
        content: Text(
          'Connected as: ${account.accountName ?? "User"}\n\nDo you want to disconnect your YouTube Music account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await account.logout();
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Disconnected from YouTube Music')),
                );
              }
            },
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }
}

class _CacheSection extends StatefulWidget {
  const _CacheSection();

  @override
  State<_CacheSection> createState() => _CacheSectionState();
}

class _CacheSectionState extends State<_CacheSection> {
  int _cacheSizeBytes = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  Future<void> _refreshCacheSize() async {
    final size = await ArtworkCacheManager().getDiskCacheSizeBytes();
    if (mounted) {
      setState(() {
        _cacheSizeBytes = size;
        _isLoading = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final manager = ArtworkCacheManager();
    final maxMb = manager.maxCacheSizeMb;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.photo_size_select_actual_rounded, color: p.accent, size: 22),
          ),
          title: Text(
            'Artwork & Media Cache',
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          subtitle: Text(
            _isLoading ? 'Calculating…' : '${_formatSize(_cacheSizeBytes)} used of $maxMb MB max',
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
          trailing: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: p.error,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Clear'),
            onPressed: () async {
              await manager.clearAllCache();
              await _refreshCacheSize();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Artwork cache cleared successfully')),
                );
              }
            },
          ),
        ),
        Divider(height: 1, color: p.hairline),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: p.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.disc_full_rounded, color: p.textSecondary, size: 22),
          ),
          title: Text(
            'Maximum Cache Limit',
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          subtitle: Text(
            '$maxMb MB • Auto-evicts oldest artworks when full',
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
          trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: p.textTertiary),
          onTap: () => _showMaxCacheLimitPicker(context, manager),
        ),
      ],
    );
  }

  void _showMaxCacheLimitPicker(BuildContext context, ArtworkCacheManager manager) {
    final p = context.palette;
    final options = [50, 100, 250, 500];

    showModalBottomSheet(
      context: context,
      backgroundColor: p.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Maximum Cache Size',
                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 12),
              for (final mb in options)
                ListTile(
                  leading: Icon(
                    manager.maxCacheSizeMb == mb ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: manager.maxCacheSizeMb == mb ? p.accent : p.textTertiary,
                  ),
                  title: Text(
                    '$mb MB',
                    style: TextStyle(
                      color: manager.maxCacheSizeMb == mb ? p.accent : p.textPrimary,
                      fontWeight: manager.maxCacheSizeMb == mb ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  onTap: () async {
                    await manager.setMaxCacheSizeMb(mb);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
