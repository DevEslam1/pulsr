// lib/features/settings/presentation/widgets/download_settings_tiles.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../domain/models/download_settings.dart';

/// Concurrency picker for the download queue.
///
/// Reads/writes [DownloadSettings] directly rather than going through
/// [SettingsCubit] because the download concurrency lives in its own model
/// (shared with the repository). Changing it here is picked up by
/// [DownloadRepositoryImpl] the next time a task is admitted.
class DownloadConcurrencyTile extends StatefulWidget {
  const DownloadConcurrencyTile({super.key});

  @override
  State<DownloadConcurrencyTile> createState() =>
      _DownloadConcurrencyTileState();
}

class _DownloadConcurrencyTileState extends State<DownloadConcurrencyTile> {
  int _value = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await DownloadSettings.load();
    if (mounted) setState(() => _value = settings.maxConcurrent);
  }

  Future<void> _pick() async {
    final p = context.palette;
    final selected = await PulsrSheetHelper.showPulsrSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              Semantics(
                selected: _value == i,
                button: true,
                label: '$i',
                excludeSemantics: true,
                child: ListTile(
                  leading: Icon(
                    _value == i
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: p.accent,
                  ),
                  title: Text('$i', style: TextStyle(color: p.textPrimary)),
                  onTap: () => Navigator.of(sheetContext).pop(i),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final settings = await DownloadSettings.load();
    await settings.copyWith(maxConcurrent: selected).save();
    if (mounted) setState(() => _value = selected);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(Icons.download_for_offline_rounded, color: p.accent),
      title: Text(
        context.l10n.settingsDownloadConcurrent,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14.5,
          letterSpacing: -0.1,
        ),
      ),
      subtitle: Text(
        context.l10n.settingsDownloadConcurrentSubtitle,
        style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.32),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            margin: const EdgeInsetsDirectional.only(end: 6),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$_value',
              style: TextStyle(
                color: p.accent,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: p.textTertiary.withValues(alpha: 0.7), size: 20),
        ],
      ),
      onTap: _pick,
    );
  }
}

/// Documents that a custom download location is not implemented. Shown as a
/// disabled row rather than hidden, so the limitation is explicit rather than
/// looking like a missing feature.
class DownloadLocationTile extends StatelessWidget {
  const DownloadLocationTile({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListTile(
      enabled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(Icons.folder_outlined, color: p.textTertiary),
      title: Text(
        context.l10n.settingsDownloadLocation,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14.5,
          letterSpacing: -0.1,
          color: p.textSecondary,
        ),
      ),
      subtitle: Text(
        context.l10n.settingsDownloadLocationUnsupported,
        style: TextStyle(color: p.textTertiary, fontSize: 12.5, height: 1.32),
      ),
    );
  }
}
