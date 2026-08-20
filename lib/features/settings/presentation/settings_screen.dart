// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../player/presentation/widgets/audio_visualizer.dart';
import '../../player/presentation/widgets/equalizer_sheet.dart';
import '../../sheets/sleep_timer_sheet.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';
import 'hidden_folders_screen.dart';
import 'widgets/backup_section.dart';

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
                  _section(context, 'Audio & Playback', [
                    _navTile(context, Icons.equalizer_rounded, 'Equalizer & Sound Effects', '5-band EQ, bass boost, presets',
                        onTap: () => showModalBottomSheet(context: context, useRootNavigator: true, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const EqualizerSheet())),
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
                  ]),
                  _section(context, 'Theme & Appearance', [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<AppThemeMode>(
                          segments: const [
                            ButtonSegment(value: AppThemeMode.system, label: Text('Auto'), icon: Icon(Icons.brightness_auto_rounded, size: 15)),
                            ButtonSegment(value: AppThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded, size: 15)),
                            ButtonSegment(value: AppThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded, size: 15)),
                            ButtonSegment(value: AppThemeMode.amoled, label: Text('AMOLED'), icon: Icon(Icons.contrast_rounded, size: 15)),
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
                          Wrap(
                            spacing: 12, runSpacing: 12,
                            children: AppColors.customAccents.map((color) {
                              final isSelected = state.customAccentColorValue == color.toARGB32();
                              return GestureDetector(
                                onTap: () => cubit.setCustomAccentColor(color),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 42, height: 42,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: isSelected ? p.textPrimary : Colors.transparent, width: 2.5),
                                    boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 1)] : null,
                                  ),
                                  child: isSelected
                                      ? Icon(Icons.check_rounded, size: 20,
                                          color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                                      : null,
                                ),
                              );
                            }).toList(),
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
                    _switchTile(context, Icons.palette_outlined, 'Dynamic Artwork Theming', 'Adapt colors from album art',
                        value: state.dynamicThemingEnabled, onChanged: cubit.setDynamicTheming),
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
      {Widget? trailing, required VoidCallback onTap}) {
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
}
