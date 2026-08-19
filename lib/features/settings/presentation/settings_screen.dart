// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../player/presentation/widgets/equalizer_sheet.dart';
import '../../sheets/sleep_timer_sheet.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();

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
                    leading: _buildIconContainer(Icons.graphic_eq_rounded),
                    title: const Text('Gapless Playback', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('Continuous audio without silence', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    trailing: Switch.adaptive(
                      value: state.gaplessPlayback,
                      activeTrackColor: AppColors.primary,
                      activeThumbColor: Colors.white,
                      onChanged: (val) => cubit.setGapless(val),
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
                            Text('${state.crossfadeSeconds.toStringAsFixed(1)}s', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        Slider(
                          value: state.crossfadeSeconds,
                          min: 0.0,
                          max: 12.0,
                          divisions: 24,
                          activeColor: AppColors.primary,
                          inactiveColor: AppColors.card,
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
                  ListTile(
                    leading: _buildIconContainer(Icons.palette_outlined),
                    title: const Text('Dynamic Artwork Theming', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('Adapt player colors from album artwork', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    trailing: Switch.adaptive(
                      value: state.dynamicThemingEnabled,
                      activeTrackColor: AppColors.primary,
                      activeThumbColor: Colors.white,
                      onChanged: (val) => cubit.setDynamicTheming(val),
                    ),
                  ),
                ],
              ),

              _buildSettingsCategory(
                context,
                title: 'LIBRARY & SCANNING',
                items: [
                  _buildSettingsTile(
                    icon: Icons.refresh_rounded,
                    title: state.isScanning ? 'Scanning storage...' : 'Rescan Media Library',
                    subtitle: state.scanResultCount != null
                        ? 'Last scan: ${state.scanResultCount} tracks discovered'
                        : 'Scan device storage for new audio files',
                    trailing: state.isScanning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          )
                        : null,
                    onTap: state.isScanning ? () {} : () => cubit.rescanLibrary(),
                  ),
                  _buildSettingsTile(
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
                  _buildSettingsTile(
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

  static Widget _buildIconContainer(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outline, width: 1),
      ),
      child: Icon(icon, color: AppColors.primary, size: 20),
    );
  }

  void _showDurationFilterDialog(BuildContext context, SettingsCubit cubit, int currentSec) {
    int selected = currentSec;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
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
                activeColor: AppColors.primary,
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

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: _buildIconContainer(icon),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
