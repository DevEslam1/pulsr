// lib/features/downloads/presentation/downloads_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/errors/error_message_resolver.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/widgets/empty_state_widget.dart';
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
  final AppDatabase? db;

  const DownloadsScreen({super.key, this.db});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  DownloadFilter _filter = DownloadFilter.all;
  late final AppDatabase? _db;

  @override
  void initState() {
    super.initState();
    _db = widget.db ??
        (getIt.isRegistered<AppDatabase>() ? getIt<AppDatabase>() : null);
  }

  String _emptyMessageForFilter(AppLocalizations l10n, DownloadFilter filter) {
    return switch (filter) {
      DownloadFilter.all => l10n.noDownloadsTitle,
      DownloadFilter.downloading =>
        '${l10n.noDownloadsTitle} (${l10n.statusDownloading})',
      DownloadFilter.completed =>
        '${l10n.noDownloadsTitle} (${l10n.statusCompleted})',
      DownloadFilter.failed => '${l10n.noDownloadsTitle} (${l10n.statusFailed})',
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
            BlocSelector<DownloadsCubit, DownloadsState, int>(
              selector: (state) => state.taskList
                  .where((t) => t.status == DownloadStatus.failed)
                  .length,
              builder: (context, failedCount) {
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
                          EmptyStateWidget(
                            icon: Icons.download_done_rounded,
                            title: l10n.noDownloadsTitle,
                            subtitle: l10n.noDownloadsSubtitle,
                            primaryActionLabel: l10n.searchOnline,
                            primaryActionIcon: Icons.explore_rounded,
                            onPrimaryAction: () => context.go('/browse'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              } else {
                content = ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
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
                              _buildFilterChip(l10n.all, allTasks.length,
                                  DownloadFilter.all, p),
                              const SizedBox(width: AppSpacing.xs),
                              _buildFilterChip(l10n.statusDownloading, activeTasks.length,
                                  DownloadFilter.downloading, p),
                              const SizedBox(width: AppSpacing.xs),
                              _buildFilterChip(l10n.statusCompleted, completedTasks.length,
                                  DownloadFilter.completed, p),
                              const SizedBox(width: AppSpacing.xs),
                              _buildFilterChip(l10n.statusFailed, failedTasks.length,
                                  DownloadFilter.failed, p),
                            ],
                          ),
                        ),
                      );
                    }

                    if (filteredTasks.isEmpty) {
                      return EmptyStateWidget(
                        icon: _filter == DownloadFilter.failed
                            ? Icons.error_outline_rounded
                            : Icons.downloading_rounded,
                        iconColor: _filter == DownloadFilter.failed
                            ? p.error
                            : p.accent,
                        title: l10n.downloadsTitle,
                        subtitle: _emptyMessageForFilter(l10n, _filter),
                        primaryActionLabel: _filter == DownloadFilter.failed
                            ? l10n.retry
                            : l10n.searchOnline,
                        primaryActionIcon: _filter == DownloadFilter.failed
                            ? Icons.refresh_rounded
                            : Icons.explore_rounded,
                        onPrimaryAction: () {
                          if (_filter == DownloadFilter.failed) {
                            context.read<DownloadsCubit>().retryAllFailed();
                          } else {
                            context.go('/browse');
                          }
                        },
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
                backgroundColor: p.surfaceContainer,
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
    final downloadsCubit = context.read<DownloadsCubit>();
    final playerCubit = context.read<PlayerCubit>();
    final l10n = AppLocalizations.of(context)!;
    try {
      final db = _db;
      if (db == null) {
        ErrorLogger.log('Database not available for downloaded song playback',
            category: 'Downloads');
        if (context.mounted) {
          PulsrToast.show(
            context,
            message: l10n.libraryReadError,
            icon: Icons.error_outline_rounded,
            isError: true,
          );
        }
        return;
      }
      final song = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(localId)))
          .getSingleOrNull();
      if (!context.mounted) return;
      if (song == null) {
        PulsrToast.show(
          context,
          message: l10n.songNotFound,
          icon: Icons.music_off_rounded,
          isError: true,
          actionLabel: l10n.delete,
          onActionPressed: () {
            downloadsCubit.deleteDownload(task.videoId);
          },
        );
        return;
      }
      playerCubit.playSong(song);
    } catch (e, st) {
      ErrorLogger.log('Failed to play downloaded song',
          error: e, stackTrace: st, category: 'Downloads');
      if (context.mounted) {
        PulsrToast.show(
          context,
          message: l10n.songNotFound,
          icon: Icons.music_off_rounded,
          isError: true,
        );
      }
    }
  }
}
