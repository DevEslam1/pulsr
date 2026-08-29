// lib/features/settings/presentation/widgets/library_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../cubit/settings_cubit.dart';
import '../../cubit/settings_state.dart';
import '../hidden_folders_screen.dart';
import 'settings_section.dart';
import 'settings_slider_row.dart';
import 'settings_tiles.dart';

/// Library management: hidden folders, rescanning and the short-audio filter.
class LibrarySection extends StatelessWidget {
  final SettingsState state;

  const LibrarySection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<SettingsCubit>();
    return SettingsSection(
      icon: Icons.library_music_rounded,
      title: context.l10n.libraryAndScanning,
      children: [
        SettingsNavTile(
            Icons.folder_off_rounded,
            context.l10n.hiddenAndExcludedFolders,
            state.autoHideSystemMedia
                ? 'Auto-filtering voice memos • Custom paths'
                : 'Manage excluded directories',
            onTap: () => Navigator.push(context,
                MaterialPageRoute<void>(
                    builder: (_) => const HiddenFoldersScreen()))),
        settingsCardDivider(p),
        SettingsNavTile(
            Icons.refresh_rounded,
            state.isScanning ? 'Scanning storage…' : context.l10n.rescanLibrary,
            state.scanResultCount != null
                ? 'Last scan: ${state.scanResultCount} tracks'
                : 'Scan device storage for audio',
            trailing: state.isScanning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: p.accent))
                : null,
            onTap:
                state.isScanning ? () {} : () => cubit.rescanLibrary()),
        settingsCardDivider(p),
        SettingsNavTile(
            Icons.filter_list_rounded,
            context.l10n.shortAudioFilter,
            context.l10n.ignoreFilesUnder(state.minDurationSec),
            onTap: () =>
                _showDurationFilterDialog(context, cubit, state.minDurationSec)),
      ],
    );
  }

  // Default threshold is 30 s (SettingsState.minDurationSec).
  void _showDurationFilterDialog(
      BuildContext context, SettingsCubit cubit, int currentSec) {
    int selected = currentSec;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(context.l10n.minDuration),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Exclude tracks under $selected seconds (filters voice notes):'),
              SettingSliderRow(
                label: 'Duration threshold',
                value: selected.toDouble(),
                min: 0,
                max: 120,
                divisions: 12,
                defaultValue: 30,
                formatValue: (v) => '${v.toInt()}s',
                onChanged: (val) =>
                    setDialogState(() => selected = val.toInt()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel)),
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
}
