// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../player/presentation/widgets/audio_visualizer.dart';
import '../../player/presentation/widgets/equalizer_sheet.dart';
import '../../sheets/sleep_timer_sheet.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';
import 'widgets/backup_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();
        final primaryColor = Theme.of(context).colorScheme.primary;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Settings',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 120, top: 8),
            children: [
              _buildSettingsCategory(
                context,
                title: 'AUDIO & PLAYBACK',
                items: [
                  _buildSettingsTile(
                    context,
                    icon: Icons.equalizer_rounded,
                    title: 'Equalizer & Sound Effects',
                    subtitle: '5-band graphical EQ, bass boost, and presets',
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const EqualizerSheet(),
                      );
                    },
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.timer_outlined,
                    title: 'Sleep Timer',
                    subtitle: 'Auto pause audio with gentle fade-out',
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) => const SleepTimerSheet(),
                      );
                    },
                  ),
                  ListTile(
                    leading: _buildIconContainer(context, Icons.graphic_eq_rounded),
                    title: const Text('Gapless Playback', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Continuous audio without silence', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color, fontSize: 12)),
                    trailing: Switch.adaptive(
                      value: state.gaplessPlayback,
                      activeTrackColor: primaryColor,
                      activeThumbColor: Colors.white,
                      onChanged: (val) => cubit.setGapless(val),
                    ),
                  ),
                  ListTile(
                    leading: _buildIconContainer(context, Icons.play_circle_outline_rounded),
                    title: const Text('Resume After Interruption', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Automatically resume playback after phone calls or interruptions', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color, fontSize: 12)),
                    trailing: Switch.adaptive(
                      value: state.resumeAfterInterruption,
                      activeTrackColor: primaryColor,
                      activeThumbColor: Colors.white,
                      onChanged: (val) => cubit.setResumeAfterInterruption(val),
                    ),
                  ),
                  ListTile(
                    leading: _buildIconContainer(context, Icons.graphic_eq_rounded),
                    title: const Text('Waveform Seek Bar', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Display dynamic audio waveform frequency visualization in player seek bar', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color, fontSize: 12)),
                    trailing: Switch.adaptive(
                      value: state.waveformSeekBarEnabled,
                      activeTrackColor: primaryColor,
                      activeThumbColor: Colors.white,
                      onChanged: (val) => cubit.setWaveformSeekBar(val),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Crossfade Duration', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            Text('${state.crossfadeSeconds.toStringAsFixed(1)}s', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        Slider(
                          value: state.crossfadeSeconds,
                          min: 0.0,
                          max: 12.0,
                          divisions: 24,
                          activeColor: primaryColor,
                          inactiveColor: Theme.of(context).cardTheme.color,
                          onChanged: (val) => cubit.setCrossfade(val),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              _buildSettingsCategory(
                context,
                title: 'THEME & APPEARANCE',
                items: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<AppThemeMode>(
                            segments: const [
                              ButtonSegment(
                                value: AppThemeMode.system,
                                label: Text('System'),
                                icon: Icon(Icons.brightness_auto_rounded, size: 16),
                              ),
                              ButtonSegment(
                                value: AppThemeMode.light,
                                label: Text('Light'),
                                icon: Icon(Icons.light_mode_rounded, size: 16),
                              ),
                              ButtonSegment(
                                value: AppThemeMode.dark,
                                label: Text('Dark'),
                                icon: Icon(Icons.dark_mode_rounded, size: 16),
                              ),
                              ButtonSegment(
                                value: AppThemeMode.amoled,
                                label: Text('AMOLED'),
                                icon: Icon(Icons.contrast_rounded, size: 16),
                              ),
                            ],
                            selected: {state.themeMode},
                            onSelectionChanged: (newSelection) {
                              cubit.setThemeMode(newSelection.first);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Custom Accent Color', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          state.dynamicThemingEnabled
                              ? 'Used as fallback when dynamic artwork theme is off or unavailable'
                              : 'Applied across the player and app UI',
                          style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: AppColors.customAccents.map((color) {
                            final isSelected = state.customAccentColorValue == color.toARGB32();
                            final onColor = color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
                            return GestureDetector(
                              onTap: () => cubit.setCustomAccentColor(color),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                                    width: 3,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: color.withValues(alpha: 0.5),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          )
                                        ]
                                      : null,
                                ),
                                child: isSelected
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: onColor,
                                        size: 20,
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.art_track_rounded,
                    title: 'Now Playing Theme',
                    subtitle: _getThemeModeTitle(state.playerThemeMode),
                    onTap: () {
                      _showThemePickerSheet(context, cubit, state.playerThemeMode);
                    },
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.graphic_eq_rounded,
                    title: 'Audio Visualizer Style',
                    subtitle: _getVisualizerStyleTitle(state.visualizerStyle),
                    onTap: () {
                      _showVisualizerStylePickerSheet(context, cubit, state.visualizerStyle);
                    },
                  ),
                  ListTile(
                    leading: _buildIconContainer(context, Icons.palette_outlined),
                    title: const Text('Dynamic Artwork Theming', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Adapt player colors from album artwork', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color, fontSize: 12)),
                    trailing: Switch.adaptive(
                      value: state.dynamicThemingEnabled,
                      activeTrackColor: primaryColor,
                      activeThumbColor: Colors.white,
                      onChanged: (val) => cubit.setDynamicTheming(val),
                    ),
                  ),
                ],
              ),

              _buildSettingsCategory(
                context,
                title: 'GESTURES',
                items: [
                  _buildSettingsTile(
                    context,
                    icon: Icons.swipe_left_rounded,
                    title: 'MiniPlayer Swipe Left',
                    subtitle: _getMiniPlayerSwipeTitle(state.miniPlayerSwipeLeft),
                    onTap: () {
                      _showMiniPlayerSwipePickerSheet(context, cubit, isLeft: true, currentAction: state.miniPlayerSwipeLeft);
                    },
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.swipe_right_rounded,
                    title: 'MiniPlayer Swipe Right',
                    subtitle: _getMiniPlayerSwipeTitle(state.miniPlayerSwipeRight),
                    onTap: () {
                      _showMiniPlayerSwipePickerSheet(context, cubit, isLeft: false, currentAction: state.miniPlayerSwipeRight);
                    },
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.touch_app_rounded,
                    title: 'Now Playing Double-Tap',
                    subtitle: _getNowPlayingDoubleTapTitle(state.nowPlayingDoubleTap),
                    onTap: () {
                      _showNowPlayingDoubleTapPickerSheet(context, cubit, state.nowPlayingDoubleTap);
                    },
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.gesture_rounded,
                    title: 'Now Playing Artwork Swipe',
                    subtitle: _getNowPlayingArtworkSwipeTitle(state.nowPlayingArtworkSwipe),
                    onTap: () {
                      _showNowPlayingArtworkSwipePickerSheet(context, cubit, state.nowPlayingArtworkSwipe);
                    },
                  ),
                ],
              ),

              _buildSettingsCategory(
                context,
                title: 'LIBRARY & SCANNING',
                items: [
                  _buildSettingsTile(
                    context,
                    icon: Icons.refresh_rounded,
                    title: state.isScanning ? 'Scanning storage...' : 'Rescan Media Library',
                    subtitle: state.scanResultCount != null
                        ? 'Last scan: ${state.scanResultCount} tracks discovered'
                        : 'Scan device storage for new audio files',
                    trailing: state.isScanning
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
                          )
                        : null,
                    onTap: state.isScanning ? () {} : () => cubit.rescanLibrary(),
                  ),
                  _buildSettingsTile(
                    context,
                    icon: Icons.filter_list_rounded,
                    title: 'Short Audio Filter',
                    subtitle: 'Ignore audio files shorter than ${state.minDurationSec} seconds',
                    onTap: () {
                      _showDurationFilterDialog(context, cubit, state.minDurationSec);
                    },
                  ),
                ],
              ),

              _buildSettingsCategory(
                context,
                title: 'PRIVACY & DATA',
                items: [
                  const BackupSection(),
                  _buildSettingsTile(
                    context,
                    icon: Icons.security_rounded,
                    title: 'Privacy Guarantee',
                    subtitle: '100% offline. Zero telemetry, zero cloud tracking.',
                    onTap: () {},
                  ),
                ],
              ),

              _buildSettingsCategory(
                context,
                title: 'ABOUT',
                items: [
                  _buildSettingsTile(
                    context,
                    icon: Icons.info_outline_rounded,
                    title: 'Pulsr Music',
                    subtitle: 'Version 1.0.0 (Pro Audio Edition) • Pure Offline Sound',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildIconContainer(BuildContext context, IconData icon) {
    final cardColor = Theme.of(context).cardTheme.color ?? AppColors.card;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: outlineColor, width: 1),
      ),
      child: Icon(icon, color: primaryColor, size: 20),
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

  Widget _buildSettingsCategory(
    BuildContext context, {
    required String title,
    required List<Widget> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        ...items,
      ],
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? AppColors.textSecondary;

    return ListTile(
      leading: _buildIconContainer(context, icon),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: textSecondary, fontSize: 12),
      ),
      trailing: trailing ?? Icon(Icons.chevron_right_rounded, color: textSecondary),
      onTap: onTap,
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
    final cardColor = Theme.of(context).cardTheme.color ?? AppColors.card;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? AppColors.textSecondary;

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
                decoration: BoxDecoration(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
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
    final cardColor = Theme.of(context).cardTheme.color ?? AppColors.card;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? AppColors.textSecondary;

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
                decoration: BoxDecoration(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
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
    final cardColor = Theme.of(context).cardTheme.color ?? AppColors.card;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? AppColors.textSecondary;

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
                decoration: BoxDecoration(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
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
    final cardColor = Theme.of(context).cardTheme.color ?? AppColors.card;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? AppColors.textSecondary;

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
                decoration: BoxDecoration(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
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
    final cardColor = Theme.of(context).cardTheme.color ?? AppColors.card;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final textPrimary = Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textPrimary;
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ?? AppColors.textSecondary;

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
                decoration: BoxDecoration(
                  color: isSelected ? primaryColor.withValues(alpha: 0.12) : cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
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
              );
            }),
          ],
        ),
      ),
    );
  }
}
