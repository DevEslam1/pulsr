// lib/features/downloads/presentation/widgets/storage_stats_header.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../domain/models/download_task.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class StorageStatsHeader extends StatelessWidget {
  final StorageStats stats;

  const StorageStatsHeader({
    super.key,
    required this.stats,
  });

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024.0 && i < suffixes.length - 1) {
      d /= 1024.0;
      i++;
    }
    return '${d.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final usedStr = _formatBytes(stats.usedBytes);
    final freeStr = _formatBytes(stats.freeBytes);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.r16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.pie_chart_outline_rounded,
                      size: 20, color: p.accent),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    l10n.storageUsed,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: AppFontSize.body,
                    ),
                  ),
                ],
              ),
              Text(
                '$usedStr / ${l10n.storageFree}: $freeStr',
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.r4),
            child: LinearProgressIndicator(
              value: stats.usedPercentage,
              backgroundColor: p.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(p.accent),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}
