import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../domain/models/download_task.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../cubit/downloads_cubit.dart';
import '../../cubit/downloads_state.dart';

class StorageStatsHeader extends StatelessWidget {
  final StorageStats? stats;

  const StorageStatsHeader({
    super.key,
    this.stats,
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
    if (stats != null) {
      return _buildContent(context, stats!);
    }

    return BlocSelector<DownloadsCubit, DownloadsState, StorageStats>(
      selector: (state) => state.storageStats,
      builder: (context, stats) {
        return _buildContent(context, stats);
      },
    );
  }

  Widget _buildContent(BuildContext context, StorageStats stats) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final usedStr = _formatBytes(stats.usedBytes);
    final freeStr = _formatBytes(stats.freeBytes);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
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
                  const SizedBox(width: 8),
                  Text(
                    l10n.storageUsed,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Text(
                '$usedStr / ${l10n.storageFree}: $freeStr',
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
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
