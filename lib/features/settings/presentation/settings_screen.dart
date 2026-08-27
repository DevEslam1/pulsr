// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/di/injection.dart';
import '../../../data/db/app_database.dart';
import '../../../core/services/artwork_cache_manager.dart';
import '../../../core/services/scrobbler_service.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_cache_manager.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/utils/platform_capabilities.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../auth/cubit/auth_state.dart';
import '../../auth/presentation/auth_sheet.dart';
import '../../auth/presentation/ytm_web_login_sheet.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/presentation/widgets/audio_quality_sheet.dart';
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
          appBar: AppBar(title: Text(context.l10n.settings)),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760), // readable on tablets
              child: ListView(
                padding: EdgeInsets.only(bottom: 160, top: 8, left: Adaptive.pagePadding(context), right: Adaptive.pagePadding(context)),
                children: [
                  _buildCloudSyncCard(context),
                  _section(context, context.l10n.audioAndPlayback, [
                    _navTile(
                      context,
                      Icons.equalizer_rounded,
                      context.l10n.equalizerAndSoundEffects,
                      PlatformCapabilities.hasEqualizer
                          ? context.l10n.equalizerSubtitle
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
                    _navTile(context, Icons.timer_outlined, context.l10n.sleepTimer, context.l10n.sleepTimerSubtitle,
                        onTap: () => showModalBottomSheet(context: context, useRootNavigator: true, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const SleepTimerSheet())),
                    _divider(p),
                    _switchTile(context, Icons.graphic_eq_rounded, context.l10n.gaplessPlayback, context.l10n.gaplessSubtitle,
                        value: state.gaplessPlayback, onChanged: cubit.setGapless),
                    _divider(p),
                    _switchTile(context, Icons.play_circle_outline_rounded, context.l10n.resumeAfterInterruption, context.l10n.resumeAfterInterruptionSubtitle,
                        value: state.resumeAfterInterruption, onChanged: cubit.setResumeAfterInterruption),
                    _divider(p),
                    _switchTile(context, Icons.waves_rounded, context.l10n.waveformSeekBar, context.l10n.waveformSeekBarSubtitle,
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
                              Text(context.l10n.crossfade, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
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
                    _divider(p),
                    // Audiophile & Hi-Res Output Card & Controls
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                      child: Material(
                        color: p.surfaceContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            final playerState = context.read<PlayerCubit>().state;
                            final currentSong = playerState.currentSong ??
                                const SongsTableData(
                                  id: 0,
                                  title: 'Hardware Audio Output',
                                  artist: 'Master Audio Engine',
                                  album: 'Internal / USB DAC',
                                  durationMs: 0,
                                  path: '',
                                  source: SongSource.local,
                                  isFavorite: false,
                                  isMissing: false,
                                  playCount: 0,
                                  lastPositionMs: 0,
                                );
                            AudioQualitySheet.show(context, currentSong, p.accent);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: state.currentOutputDevice?.isUsbDac == true
                                    ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                                    : p.hairline,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      state.currentOutputDevice?.isUsbDac == true
                                          ? Icons.usb_rounded
                                          : Icons.headphones_rounded,
                                      color: state.currentOutputDevice?.isUsbDac == true
                                          ? const Color(0xFFFFD700)
                                          : p.accent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        state.currentOutputDevice?.deviceName ?? 'Audio Output Device',
                                        style: TextStyle(
                                          color: p.textPrimary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (state.currentOutputDevice?.isBitPerfectActive == true)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
                                        ),
                                        child: const Text(
                                          'BIT-PERFECT',
                                          style: TextStyle(
                                            color: Color(0xFFFFD700),
                                            fontWeight: FontWeight.w900,
                                            fontSize: 9,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 6),
                                    Icon(Icons.tune_rounded, size: 16, color: p.textSecondary),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap to configure Output Device • Sample Rate (${(state.currentOutputDevice?.sampleRate ?? 44100) ~/ 1000} kHz) • Bit Depth (${state.currentOutputDevice?.bitDepth ?? 16}-bit)',
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    _switchTile(
                      context,
                      Icons.album_rounded,
                      'Bit-Perfect USB Pass-Through',
                      'Direct hardware streaming to USB DACs (bypasses Android OS resampler on Android 14+)',
                      value: state.bitPerfectOutput,
                      onChanged: cubit.setBitPerfectOutput,
                    ),
                    _divider(p),
                    _switchTile(
                      context,
                      Icons.tune_rounded,
                      'Bypass DSP in Bit-Perfect Mode',
                      'Bypasses Equalizer and virtualizer for an uncolored, pure audio bitstream to the DAC',
                      value: state.bypassDspOnBitPerfect,
                      onChanged: cubit.setBypassDspOnBitPerfect,
                    ),
                    _divider(p),
                    // ReplayGain / Loudness Normalization Suite
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.volume_up_rounded, color: p.accent, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ReplayGain Loudness Normalization',
                                      style: TextStyle(
                                        color: p.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'EBU R128 automatic volume leveling across diverse track masters',
                                      style: TextStyle(
                                        color: p.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ReplayGainMode>(
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                padding: WidgetStatePropertyAll(
                                  EdgeInsets.symmetric(horizontal: 4),
                                ),
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: ReplayGainMode.off,
                                  label: Text('Off', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                                ButtonSegment(
                                  value: ReplayGainMode.track,
                                  label: Text('Track', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                                ButtonSegment(
                                  value: ReplayGainMode.album,
                                  label: Text('Album', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                                ButtonSegment(
                                  value: ReplayGainMode.auto,
                                  label: Text('Auto', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                              ],
                              selected: {state.replayGainMode},
                              onSelectionChanged: (selected) {
                                if (selected.isNotEmpty) {
                                  cubit.setReplayGainMode(selected.first);
                                }
                              },
                            ),
                          ),
                          if (state.replayGainMode != ReplayGainMode.off) ...[
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Preamp (With RG tag)',
                                  style: TextStyle(color: p.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${state.replayGainPreampWithRg >= 0 ? '+' : ''}${state.replayGainPreampWithRg.toStringAsFixed(1)} dB',
                                  style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            Slider(
                              value: state.replayGainPreampWithRg,
                              min: -12.0,
                              max: 12.0,
                              divisions: 48,
                              onChanged: cubit.setReplayGainPreampWithRg,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Preamp (Without RG tag fallback)',
                                  style: TextStyle(color: p.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${state.replayGainPreampWithoutRg >= 0 ? '+' : ''}${state.replayGainPreampWithoutRg.toStringAsFixed(1)} dB',
                                  style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            Slider(
                              value: state.replayGainPreampWithoutRg,
                              min: -12.0,
                              max: 12.0,
                              divisions: 48,
                              onChanged: cubit.setReplayGainPreampWithoutRg,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const BatteryOptimizationCard(),
                  ]),
                  _section(context, context.l10n.themeAndAppearance, [
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
                                context.l10n.systemDefault,
                                maxLines: 1,
                                softWrap: false,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              icon: const Icon(Icons.brightness_auto_rounded, size: 15),
                            ),
                            ButtonSegment(
                              value: AppThemeMode.light,
                              label: Text(
                                context.l10n.themeLight,
                                maxLines: 1,
                                softWrap: false,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              icon: const Icon(Icons.light_mode_rounded, size: 15),
                            ),
                            ButtonSegment(
                              value: AppThemeMode.dark,
                              label: Text(
                                context.l10n.themeDark,
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
                          Text(context.l10n.accentColor, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
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
                    _navTile(context, Icons.art_track_rounded, context.l10n.nowPlayingTheme, _getThemeModeTitle(state.playerThemeMode),
                        onTap: () => _showThemePickerSheet(context, cubit, state.playerThemeMode)),
                    _divider(p),
                    _navTile(context, Icons.graphic_eq_rounded, context.l10n.visualizerStyle, _getVisualizerStyleTitle(state.visualizerStyle),
                        onTap: () => _showVisualizerStylePickerSheet(context, cubit, state.visualizerStyle)),
                    _divider(p),
                    _navTile(context, Icons.palette_outlined, context.l10n.colorSource, _getColorSourceTitle(state.themeColorSource),
                        onTap: () => _showColorSourcePickerSheet(context, cubit, state.themeColorSource)),
                    _divider(p),
                    _navTile(context, Icons.language_rounded, context.l10n.language, _getLanguageTitle(state.languageCode, context.l10n),
                        onTap: () => _showLanguagePickerSheet(context, cubit, state.languageCode)),
                  ]),
                  _section(context, context.l10n.gestures, [
                    _navTile(context, Icons.swipe_left_rounded, context.l10n.miniPlayerSwipeLeft, _getMiniPlayerSwipeTitle(state.miniPlayerSwipeLeft),
                        onTap: () => _showMiniPlayerSwipePickerSheet(context, cubit, isLeft: true, currentAction: state.miniPlayerSwipeLeft)),
                    _divider(p),
                    _navTile(context, Icons.swipe_right_rounded, context.l10n.miniPlayerSwipeRight, _getMiniPlayerSwipeTitle(state.miniPlayerSwipeRight),
                        onTap: () => _showMiniPlayerSwipePickerSheet(context, cubit, isLeft: false, currentAction: state.miniPlayerSwipeRight)),
                    _divider(p),
                    _navTile(context, Icons.touch_app_rounded, context.l10n.nowPlayingDoubleTap, _getNowPlayingDoubleTapTitle(state.nowPlayingDoubleTap),
                        onTap: () => _showNowPlayingDoubleTapPickerSheet(context, cubit, state.nowPlayingDoubleTap)),
                    _divider(p),
                    _navTile(context, Icons.gesture_rounded, context.l10n.artworkSwipe, _getNowPlayingArtworkSwipeTitle(state.nowPlayingArtworkSwipe),
                        onTap: () => _showNowPlayingArtworkSwipePickerSheet(context, cubit, state.nowPlayingArtworkSwipe)),
                  ]),
                  _section(context, context.l10n.libraryAndScanning, [
                    _navTile(context, Icons.folder_off_rounded, context.l10n.hiddenAndExcludedFolders,
                        state.autoHideSystemMedia ? 'Auto-filtering voice memos • Custom paths' : 'Manage excluded directories',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HiddenFoldersScreen()))),
                    _divider(p),
                    _navTile(context, Icons.refresh_rounded,
                        state.isScanning ? 'Scanning storage…' : context.l10n.rescanLibrary,
                        state.scanResultCount != null ? 'Last scan: ${state.scanResultCount} tracks' : 'Scan device storage for audio',
                        trailing: state.isScanning
                            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                            : null,
                        onTap: state.isScanning ? () {} : () => cubit.rescanLibrary()),
                    _divider(p),
                    _navTile(context, Icons.filter_list_rounded, context.l10n.shortAudioFilter, context.l10n.ignoreFilesUnder(state.minDurationSec),
                        onTap: () => _showDurationFilterDialog(context, cubit, state.minDurationSec)),
                  ]),
                  if (AppConfig.ytmEnabled)
                    _section(context, context.l10n.youtubeMusicAndOnline, [
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
                                '${ytmAccount.accountName ?? "Connected"} • Tap to manage',
                                onTap: () =>
                                    _showYtmAccountDisconnectDialog(context),
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
                        onTap: () => _showYtmWebOptionsSheet(context),
                      ),
                      _divider(p),
                      _switchTile(context, Icons.cloud_off_rounded, context.l10n.offlineOnlyMode,
                          context.l10n.offlineOnlySubtitle,
                          value: state.offlineOnlyMode, onChanged: cubit.setOfflineOnlyMode),
                      if (!state.offlineOnlyMode) ...[
                        _divider(p),
                        _switchTile(context, Icons.wifi_rounded, context.l10n.wifiOnlyMode,
                            context.l10n.wifiOnlySubtitle,
                            value: state.wifiOnlyMode, onChanged: cubit.setWifiOnlyMode),
                        _divider(p),
                        _navTile(context, Icons.travel_explore_rounded, context.l10n.searchYtm,
                            context.l10n.searchYtmSubtitle,
                            onTap: () => context.push('/ytm-search')),
                        _divider(p),
                        _navTile(context, Icons.wifi_tethering_rounded, context.l10n.streamingQuality,
                            _getQualityTitle(state.streamingQuality),
                            onTap: () => _showQualityPickerSheet(context, cubit, isStreaming: true, currentQuality: state.streamingQuality)),
                        _divider(p),
                        _navTile(context, Icons.downloading_rounded, context.l10n.downloadQuality,
                            _getQualityTitle(state.downloadQuality),
                            onTap: () => _showQualityPickerSheet(context, cubit, isStreaming: false, currentQuality: state.downloadQuality)),
                        _divider(p),
                        _navTile(
                          context,
                          Icons.precision_manufacturing_rounded,
                          context.l10n.extractionEngine,
                          _getExtractorEngineTitle(state.extractorEngine),
                          onTap: () => _showExtractorEnginePickerSheet(context, cubit, currentEngine: state.extractorEngine),
                        ),
                        if (state.extractorEngine != ExtractorEngine.onDevice) ...[
                          _divider(p),
                          _navTile(
                            context,
                            Icons.dns_rounded,
                            context.l10n.ytdlpConfig,
                            state.ytdlpBackendUrl,
                            onTap: () => _showYtdlpConfigDialog(context, cubit, state),
                          ),
                        ],
                        _divider(p),
                        _navTile(
                          context,
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
                              Icon(Icons.chevron_right_rounded, color: p.textTertiary, size: 20),
                            ],
                          ),
                          onTap: () => context.push('/proxy-settings'),
                        ),
                      ],
                    ]),
                  if (!AppConfig.ytmEnabled)
                    _section(context, context.l10n.networkAndProxy, [
                      _navTile(
                        context,
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
                            Icon(Icons.chevron_right_rounded, color: p.textTertiary, size: 20),
                          ],
                        ),
                        onTap: () => context.push('/proxy-settings'),
                      ),
                    ]),
                  _section(context, context.l10n.storageAndCache, [
                    const _CacheSection(),
                  ]),
                  _section(context, context.l10n.privacyAndData, [
                    const BackupSection(),
                    _divider(p),
                    _navTile(
                      context,
                      Icons.equalizer_outlined,
                      'Scrobbling (Last.fm & ListenBrainz)',
                      'Direct API scrobbling and Now Playing notifications',
                      onTap: () => _showScrobblerSettingsModal(context),
                    ),
                    _divider(p),
                    _navTile(context, Icons.security_rounded, context.l10n.privacyGuarantee, context.l10n.privacyGuaranteeSubtitle, onTap: () {}),
                  ]),
                  _section(context, context.l10n.about, [
                    _navTile(context, Icons.info_outline_rounded, context.l10n.appTitle, context.l10n.aboutAppSubtitle, onTap: () {}),
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
        title: Text(context.l10n.minDuration),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.cancel)),
          ElevatedButton(
            onPressed: () {
              cubit.setMinDuration(selected);
              Navigator.pop(ctx);
            },
            child: Text(context.l10n.save),
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
      case PlayerThemeMode.vinyl:
        return 'Vinyl Turntable Studio';
      case PlayerThemeMode.cassette:
        return 'Retro Cassette Deck';
      case PlayerThemeMode.waveform:
        return 'Full-Bleed Waveform';
      case PlayerThemeMode.lyricsFocus:
        return 'Karaoke Lyrics Immersion';
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
      case VisualizerStyle.particles:
        return 'Particles (Audio Field)';
      case VisualizerStyle.terrain3D:
        return '3D Terrain (Wireframe Mountain)';
      case VisualizerStyle.albumArtReactive:
        return 'Album Art Reactive Glow';
      case VisualizerStyle.custom:
        return 'Custom JSON Visualizer';
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
      (
        mode: PlayerThemeMode.vinyl,
        title: 'Vinyl Turntable Studio',
        subtitle: 'True vinyl record with realistic grooves, center label & tonearm',
        icon: Icons.album_rounded,
      ),
      (
        mode: PlayerThemeMode.cassette,
        title: 'Retro Cassette Deck',
        subtitle: 'Vintage cassette tape with spinning spools & magnetic tape counter',
        icon: Icons.radio_rounded,
      ),
      (
        mode: PlayerThemeMode.waveform,
        title: 'Full-Bleed Waveform',
        subtitle: 'Full screen audio-reactive glowing waveform visualizer backdrop',
        icon: Icons.waves_rounded,
      ),
      (
        mode: PlayerThemeMode.lyricsFocus,
        title: 'Karaoke Lyrics Immersion',
        subtitle: 'Magnified synchronized lyrics-first karaoke player interface',
        icon: Icons.mic_rounded,
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

  String _getLanguageTitle(String code, dynamic l10n) {
    switch (code) {
      case 'ar':
        return 'العربية (Arabic)';
      case 'es':
        return 'Español (Spanish)';
      case 'en':
        return 'English';
      default:
        return 'System Default';
    }
  }

  void _showLanguagePickerSheet(
    BuildContext context,
    SettingsCubit cubit,
    String currentCode,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final cardColor = Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? context.palette.textSecondary;

    final languages = [
      (code: 'system', name: 'System Default', nativeName: 'الافتراضي للنظام / Predeterminado', flag: Icons.settings_suggest_rounded),
      (code: 'en', name: 'English', nativeName: 'English (US/UK)', flag: Icons.language_rounded),
      (code: 'ar', name: 'العربية', nativeName: 'Arabic (RTL)', flag: Icons.translate_rounded),
      (code: 'es', name: 'Español', nativeName: 'Spanish', flag: Icons.public_rounded),
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
                context.l10n.appLanguage,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...languages.map((lang) {
              final isSelected = lang.code == currentCode;
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
                      lang.flag,
                      color: isSelected ? primaryColor : textSecondary,
                    ),
                    title: Text(
                      lang.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isSelected ? primaryColor : textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      lang.nativeName,
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: primaryColor)
                        : null,
                    onTap: () {
                      cubit.setLanguage(lang.code);
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
    final cardColor = Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? context.palette.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? context.palette.textSecondary;

    final options = [
      (
        engine: ExtractorEngine.auto,
        title: 'Auto (Recommended)',
        subtitle: 'Uses remote yt-dlp backend with automatic fallback to on-device extractor',
        icon: Icons.auto_mode_rounded,
      ),
      (
        engine: ExtractorEngine.remoteYtdlp,
        title: 'Remote yt-dlp Backend',
        subtitle: 'Resolves via cloud server with proxy pool & cookie rotation to prevent bot bans',
        icon: Icons.cloud_done_rounded,
      ),
      (
        engine: ExtractorEngine.onDevice,
        title: 'On-Device Extractor',
        subtitle: 'Extracts directly on your device via NewPipe / InnerTube (no remote server)',
        icon: Icons.phone_android_rounded,
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

        String syncSubtitle = context.l10n.cloudSyncSubtitle;
        if (user != null) {
          if (state.lastSyncedAt != null) {
            final diff = DateTime.now().difference(state.lastSyncedAt!);
            if (diff.inMinutes < 1) {
              syncSubtitle = context.l10n.lastSyncedJustNow;
            } else if (diff.inHours < 1) {
              syncSubtitle = context.l10n.lastSyncedMinutesAgo(diff.inMinutes);
            } else {
              syncSubtitle = context.l10n.lastSyncedHoursAgo(diff.inHours);
            }
          } else {
            syncSubtitle = context.l10n.connectedReadyToSync;
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
                          user?.displayName ?? user?.email ?? context.l10n.cloudSync,
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
                      child: Text(context.l10n.signIn, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: context.l10n.syncNow,
                      icon: isSyncing
                          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                          : Icon(Icons.sync_rounded, color: p.accent),
                      onPressed: isSyncing ? null : () => authCubit.syncNow(),
                    ),
                    IconButton(
                      tooltip: context.l10n.signOut,
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

  void _showYtmWebOptionsSheet(BuildContext context) {
    final p = context.palette;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Center(
          child: ConstrainedBox(
            constraints: Adaptive.sheetConstraints(ctx),
            child: Material(
              color: p.surfaceContainerHigh,
              borderRadius: AppRadii.bottomSheetRadius,
              clipBehavior: Clip.antiAlias,
              child: Padding(
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
                          child: Icon(Icons.language_rounded, color: p.accent, size: 22),
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
                                style: TextStyle(color: p.textSecondary, fontSize: 12),
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
                      subtitle: 'Personalized recommendations, mixes & quick picks',
                      url: 'https://music.youtube.com',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.explore_rounded,
                      title: 'Explore & Charts',
                      subtitle: 'Trending songs, top global charts & music videos',
                      url: 'https://music.youtube.com/explore',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.library_music_rounded,
                      title: 'Your Library',
                      subtitle: 'Saved playlists, albums, songs & subscribed artists',
                      url: 'https://music.youtube.com/library',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.favorite_rounded,
                      title: 'Liked Music',
                      subtitle: 'Thumbed-up songs synced with your Google account',
                      url: 'https://music.youtube.com/playlist?list=LM',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.fiber_new_rounded,
                      title: 'New Releases',
                      subtitle: 'Latest album drops, EPs and trending single releases',
                      url: 'https://music.youtube.com/new_releases',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.history_rounded,
                      title: 'Listening History',
                      subtitle: 'Recently played tracks and stations on your account',
                      url: 'https://music.youtube.com/history',
                      p: p,
                    ),
                  ],
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
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: p.textSecondary, fontSize: 11.5),
        ),
        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: p.textTertiary),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surfaceContainerHigh,
        title: Text(context.l10n.ytmAccount, style: TextStyle(color: p.textPrimary)),
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
            label: Text(context.l10n.openWebPlayer, style: TextStyle(color: p.accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel, style: TextStyle(color: p.textSecondary)),
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
            style: FilledButton.styleFrom(backgroundColor: p.error),
            child: Text(context.l10n.disconnect),
          ),
        ],
      ),
    );
  }

  void _showYtdlpConfigDialog(BuildContext context, SettingsCubit cubit, SettingsState state) {
    final urlController = TextEditingController(text: state.ytdlpBackendUrl);
    final tokenController = TextEditingController(text: state.ytdlpBackendToken);

    showDialog(
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
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: liveState.isTestingYtdlpBackend
                              ? null
                              : () {
                                  cubit.setYtdlpBackendUrl(urlController.text);
                                  cubit.setYtdlpBackendToken(tokenController.text);
                                  cubit.testYtdlpBackend();
                                },
                          icon: liveState.isTestingYtdlpBackend
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.speed_rounded, size: 16),
                          label: const Text('Test Connection'),
                        ),
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
                            color: liveState.ytdlpBackendStatusMessage!.startsWith('Connected')
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
                      const SnackBar(content: Text('yt-dlp backend settings saved')),
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

class _CacheSection extends StatefulWidget {
  const _CacheSection();

  @override
  State<_CacheSection> createState() => _CacheSectionState();
}

class _CacheSectionState extends State<_CacheSection> {
  int _artCacheSizeBytes = 0;
  int _streamCacheSizeBytes = 0;
  bool _isLoading = true;
  final YtmCacheManager _ytmCacheManager = YtmCacheManager();

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  Future<void> _refreshCacheSize() async {
    final artSize = await ArtworkCacheManager().getDiskCacheSizeBytes();
    final streamSize = await _ytmCacheManager.getCacheSizeBytes();
    if (mounted) {
      setState(() {
        _artCacheSizeBytes = artSize;
        _streamCacheSizeBytes = streamSize;
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
            'Artwork Cache',
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          subtitle: Text(
            _isLoading ? 'Calculating…' : '${_formatSize(_artCacheSizeBytes)} used of $maxMb MB max',
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
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cloud_download_rounded, color: Colors.redAccent, size: 22),
          ),
          title: Text(
            'YouTube Stream Disk Cache',
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          subtitle: Text(
            _isLoading ? 'Calculating…' : '${_formatSize(_streamCacheSizeBytes)} cached for zero-latency replay',
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
              await _ytmCacheManager.clearCache();
              await _refreshCacheSize();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Stream cache cleared successfully')),
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
            'Maximum Artwork Cache Limit',
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

void _showScrobblerSettingsModal(BuildContext context) {
  final p = context.palette;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _ScrobblerConfigSheet(),
  );
}

class _ScrobblerConfigSheet extends StatefulWidget {
  const _ScrobblerConfigSheet();

  @override
  State<_ScrobblerConfigSheet> createState() => _ScrobblerConfigSheetState();
}

class _ScrobblerConfigSheetState extends State<_ScrobblerConfigSheet> {
  bool _listenBrainzEnabled = false;
  final _listenBrainzTokenController = TextEditingController();

  bool _lastFmEnabled = false;
  final _lastFmApiKeyController = TextEditingController();
  final _lastFmSecretController = TextEditingController();
  final _lastFmSessionKeyController = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScrobblerPrefs();
  }

  Future<void> _loadScrobblerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();
    String lbToken = '';
    String lastFmKey = '';
    String lastFmSec = '';
    String lastFmSession = '';
    try {
      lbToken = await secureStorage.read(key: ScrobblerService.keyListenBrainzTokenSecure) ?? '';
      lastFmKey = await secureStorage.read(key: ScrobblerService.keyLastFmApiKeySecure) ?? '';
      lastFmSec = await secureStorage.read(key: ScrobblerService.keyLastFmSecretSecure) ?? '';
      lastFmSession = await secureStorage.read(key: ScrobblerService.keyLastFmSessionKeySecure) ?? '';
    } catch (_) {}
    if (lbToken.isEmpty) {
      lbToken = prefs.getString(ScrobblerService.keyListenBrainzToken) ?? '';
    }
    if (lastFmKey.isEmpty) {
      lastFmKey = prefs.getString(ScrobblerService.keyLastFmApiKey) ?? '';
    }
    if (lastFmSec.isEmpty) {
      lastFmSec = prefs.getString(ScrobblerService.keyLastFmSecret) ?? '';
    }
    if (lastFmSession.isEmpty) {
      lastFmSession = prefs.getString(ScrobblerService.keyLastFmSessionKey) ?? '';
    }
    setState(() {
      _listenBrainzEnabled = prefs.getBool(ScrobblerService.keyListenBrainzEnabled) ?? false;
      _listenBrainzTokenController.text = lbToken;

      _lastFmEnabled = prefs.getBool(ScrobblerService.keyLastFmEnabled) ?? false;
      _lastFmApiKeyController.text = lastFmKey;
      _lastFmSecretController.text = lastFmSec;
      _lastFmSessionKeyController.text = lastFmSession;
      _isLoading = false;
    });
  }

  Future<void> _saveScrobblerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();
    await prefs.setBool(ScrobblerService.keyListenBrainzEnabled, _listenBrainzEnabled);
    final lbToken = _listenBrainzTokenController.text.trim();
    if (lbToken.isNotEmpty) {
      await secureStorage.write(key: ScrobblerService.keyListenBrainzTokenSecure, value: lbToken);
    } else {
      await secureStorage.delete(key: ScrobblerService.keyListenBrainzTokenSecure);
    }
    await prefs.remove(ScrobblerService.keyListenBrainzToken);

    await prefs.setBool(ScrobblerService.keyLastFmEnabled, _lastFmEnabled);
    final lastFmKey = _lastFmApiKeyController.text.trim();
    final lastFmSec = _lastFmSecretController.text.trim();
    final lastFmSession = _lastFmSessionKeyController.text.trim();

    if (lastFmKey.isNotEmpty) {
      await secureStorage.write(key: ScrobblerService.keyLastFmApiKeySecure, value: lastFmKey);
    } else {
      await secureStorage.delete(key: ScrobblerService.keyLastFmApiKeySecure);
    }
    if (lastFmSec.isNotEmpty) {
      await secureStorage.write(key: ScrobblerService.keyLastFmSecretSecure, value: lastFmSec);
    } else {
      await secureStorage.delete(key: ScrobblerService.keyLastFmSecretSecure);
    }
    if (lastFmSession.isNotEmpty) {
      await secureStorage.write(key: ScrobblerService.keyLastFmSessionKeySecure, value: lastFmSession);
    } else {
      await secureStorage.delete(key: ScrobblerService.keyLastFmSessionKeySecure);
    }
    await prefs.remove(ScrobblerService.keyLastFmApiKey);
    await prefs.remove(ScrobblerService.keyLastFmSecret);
    await prefs.remove(ScrobblerService.keyLastFmSessionKey);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scrobbler configuration saved!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _listenBrainzTokenController.dispose();
    _lastFmApiKeyController.dispose();
    _lastFmSecretController.dispose();
    _lastFmSessionKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.equalizer_rounded, color: p.accent, size: 24),
                const SizedBox(width: 10),
                Text(
                  'Scrobbler Settings',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'ListenBrainz REST Scrobbler',
              style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Enable ListenBrainz', style: TextStyle(color: p.textPrimary, fontSize: 14)),
              value: _listenBrainzEnabled,
              activeThumbColor: p.accent,
              onChanged: (val) => setState(() => _listenBrainzEnabled = val),
            ),
            if (_listenBrainzEnabled)
              TextField(
                controller: _listenBrainzTokenController,
                style: TextStyle(color: p.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'User Token',
                  hintText: 'Enter ListenBrainz User Token',
                  labelStyle: TextStyle(color: p.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            const SizedBox(height: 20),
            Divider(color: p.hairline),
            const SizedBox(height: 8),
            Text(
              'Last.fm REST Scrobbler',
              style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Enable Last.fm Direct Scrobbling', style: TextStyle(color: p.textPrimary, fontSize: 14)),
              value: _lastFmEnabled,
              activeThumbColor: p.accent,
              onChanged: (val) => setState(() => _lastFmEnabled = val),
            ),
            if (_lastFmEnabled) ...[
              TextField(
                controller: _lastFmApiKeyController,
                style: TextStyle(color: p.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Last.fm API Key',
                  labelStyle: TextStyle(color: p.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lastFmSecretController,
                style: TextStyle(color: p.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Last.fm Shared Secret',
                  labelStyle: TextStyle(color: p.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lastFmSessionKeyController,
                style: TextStyle(color: p.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Last.fm Session Key (sk)',
                  labelStyle: TextStyle(color: p.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saveScrobblerPrefs,
                child: const Text('Save Settings', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

