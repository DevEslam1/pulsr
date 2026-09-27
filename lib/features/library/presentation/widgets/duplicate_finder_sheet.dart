// lib/features/library/presentation/widgets/duplicate_finder_sheet.dart
import 'package:flutter/material.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../data/db/app_database.dart';

class DuplicateGroup {
  final String normalizedKey;
  final List<SongsTableData> tracks;
  DuplicateGroup(this.normalizedKey, this.tracks);
}

/// Sheet for scanning, reviewing, and cleaning duplicate audio tracks in the library.
class DuplicateFinderSheet extends StatefulWidget {
  final List<SongsTableData> allSongs;
  final ValueChanged<List<SongsTableData>>? onDeleteSelected;

  const DuplicateFinderSheet({
    super.key,
    required this.allSongs,
    this.onDeleteSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required List<SongsTableData> allSongs,
    ValueChanged<List<SongsTableData>>? onDeleteSelected,
  }) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (_) => DuplicateFinderSheet(
        allSongs: allSongs,
        onDeleteSelected: onDeleteSelected,
      ),
    );
  }

  @override
  State<DuplicateFinderSheet> createState() => _DuplicateFinderSheetState();
}

class _DuplicateFinderSheetState extends State<DuplicateFinderSheet> {
  final List<DuplicateGroup> _duplicates = [];
  final Set<int> _selectedIdsToDelete = {};
  bool _isScanning = true;

  @override
  void initState() {
    super.initState();
    _scanForDuplicates();
  }

  void _scanForDuplicates() {
    final Map<String, List<SongsTableData>> map = {};
    for (final song in widget.allSongs) {
      final key =
          '${song.title.trim().toLowerCase()}_${song.artist.trim().toLowerCase()}';
      map.putIfAbsent(key, () => []).add(song);
    }

    _duplicates.clear();
    map.forEach((key, list) {
      if (list.length >= 2) {
        _duplicates.add(DuplicateGroup(key, list));
      }
    });

    setState(() => _isScanning = false);
  }

  void _autoSelectLowerQuality() {
    _selectedIdsToDelete.clear();
    for (final group in _duplicates) {
      // Sort so highest bitrate / lossless is first
      final sorted = List<SongsTableData>.from(group.tracks)
        ..sort((a, b) {
          final aIsFlac = a.path.toLowerCase().endsWith('.flac') ? 1 : 0;
          final bIsFlac = b.path.toLowerCase().endsWith('.flac') ? 1 : 0;
          if (aIsFlac != bIsFlac) return bIsFlac.compareTo(aIsFlac);
          final aBitrate = a.bitrateKbps ?? 0;
          final bBitrate = b.bitrateKbps ?? 0;
          return bBitrate.compareTo(aBitrate);
        });

      // Keep the best (first), mark the rest for deletion
      for (int i = 1; i < sorted.length; i++) {
        _selectedIdsToDelete.add(sorted[i].id);
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.duplicateCleaner,
                      style: TextStyle(
                        fontSize: AppFontSize.titleLarge,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${_duplicates.length} duplicate clusters found',
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (_duplicates.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                    label: Text(context.l10n.keepThisOne),
                    onPressed: _autoSelectLowerQuality,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            if (_isScanning)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_duplicates.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 48, color: p.accent),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        context.l10n.noDuplicatesFound,
                        style: TextStyle(
                          fontSize: AppFontSize.body,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _duplicates.length,
                  itemBuilder: (context, index) {
                    final group = _duplicates[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Material(
                        color: p.surfaceContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.r16),
                          side: BorderSide(color: p.hairline),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.tracks.first.title,
                            style: TextStyle(
                              fontSize: AppFontSize.body,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            group.tracks.first.artist,
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              color: p.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Divider(height: AppSpacing.md),
                          ...group.tracks.map((track) {
                            final isMarked =
                                _selectedIdsToDelete.contains(track.id);
                            final ext = track.path.contains('.')
                                ? track.path.split('.').last.toUpperCase()
                                : 'AUDIO';
                            final bitrateStr = track.bitrateKbps != null
                                ? '${track.bitrateKbps} kbps'
                                : '';

                            return CheckboxListTile(
                              value: isMarked,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.xs,
                                        vertical: AppSpacing.xxs),
                                    decoration: BoxDecoration(
                                      color: ext == 'FLAC'
                                          ? p.accent.withValues(alpha: 0.15)
                                          : p.hairline,
                                      borderRadius:
                                          BorderRadius.circular(AppRadii.r4),
                                    ),
                                    child: Text(
                                      ext,
                                      style: TextStyle(
                                        fontSize: AppFontSize.tiny,
                                        fontWeight: FontWeight.w800,
                                        color: ext == 'FLAC'
                                            ? p.accent
                                            : p.textSecondary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    bitrateStr,
                                    style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textSecondary,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    Formatters.formatDuration(Duration(
                                        milliseconds: track.durationMs)),
                                    style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                track.path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppFontSize.tiny,
                                  color: p.textTertiary,
                                ),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedIdsToDelete.add(track.id);
                                  } else {
                                    _selectedIdsToDelete.remove(track.id);
                                  }
                                });
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                );
              },
                ),
              ),

            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('Remove Selected (${_selectedIdsToDelete.length})'),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.favorite,
                  ),
                  onPressed: _selectedIdsToDelete.isEmpty
                      ? null
                      : () {
                          final selected = widget.allSongs
                              .where((s) => _selectedIdsToDelete.contains(s.id))
                              .toList();
                          widget.onDeleteSelected?.call(selected);
                          Navigator.of(context).pop();
                        },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
