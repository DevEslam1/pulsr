// lib/features/downloads/presentation/widgets/download_tile.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../domain/models/download_task.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../cubit/downloads_cubit.dart';

class DownloadTile extends StatelessWidget {
  final DownloadTask task;

  const DownloadTile({
    super.key,
    required this.task,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cubit = context.read<DownloadsCubit>();
    final l10n = AppLocalizations.of(context)!;

    final (statusIcon, statusColor, statusLabel) = switch (task.status) {
      DownloadStatus.downloading => (
          Icons.downloading_rounded,
          p.accent,
          l10n.statusDownloading,
        ),
      DownloadStatus.embedding => (
          Icons.tag_rounded,
          p.accent,
          'Embedding tags…',
        ),
      DownloadStatus.queued => (
          Icons.schedule_rounded,
          p.accent.withValues(alpha: 0.7),
          l10n.statusQueued,
        ),
      DownloadStatus.paused => (
          Icons.pause_circle_outline_rounded,
          p.textTertiary,
          l10n.statusPaused,
        ),
      DownloadStatus.complete => (
          Icons.check_circle_rounded,
          p.success,
          l10n.statusCompleted,
        ),
      DownloadStatus.failed => (
          Icons.error_outline_rounded,
          p.error,
          l10n.statusFailed,
        ),
    };

    // a11y: semantic label for screen readers per 10/10 checklist
    return Semantics(
      label:
          '${task.title} ${task.artist} $statusLabel ${task.progress > 0 ? '${(task.progress * 100).round()}%' : ''}',
      button: false,
      child: Container(
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.hairline),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title.isNotEmpty ? task.title : task.videoId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (task.artist.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          task.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  label: 'Download actions for ${task.title}',
                  button: true,
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded,
                        color: p.textSecondary, size: 20),
                    color: p.surfaceContainerHigh,
                    onSelected: (action) {
                      switch (action) {
                        case 'pause':
                          cubit.pauseDownload(task.videoId);
                          break;
                        case 'resume':
                          cubit.resumeDownload(task.videoId);
                          break;
                        case 'retry':
                          cubit.retryDownload(task.videoId);
                          break;
                        case 'prioritize':
                          cubit.prioritizeDownload(task.videoId);
                          break;
                        case 'delete':
                          cubit.deleteDownload(task.videoId);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      if (task.status == DownloadStatus.queued ||
                          task.status == DownloadStatus.paused)
                        PopupMenuItem(
                          value: 'prioritize',
                          child: Row(
                            children: [
                              Icon(Icons.vertical_align_top_rounded,
                                  size: 18, color: p.accent),
                              const SizedBox(width: 10),
                              Text('Download Next',
                                  style: TextStyle(color: p.accent)),
                            ],
                          ),
                        ),
                      if (task.status.canPause)
                        PopupMenuItem(
                          value: 'pause',
                          child: Row(
                            children: [
                              Icon(Icons.pause_rounded,
                                  size: 18, color: p.textPrimary),
                              const SizedBox(width: 10),
                              Text(l10n.pause),
                            ],
                          ),
                        ),
                      if (task.status.canResume)
                        PopupMenuItem(
                          value: 'resume',
                          child: Row(
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  size: 18, color: p.textPrimary),
                              const SizedBox(width: 10),
                              Text(l10n.resume),
                            ],
                          ),
                        ),
                      if (task.status.canRetry)
                        PopupMenuItem(
                          value: 'retry',
                          child: Row(
                            children: [
                              Icon(Icons.refresh_rounded,
                                  size: 18, color: p.textPrimary),
                              const SizedBox(width: 10),
                              Text(l10n.retry),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 18, color: p.error),
                            const SizedBox(width: 10),
                            Text(l10n.delete, style: TextStyle(color: p.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (task.status == DownloadStatus.downloading) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress > 0 ? task.progress : null,
                  backgroundColor: p.surfaceContainerHigh,
                  valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(task.progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (task.speedKbps != null && task.speedKbps! > 0)
                    Text(
                      '${task.speedKbps!.toStringAsFixed(0)} KB/s',
                      style: TextStyle(color: p.textTertiary, fontSize: 12),
                    ),
                  if (task.etaSeconds != null && task.etaSeconds! > 0)
                    Text(
                      'ETA: ${task.etaSeconds}s',
                      style: TextStyle(color: p.textTertiary, fontSize: 12),
                    ),
                ],
              ),
            ],
            if (task.error != null && task.error!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: p.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      task.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.error, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
