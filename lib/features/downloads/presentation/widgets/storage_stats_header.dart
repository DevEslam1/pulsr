// lib/features/downloads/presentation/widgets/storage_stats_header.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final usedStr = Formatters.formatBytes(stats.usedBytes);
    final freeStr = Formatters.formatBytes(stats.freeBytes);

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
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
            borderRadius: AppRadii.r4All,
            child: Semantics(
              label: l10n.storageUsed,
              value:
                  '${(stats.usedPercentage * 100).toStringAsFixed(0)}% ($usedStr / $freeStr)',
              child: LinearProgressIndicator(
                value: stats.usedPercentage,
                backgroundColor: p.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                minHeight: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
