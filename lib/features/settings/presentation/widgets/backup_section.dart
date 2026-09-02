// lib/features/settings/presentation/widgets/backup_section.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../domain/usecases/backup_usecases.dart';
import '../../cubit/settings_cubit.dart';

class BackupSection extends StatefulWidget {
  const BackupSection({super.key});

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  bool _isExporting = false;
  bool _isImporting = false;

  static Widget _buildIconContainer(BuildContext context, IconData icon) {
    final cardColor =
        Theme.of(context).cardTheme.color ?? context.palette.surfaceContainer;
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

  Future<void> _exportBackup(BuildContext context) async {
    setState(() => _isExporting = true);
    try {
      final exportUseCase = getIt<ExportBackupUseCase>();
      final jsonContent = await exportUseCase.execute();

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName = 'pulsr_backup_$timestamp.json';
      final bytes = Uint8List.fromList(utf8.encode(jsonContent));

      final outputFileUri = await FilePicker.saveFile(
        dialogTitle: 'Export Backup JSON',
        fileName: fileName,
        mimeType: 'application/json',
        bytes: bytes,
      );

      if (outputFileUri != null) {
        final filePath = outputFileUri.toFilePath();
        final file = File(filePath);
        if (!await file.exists() || (await file.length()) == 0) {
          await file.writeAsString(jsonContent);
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Backup exported successfully to ${file.path.split(Platform.pathSeparator).last}'),
              backgroundColor: context.palette.accent,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (files.isEmpty || files.single.path == null) {
      return;
    }

    final filePath = files.single.path!;
    final file = File(filePath);

    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected backup file does not exist'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final jsonContent = await file.readAsString();
    Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonContent) as Map<String, dynamic>;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid JSON backup file format'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final favsCount = (data['favorites'] as List?)?.length ?? 0;
    final playlistsCount = (data['playlists'] as List?)?.length ?? 0;
    final historyCount = (data['playHistory'] as List?)?.length ?? 0;
    final hasSettings = data['settings'] is Map;

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Row(
          children: [
            Icon(Icons.restore_rounded, color: context.palette.accent),
            const SizedBox(width: 8),
            Text(context.l10n.confirmRestore),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.confirmRestoreDesc,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text('• ${context.l10n.favorites}: $favsCount'),
            Text('• ${context.l10n.playlists}: $playlistsCount'),
            Text('• History: $historyCount'),
            Text(
                '• ${context.l10n.settings}: ${hasSettings ? "Included" : "None"}'),
            const SizedBox(height: 12),
            Text(
              context.l10n.existingLibraryUpdateNotice,
              style:
                  TextStyle(fontSize: 12, color: context.palette.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel,
                style: TextStyle(color: context.palette.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.palette.accent,
              foregroundColor: Colors.white,
            ),
            child: Text(context.l10n.confirmRestore),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isImporting = true);
    try {
      final importUseCase = getIt<ImportBackupUseCase>();
      final importResult = await importUseCase.execute(jsonContent);

      if (context.mounted) {
        // Reload SettingsCubit so theme and player settings update immediately
        final settingsCubit = context.read<SettingsCubit>();
        await settingsCubit.reloadSettings();

        if (!context.mounted) return;

        unawaited(showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: context.palette.accent),
                const SizedBox(width: 8),
                const Text('Backup Restored'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '• Restored Favorites: ${importResult.restoredFavoritesCount}'),
                Text(
                    '• Restored Playlists: ${importResult.restoredPlaylistsCount}'),
                Text(
                    '• Restored History Entries: ${importResult.restoredHistoryCount}'),
                Text(
                    '• Restored Settings: ${importResult.restoredSettingsCount} keys'),
                if (importResult.restoredExcludedFoldersCount > 0)
                  Text(
                      '• Restored Excluded Folders: ${importResult.restoredExcludedFoldersCount}'),
                if (importResult.unmatchedPaths.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '⚠️ ${importResult.unmatchedPaths.length} song paths could not be matched in your current library.',
                    style: const TextStyle(color: Colors.amber, fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          ),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = Theme.of(context).textTheme.bodyMedium?.color ??
        context.palette.textSecondary;

    return Column(
      children: [
        ListTile(
          leading: _buildIconContainer(context, Icons.upload_file_rounded),
          title: const Text(
            'Export Backup',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            'Save favorites, playlists, history & settings to JSON',
            style: TextStyle(color: textSecondary, fontSize: 12),
          ),
          trailing: _isExporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.chevron_right_rounded, color: textSecondary),
          onTap: _isExporting ? null : () => _exportBackup(context),
        ),
        ListTile(
          leading:
              _buildIconContainer(context, Icons.download_for_offline_rounded),
          title: const Text(
            'Import Backup',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            'Restore favorites, playlists, history & settings from JSON file',
            style: TextStyle(color: textSecondary, fontSize: 12),
          ),
          trailing: _isImporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.chevron_right_rounded, color: textSecondary),
          onTap: _isImporting ? null : () => _importBackup(context),
        ),
      ],
    );
  }
}
