// lib/features/downloads/presentation/downloads_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/errors/error_message_resolver.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/widgets/pulsr_back_button.dart';
import '../../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/download_task.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../player/cubit/player_cubit.dart';
import '../cubit/downloads_cubit.dart';
import '../cubit/downloads_state.dart';
import 'widgets/download_tile.dart';
import 'widgets/storage_stats_header.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

enum DownloadFilter { all, downloading, completed, failed }

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  DownloadFilter _filter = DownloadFilter.all;

  String _emptyMessageForFilter(DownloadFilter filter) {
    return switch (filter) {
      DownloadFilter.all => 'No downloads yet',
      DownloadFilter.downloading => 'No active downloads in progress',
      DownloadFilter.completed => 'No completed downloads yet',
      DownloadFilter.failed => 'No failed downloads',
    };
  }

  Widget _buildFilterChip(
      String label, int count, DownloadFilter filter, PulsrPalette p) {
    final isSelected = _filter == filter;
    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      selectedColor: p.accent.withValues(alpha: 0.2),
      checkmarkColor: p.accent,
      labelStyle: TextStyle(
        color: isSelected ? p.accent : p.textSecondary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        fontSize: AppFontSize.caption,
      ),
      side: BorderSide(
        color: isSelected ? p.accent.withValues(alpha: 0.4) : p.hairline,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.r12),
      ),
      onSelected: (_) {
        setState(() => _filter = filter);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return PulsrPagePopScope(
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const PulsrBackButton(),
          title: Text(
            l10n.downloadsTitle,
            style: TextStyle(
              color: p.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: AppFontSize.titleLarge,
            ),
          ),
          actions: [
            BlocBuilder<DownloadsCubit, DownloadsState>(
              buildWhen: (a, b) => a.taskList != b.taskList,
              builder: (context, state) {
                final failedCount = state.taskList
                    .where((t) => t.status == DownloadStatus.failed)
                    .length;
                if (failedCount == 0) return const SizedBox.shrink();
                return TextButton.icon(
                  onPressed: () =>
                      context.read<DownloadsCubit>().retryAllFailed(),
                  icon: Icon(Icons.refresh_rounded,
                      size: 18, color: p.accent),
                  label: Text(
                    '${l10n.retry} ($failedCount)',
                    style: TextStyle(
                        color: p.accent, fontSize: AppFontSize.bodySmall),
                  ),
                );
              },
            ),
          ],
        ),
        body: BlocListener<DownloadsCubit, DownloadsState>(
          listenWhen: (prev, curr) =>
              curr.errorMessage != null &&
              curr.errorMessage != prev.errorMessage,
          listener: (context, state) {
            final message = state.errorMessage;
            if (message == null) return;
            PulsrToast.show(
              context,
              message: resolveUiErrorMessage(context, message),
              icon: Icons.error_outline_rounded,
              isError: true,
            );
          },
          child: BlocBuilder<DownloadsCubit, DownloadsState>(
            builder: (context, state) {
              if (state.isLoading && state.tasks.isEmpty) {
                return const SkeletonList(
                    padding: EdgeInsets.only(top: AppSpacing.xs));
              }

              final allTasks = state.taskList;
              final activeTasks =
                  allTasks.where((t) => t.status.isActive).toList();
              final completedTasks = allTasks
                  .where((t) => t.status == DownloadStatus.complete)
                  .toList();
              final failedTasks = allTasks
                  .where((t) => t.status == DownloadStatus.failed)
                  .toList();

              final filteredTasks = switch (_filter) {
                DownloadFilter.all => allTasks,
                DownloadFilter.downloading => activeTasks,
                DownloadFilter.completed => completedTasks,
                DownloadFilter.failed => failedTasks,
              };

              Widget content;
              if (allTasks.isEmpty) {
                content = LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        children: [
                          if (state.storageStats.totalBytes > 0)
                            StorageStatsHeader(stats: state.storageStats),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.download_done_rounded,
                                    size: 64,
                                    color: p.textTertiary,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    l10n.noDownloadsTitle,
                                    style: TextStyle(
                                      color: p.textPrimary,
                                      fontSize: AppFontSize.title,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    l10n.noDownloadsSubtitle,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: AppFontSize.body,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              } else {
                content = ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  itemCount: filteredTasks.isEmpty
                      ? 3
                      : filteredTasks.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return StorageStatsHeader(
                        key: const ValueKey('storage_stats_header'),
                        stats: state.storageStats,
                      );
                    }

                    if (index == 1) {
                      return Padding(
                        key: const ValueKey('downloads_filter_row'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xs),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip('All', allTasks.length,
                                  DownloadFilter.all, p),
                              const SizedBox(width: AppSpacing.xs),
                              _buildFilterChip('Downloading', activeTasks.length,
                                  DownloadFilter.downloading, p),
                              const SizedBox(width: AppSpacing.xs),
                              _buildFilterChip('Completed', completedTasks.length,
                                  DownloadFilter.completed, p),
                              const SizedBox(width: AppSpacing.xs),
                              _buildFilterChip('Failed', failedTasks.length,
                                  DownloadFilter.failed, p),
                            ],
                          ),
                        ),
                      );
                    }

                    if (filteredTasks.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _filter == DownloadFilter.failed
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.downloading_rounded,
                                size: 48,
                                color: p.textTertiary,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                _emptyMessageForFilter(_filter),
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.body,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final task = filteredTasks[index - 2];
                    final playable =
                        task.status == DownloadStatus.complete &&
                            task.localSongId != null;
                    return Padding(
                      key: ValueKey(task.videoId),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.s6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadii.r16),
                        onTap: playable
                            ? () => _playCompleted(context, task)
                            : null,
                        child: DownloadTile(task: task),
                      ),
                    );
                  },
                );
              }

              return RefreshIndicator(
                color: p.accent,
                onRefresh: () async {
                  final cubit = context.read<DownloadsCubit>();
                  await Future.wait([
                    cubit.loadInitialTasks(),
                    cubit.refreshStorageStats(),
                  ]);
                },
                child: content,
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _playCompleted(BuildContext context, DownloadTask task) async {
    final localId = task.localSongId;
    if (localId == null) return;
    try {
      final db = getIt<AppDatabase>();
      final song = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(localId)))
          .getSingleOrNull();
      if (song == null) {
        if (context.mounted) {
          PulsrToast.show(context,
              message: AppLocalizations.of(context)!.songNotFound,
              icon: Icons.music_off_rounded,
              isError: true);
        }
        return;
      }
      if (context.mounted) context.read<PlayerCubit>().playSong(song);
    } catch (e, st) {
      ErrorLogger.log('Failed to play downloaded song',
          error: e, stackTrace: st, category: 'Downloads');
      if (context.mounted) {
        PulsrToast.show(context,
            message: AppLocalizations.of(context)!.songNotFound,
            icon: Icons.music_off_rounded,
            isError: true);
      }
    }
  }
}
