// lib/features/settings/presentation/widgets/backup_section.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../domain/usecases/backup_usecases.dart';
import '../../cubit/settings_cubit.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
        borderRadius: BorderRadius.circular(AppRadii.r10),
        border: Border.all(color: outlineColor, width: 1),
      ),
      child: Icon(icon, color: primaryColor, size: 20),
    );
  }

  Future<void> _exportBackup(BuildContext context) async {
    final l10n = context.l10n;
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

      final outputUri = await FilePicker.saveFile(
        dialogTitle: l10n.exportBackupDialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (outputUri != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.backupExportedTo(outputUri)),
              backgroundColor: context.palette.accent,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.exportFailedWithError(e.toString())),
            backgroundColor: context.palette.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    final l10n = context.l10n;
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null) return;
    const maxBackupBytes = 10 * 1024 * 1024;

    String? jsonContent;
    final webBytes = (result as dynamic).bytes as Uint8List?;
    if (webBytes != null && webBytes.isNotEmpty) {
      // Web / in-memory pick path.
      if (webBytes.length > maxBackupBytes) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.backupTooLarge),
              backgroundColor: context.palette.error,
            ),
          );
        }
        return;
      }
      jsonContent = utf8.decode(webBytes);
    } else {
      if (result.path == null) return;
      final filePath = result.path!;
      final file = File(filePath);

    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.backupMissing),
            backgroundColor: context.palette.error,
          ),
        );
      }
      return;
    }

    jsonContent ??= await file.readAsString();
    } // end file-path branch
    final resolvedContent = jsonContent;
    if (resolvedContent.length > maxBackupBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.backupTooLarge),
            backgroundColor: context.palette.error,
          ),
        );
      }
      return;
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resolvedContent) as Map<String, dynamic>;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.backupInvalid),
            backgroundColor: context.palette.error,
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

    final confirmed = await PulsrDialogHelper.showPulsrDialog<bool>(
      context,
      title: Row(
        children: [
          Icon(Icons.restore_rounded, color: context.palette.accent),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(context.l10n.confirmRestore)),
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
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.confirmFavoritesCount(favsCount)),
          Text(l10n.confirmPlaylistsCount(playlistsCount)),
          Text(l10n.confirmHistoryCount(historyCount)),
          Text(l10n.confirmSettingsValue(
              hasSettings ? l10n.includedLabel : l10n.noneLabel)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.existingLibraryUpdateNotice,
            style:
                TextStyle(fontSize: AppFontSize.label, color: context.palette.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel,
              style: TextStyle(color: context.palette.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: context.palette.accent,
            foregroundColor: Colors.white,
          ),
          child: Text(context.l10n.confirmRestore),
        ),
      ],
    );

    if (confirmed != true) return;

    setState(() => _isImporting = true);
    try {
      final importUseCase = getIt<ImportBackupUseCase>();
      final importResult = await importUseCase.execute(resolvedContent);

      if (context.mounted) {
        // Reload SettingsCubit so theme and player settings update immediately
        final settingsCubit = context.read<SettingsCubit>();
        await settingsCubit.reloadSettings();

        if (!context.mounted) return;

        PulsrDialogHelper.showPulsrDialog<void>(
          context,
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: context.palette.accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(context.l10n.backupRestored)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n
                  .restoredFavoritesCount(importResult.restoredFavoritesCount)),
              Text(l10n
                  .restoredPlaylistsCount(importResult.restoredPlaylistsCount)),
              Text(l10n
                  .restoredHistoryCount(importResult.restoredHistoryCount)),
              Text(l10n.restoredSettingsKeys(
                  importResult.restoredSettingsCount)),
              if (importResult.restoredExcludedFoldersCount > 0)
                Text(l10n.restoredExcludedFoldersCount(
                    importResult.restoredExcludedFoldersCount)),
              if (importResult.unmatchedPaths.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.unmatchedPathsWarning(importResult.unmatchedPaths.length),
                  style: TextStyle(color: context.palette.warning, fontSize: AppFontSize.label),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.doneAction),
            ),
          ],
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.importFailedWithError(e.toString())),
            backgroundColor: context.palette.error,
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
          title: Text(context.l10n.exportBackup,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppFontSize.body),
          ),
          subtitle: Text(context.l10n.backupExportDesc,
            style: TextStyle(color: textSecondary, fontSize: AppFontSize.label),
          ),
          trailing: _isExporting
              ? const SizedBox(width: AppSpacing.s20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.chevron_right_rounded, color: textSecondary),
          onTap: _isExporting ? null : () => _exportBackup(context),
        ),
        ListTile(
          leading:
              _buildIconContainer(context, Icons.download_for_offline_rounded),
          title: Text(context.l10n.importBackup,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppFontSize.body),
          ),
          subtitle: Text(context.l10n.backupImportDesc,
            style: TextStyle(color: textSecondary, fontSize: AppFontSize.label),
          ),
          trailing: _isImporting
              ? const SizedBox(width: AppSpacing.s20,
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
