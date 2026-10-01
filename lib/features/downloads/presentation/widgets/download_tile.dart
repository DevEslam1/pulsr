// lib/features/downloads/presentation/widgets/download_tile.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../../core/errors/error_message_resolver.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../domain/models/download_task.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../cubit/downloads_cubit.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
      DownloadStatus.tagging => (
          Icons.tune_rounded,
          p.accent,
          l10n.statusEmbedding,
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

    int? resolvedBytes = task.fileSize;
    if (resolvedBytes == null && task.filePath != null) {
      try {
        final f = File(task.filePath!);
        if (f.existsSync()) resolvedBytes = f.lengthSync();
      } catch (_) {}
    }
    final formattedSize = resolvedBytes != null && resolvedBytes > 0
        ? Formatters.formatBytes(resolvedBytes)
        : null;

    final subtitleParts = <String>[
      if (task.artist.isNotEmpty) task.artist,
      if (formattedSize != null) formattedSize,
    ];
    final subtitleText = subtitleParts.join(' • ');

    final hasArtwork = task.artworkUrl != null && task.artworkUrl!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.r16),
        border: Border.all(color: p.hairline),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (hasArtwork)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.r12),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedArtwork(
                          id: task.localSongId ?? task.sourceSongId ?? -1,
                          remoteUrl: task.artworkUrl,
                          type: ArtworkType.AUDIO,
                          size: 44,
                          borderRadius: AppRadii.r12,
                        ),
                        if (task.status == DownloadStatus.complete)
                          PositionedDirectional(
                            end: 2,
                            bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                color: p.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.check_circle_rounded,
                                  color: p.success, size: 14),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.r12),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 22),
                ),
              const SizedBox(width: AppSpacing.s10),
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
                        fontSize: AppFontSize.callout,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Row(
                      children: [
                        if (subtitleText.isNotEmpty)
                          Flexible(
                            child: Text(
                              subtitleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: AppFontSize.bodySmall,
                              ),
                            ),
                          ),
                        if (task.status != DownloadStatus.complete) ...[
                          const SizedBox(width: AppSpacing.xxs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppRadii.r8),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // FIX-A12: Direct cancel button during active download or queued state
              if (task.status == DownloadStatus.downloading ||
                  task.status == DownloadStatus.tagging ||
                  task.status == DownloadStatus.queued)
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: p.textSecondary, size: 20),
                  tooltip: l10n.cancel,
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  onPressed: () {
                    final title =
                        task.title.isNotEmpty ? task.title : task.videoId;
                    cubit.cancelDownload(task.videoId);
                    PulsrToast.show(
                      context,
                      message: '$title ${l10n.statusCancelled.toLowerCase()}',
                      icon: Icons.cancel_outlined,
                      actionLabel: l10n.retry,
                      onActionPressed: () => cubit.retryDownload(task.videoId),
                    );
                  },
                ),
              Semantics(
                label: '${l10n.browseDownloadActionsFor} ${task.title}',
                button: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
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
                        case 'delete':
                          cubit.deleteDownload(task.videoId);
                          PulsrToast.show(
                            context,
                            message:
                                '${task.title.isNotEmpty ? task.title : task.videoId} ${l10n.delete.toLowerCase()}',
                            icon: Icons.delete_outline_rounded,
                            actionLabel: l10n.undo,
                            onActionPressed: () => cubit.queueDownload(task),
                          );
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      if (task.status.canPause)
                        PopupMenuItem(
                          value: 'pause',
                          child: Row(
                            children: [
                              Icon(Icons.pause_rounded,
                                  size: 18, color: p.textPrimary),
                              const SizedBox(width: AppSpacing.s10),
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
                              const SizedBox(width: AppSpacing.s10),
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
                              const SizedBox(width: AppSpacing.s10),
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
                            const SizedBox(width: AppSpacing.s10),
                            Text(l10n.delete, style: TextStyle(color: p.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.tagging) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.r4),
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                tween: Tween<double>(
                  begin: 0.0,
                  end: task.progress.clamp(0.0, 1.0),
                ),
                builder: (context, animatedProgress, _) {
                  return LinearProgressIndicator(
                    value: task.status == DownloadStatus.tagging
                        ? null
                        : (animatedProgress > 0 ? animatedProgress : null),
                    backgroundColor: p.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                    minHeight: 6,
                  );
                },
              ),
            ),
            if (task.status == DownloadStatus.downloading) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(task.progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (task.speedKbps != null && task.speedKbps! > 0)
                    Text(
                      '${task.speedKbps!.toStringAsFixed(0)} KB/s',
                      style: TextStyle(
                          color: p.textTertiary, fontSize: AppFontSize.label),
                    ),
                  if (task.etaSeconds != null && task.etaSeconds! > 0)
                    Text(
                      '${l10n.browseEta} ${task.etaSeconds}s',
                      style: TextStyle(
                          color: p.textTertiary, fontSize: AppFontSize.label),
                    ),
                ],
              ),
            ],
          ],
          if (task.error != null && task.error!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: p.error),
                const SizedBox(width: AppSpacing.s6),
                Expanded(
                  child: Text(
                    resolveUiErrorMessage(context, task.error!),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: p.error, fontSize: AppFontSize.label),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
