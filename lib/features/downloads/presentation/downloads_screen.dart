import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/errors/error_message_resolver.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/widgets/pulsr_empty_state.dart';
import '../../../../core/widgets/pulsr_back_button.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/download_task.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../player/cubit/player_cubit.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../cubit/downloads_cubit.dart';
import '../cubit/downloads_state.dart';
import 'widgets/download_tile.dart';
import 'widgets/storage_stats_header.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import '../../../../core/responsive/pulsr_layout_metrics.dart';
import 'package:pulsr/core/constants/app_colors.dart';

enum DownloadFilter { all, downloading, completed, failed }

/// Returns the subset of [selected] that still maps to a live task. Extracted
/// to the top level so the selection-pruning rule can be unit-tested without
/// building the whole screen.
@visibleForTesting
Set<String> pruneSelectedVideoIds(
    Set<String> selected, Iterable<String> validVideoIds) {
  final valid = validVideoIds.toSet();
  return selected.where(valid.contains).toSet();
}

/// The tasks [filter] currently shows, in list order. Extracted to the top
/// level so the "what is visible" rule is testable without the screen.
@visibleForTesting
List<DownloadTask> filterDownloadTasks(
    List<DownloadTask> tasks, DownloadFilter filter) {
  return switch (filter) {
    DownloadFilter.all => tasks,
    DownloadFilter.downloading =>
      tasks.where((t) => t.status.isActive).toList(),
    DownloadFilter.completed =>
      tasks.where((t) => t.status == DownloadStatus.complete).toList(),
    DownloadFilter.failed =>
      tasks.where((t) => t.status == DownloadStatus.failed).toList(),
  };
}

/// Whether two task lists show the same tiles in the same order with the same
/// statuses. Progress/ETA/speed ticks do not change the shape, so the screen
/// can skip its outer rebuild and let each tile selector update itself.
@visibleForTesting
bool sameTaskListShape(List<DownloadTask> a, List<DownloadTask> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].videoId != b[i].videoId || a[i].status != b[i].status) {
      return false;
    }
  }
  return true;
}

class DownloadsScreen extends StatefulWidget {
  final AppDatabase? db;

  const DownloadsScreen({super.key, this.db});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  DownloadFilter _filter = DownloadFilter.all;
  late final AppDatabase? _db;
  final Set<String> _selectedVideoIds = <String>{};
  bool _retryingBatch = false;

  bool get _isSelectionMode => _selectedVideoIds.isNotEmpty;

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
      DownloadFilter.failed =>
        '${l10n.noDownloadsTitle} (${l10n.statusFailed})',
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
        borderRadius: AppRadii.r12All,
      ),
      onSelected: (_) {
        setState(() {
          _filter = filter;
          // Prune selections that are not part of the newly filtered list, so
          // bulk Delete/Add-to-playlist can never act on tasks the filter has
          // hidden (they would otherwise stay selected but invisible).
          final cubit = context.read<DownloadsCubit>();
          final visible = filterDownloadTasks(cubit.state.taskList, filter);
          final pruned = pruneSelectedVideoIds(
              _selectedVideoIds, visible.map((t) => t.videoId));
          _selectedVideoIds
            ..clear()
            ..addAll(pruned);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return PulsrPagePopScope(
      onPop: _isSelectionMode
          ? () {
              setState(() => _selectedVideoIds.clear());
            }
          : null,
      child: BlocBuilder<DownloadsCubit, DownloadsState>(
        // Progress-only emits recreate the task map but not the visible list
        // shape; each tile subscribes to its own task, so skipping the outer
        // rebuild stops a ~100ms progress tick from rebuilding every tile.
        buildWhen: (prev, curr) =>
            prev.isLoading != curr.isLoading ||
            prev.errorMessage != curr.errorMessage ||
            prev.storageStats != curr.storageStats ||
            !sameTaskListShape(prev.taskList, curr.taskList),
        builder: (context, state) {
          final allTasks = state.taskList;
          final activeTasks = allTasks.where((t) => t.status.isActive).toList();
          final completedTasks = allTasks
              .where((t) => t.status == DownloadStatus.complete)
              .toList();
          final failedTasks =
              allTasks.where((t) => t.status == DownloadStatus.failed).toList();

          final filteredTasks = filterDownloadTasks(allTasks, _filter);

          return BlocListener<DownloadsCubit, DownloadsState>(
            // Prune selected ids when the visible list changes so a removed,
            // completed or filtered-out task cannot leave the screen stuck in
            // selection mode with stale "N selected" state.
            listenWhen: (prev, curr) =>
                _selectedVideoIds.isNotEmpty && curr.tasks != prev.tasks,
            listener: (context, state) {
              final visible = filterDownloadTasks(state.taskList, _filter);
              final visibleIds = {for (final t in visible) t.videoId};
              if (_selectedVideoIds.any((id) => !visibleIds.contains(id))) {
                setState(() {
                  final pruned =
                      pruneSelectedVideoIds(_selectedVideoIds, visibleIds);
                  _selectedVideoIds
                    ..clear()
                    ..addAll(pruned);
                });
              }
            },
            child: Scaffold(
              backgroundColor: p.bg,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: _isSelectionMode
                    ? IconButton(
                        constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTouchTarget,
                            minHeight: AppSpacing.minTouchTarget),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: l10n.cancel,
                        onPressed: () =>
                            setState(() => _selectedVideoIds.clear()),
                      )
                    : const PulsrBackButton(),
                title: Text(
                  _isSelectionMode
                      ? context.l10n.selectedCount(_selectedVideoIds.length)
                      : l10n.downloadsTitle,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.titleLarge,
                  ),
                ),
                actions: _isSelectionMode
                    ? [
                        IconButton(
                          constraints: const BoxConstraints(
                              minWidth: AppSpacing.minTouchTarget,
                              minHeight: AppSpacing.minTouchTarget),
                          icon: Icon(
                            _selectedVideoIds.length == filteredTasks.length
                                ? Icons.deselect_rounded
                                : Icons.select_all_rounded,
                          ),
                          tooltip:
                              _selectedVideoIds.length == filteredTasks.length
                                  ? 'Deselect all'
                                  : 'Select all',
                          onPressed: () {
                            setState(() {
                              if (_selectedVideoIds.length ==
                                  filteredTasks.length) {
                                _selectedVideoIds.clear();
                              } else {
                                _selectedVideoIds.addAll(
                                    filteredTasks.map((t) => t.videoId));
                              }
                            });
                          },
                        ),
                      ]
                    : [
                        BlocSelector<DownloadsCubit, DownloadsState,
                            List<DownloadTask>>(
                          selector: (state) => state.taskList
                              .where((t) => t.status == DownloadStatus.complete)
                              .toList(),
                          builder: (context, completed) {
                            if (completed.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return IconButton(
                              icon: const Icon(Icons.delete_sweep_rounded),
                              tooltip: l10n.clear,
                              constraints: const BoxConstraints(
                                minWidth: AppSpacing.minTouchTarget,
                                minHeight: AppSpacing.minTouchTarget,
                              ),
                              onPressed: () =>
                                  _confirmClearCompleted(context, completed),
                            );
                          },
                        ),
                        BlocSelector<DownloadsCubit, DownloadsState, int>(
                          selector: (state) => state.taskList
                              .where((t) => t.status == DownloadStatus.failed)
                              .length,
                          builder: (context, failedCount) {
                            if (failedCount == 0) {
                              return const SizedBox.shrink();
                            }
                            return TextButton.icon(
                              onPressed:
                                  _retryingBatch ? null : _retryAllFailed,
                              icon: Icon(Icons.refresh_rounded,
                                  size: 18, color: p.accent),
                              label: Text(
                                '${l10n.retry} ($failedCount)',
                                style: TextStyle(
                                    color: p.accent,
                                    fontSize: AppFontSize.bodySmall),
                              ),
                            );
                          },
                        ),
                      ],
              ),
              bottomNavigationBar: _isSelectionMode
                  ? _buildBulkActionsBar(context, allTasks)
                  : null,
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
                child: Builder(
                  builder: (context) {
                    if (state.isLoading && state.tasks.isEmpty) {
                      return const SkeletonList(
                          padding: EdgeInsets.only(top: AppSpacing.xs));
                    }

                    Widget content;
                    if (allTasks.isEmpty) {
                      content = LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight.isFinite
                                  ? constraints.maxHeight
                                  : 0.0,
                            ),
                            child: Column(
                              children: [
                                if (state.storageStats.totalBytes > 0)
                                  StorageStatsHeader(stats: state.storageStats),
                                PulsrEmptyState(
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
                            return Column(
                              key: const ValueKey('downloads_filter_row'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (activeTasks.isNotEmpty)
                                  Container(
                                    margin:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            AppSpacing.md,
                                            AppSpacing.xs,
                                            AppSpacing.md,
                                            AppSpacing.xxs),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: AppSpacing.xs),
                                    decoration: BoxDecoration(
                                      color: p.accent.withValues(alpha: 0.12),
                                      borderRadius: AppRadii.r12All,
                                      border: Border.all(
                                          color:
                                              p.accent.withValues(alpha: 0.25)),
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    p.accent),
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.xs),
                                        Expanded(
                                          child: Text(
                                            context.l10n
                                                .downloadsProgressSummary(
                                              activeTasks.length,
                                              completedTasks.length,
                                              allTasks.length,
                                            ),
                                            style: TextStyle(
                                              fontSize: AppFontSize.caption,
                                              color: p.accent,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                      vertical: AppSpacing.xs),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        _buildFilterChip(
                                            l10n.all,
                                            allTasks.length,
                                            DownloadFilter.all,
                                            p),
                                        const SizedBox(width: AppSpacing.xs),
                                        _buildFilterChip(
                                            l10n.statusDownloading,
                                            activeTasks.length,
                                            DownloadFilter.downloading,
                                            p),
                                        const SizedBox(width: AppSpacing.xs),
                                        _buildFilterChip(
                                            l10n.statusCompleted,
                                            completedTasks.length,
                                            DownloadFilter.completed,
                                            p),
                                        const SizedBox(width: AppSpacing.xs),
                                        _buildFilterChip(
                                            l10n.statusFailed,
                                            failedTasks.length,
                                            DownloadFilter.failed,
                                            p),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          if (filteredTasks.isEmpty) {
                            return PulsrEmptyState(
                              icon: _filter == DownloadFilter.failed
                                  ? Icons.error_outline_rounded
                                  : Icons.downloading_rounded,
                              iconColor: _filter == DownloadFilter.failed
                                  ? p.error
                                  : p.accent,
                              title: l10n.downloadsTitle,
                              subtitle: _emptyMessageForFilter(l10n, _filter),
                              primaryActionLabel:
                                  _filter == DownloadFilter.failed
                                      ? l10n.retry
                                      : l10n.searchOnline,
                              primaryActionIcon:
                                  _filter == DownloadFilter.failed
                                      ? Icons.refresh_rounded
                                      : Icons.explore_rounded,
                              onPrimaryAction: () {
                                if (_filter == DownloadFilter.failed) {
                                  _retryAllFailed();
                                } else {
                                  context.go('/browse');
                                }
                              },
                            );
                          }

                          // Guard the index-2 offset (two leading header rows)
                          // against a task list that shrank between builds.
                          final taskIndex = index - 2;
                          if (taskIndex < 0 ||
                              taskIndex >= filteredTasks.length) {
                            return const SizedBox.shrink();
                          }
                          final task = filteredTasks[taskIndex];
                          final playable =
                              task.status == DownloadStatus.complete &&
                                  task.localSongId != null;
                          final isSelected =
                              _selectedVideoIds.contains(task.videoId);

                          return Padding(
                            key: ValueKey(task.videoId),
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xxs),
                            child: InkWell(
                              borderRadius: AppRadii.r16All,
                              onLongPress: () {
                                Feedback.forLongPress(context);
                                setState(() {
                                  if (isSelected) {
                                    _selectedVideoIds.remove(task.videoId);
                                  } else {
                                    _selectedVideoIds.add(task.videoId);
                                  }
                                });
                              },
                              onTap: () {
                                if (_isSelectionMode) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedVideoIds.remove(task.videoId);
                                    } else {
                                      _selectedVideoIds.add(task.videoId);
                                    }
                                  });
                                } else if (playable) {
                                  _playCompleted(context, task);
                                }
                              },
                              child: Row(
                                children: [
                                  if (_isSelectionMode) ...[
                                    Checkbox(
                                      value: isSelected,
                                      activeColor: p.accent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: AppRadii.r4All,
                                      ),
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedVideoIds.add(task.videoId);
                                          } else {
                                            _selectedVideoIds
                                                .remove(task.videoId);
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(width: AppSpacing.xxs),
                                  ],
                                  Expanded(
                                    child: BlocSelector<DownloadsCubit,
                                        DownloadsState, DownloadTask>(
                                      selector: (state) =>
                                          state.tasks[task.videoId] ?? task,
                                      builder: (context, latest) =>
                                          DownloadTile(task: latest),
                                    ),
                                  ),
                                ],
                              ),
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
                        try {
                          await Future.wait([
                            cubit.loadInitialTasks(),
                            cubit.refreshStorageStats(),
                          ]);
                          // Both loaders record failures in state.errorMessage
                          // (surfaced by the listener above); re-surface here so a
                          // pull-to-refresh failure is not silently swallowed.
                          final failure = cubit.state.errorMessage;
                          if (failure != null && context.mounted) {
                            PulsrToast.show(
                              context,
                              message: resolveUiErrorMessage(context, failure),
                              icon: Icons.error_outline_rounded,
                              isError: true,
                            );
                          }
                        } catch (e, st) {
                          ErrorLogger.log('Downloads refresh failed',
                              error: e, stackTrace: st, category: 'Downloads');
                          if (context.mounted) {
                            PulsrToast.show(
                              context,
                              message: l10n.libraryReadError,
                              icon: Icons.error_outline_rounded,
                              isError: true,
                            );
                          }
                        }
                      },
                      child: Center(
                        child: ConstrainedBox(
                          constraints:
                              PulsrLayoutMetrics.contentConstraints(context),
                          child: content,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBulkActionsBar(BuildContext context, List<DownloadTask> tasks) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final selectedTasks =
        tasks.where((t) => _selectedVideoIds.contains(t.videoId)).toList();
    final hasFailed =
        selectedTasks.any((t) => t.status == DownloadStatus.failed);
    final completedWithSong = selectedTasks
        .where(
            (t) => t.status == DownloadStatus.complete && t.localSongId != null)
        .toList();

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          border: Border(top: BorderSide(color: p.hairline)),
          boxShadow: [
            BoxShadow(
              color: AppColors.scrimAt(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: p.error),
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: Text(l10n.delete),
              onPressed: selectedTasks.isEmpty
                  ? null
                  : () => _confirmDeleteSelected(context, selectedTasks),
            ),
            if (hasFailed)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: p.accent),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: Text(l10n.retry),
                onPressed: () => _retrySelectedFailed(context, selectedTasks),
              ),
            if (completedWithSong.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: p.textPrimary),
                icon: const Icon(Icons.playlist_add_rounded, size: 20),
                label: Text(l10n.addToPlaylist),
                onPressed: () =>
                    _addSelectedToPlaylist(context, completedWithSong),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSelected(
      BuildContext context, List<DownloadTask> selectedTasks) async {
    final l10n = AppLocalizations.of(context)!;
    final count = selectedTasks.length;
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: l10n.delete,
      message: l10n.removeSelectedDownloadsConfirm(count),
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (confirmed == true && context.mounted) {
      final cubit = context.read<DownloadsCubit>();
      await Future.wait(
          selectedTasks.map((t) => cubit.deleteDownload(t.videoId)));
      if (mounted) setState(() => _selectedVideoIds.clear());
    }
  }

  Future<void> _retrySelectedFailed(
      BuildContext context, List<DownloadTask> selectedTasks) async {
    if (_retryingBatch) return;
    final failedIds = selectedTasks
        .where((t) => t.status == DownloadStatus.failed)
        .map((t) => t.videoId)
        .toList();
    if (failedIds.isEmpty) return;
    final cubit = context.read<DownloadsCubit>();
    setState(() {
      _retryingBatch = true;
      _selectedVideoIds.clear();
    });
    // Paced inside the cubit: a raw concurrent loop here fired every retry at
    // once and tripped YouTube's 429/bot throttling.
    final queued = await cubit.retryDownloads(failedIds);
    if (!mounted) return;
    setState(() => _retryingBatch = false);
    _showRequeued(queued);
  }

  /// Re-queues every failed task with the cubit's pacing and reports the count.
  Future<void> _retryAllFailed() async {
    if (_retryingBatch) return;
    final cubit = context.read<DownloadsCubit>();
    setState(() => _retryingBatch = true);
    final queued = await cubit.retryAllFailed();
    if (!mounted) return;
    setState(() => _retryingBatch = false);
    _showRequeued(queued);
  }

  void _showRequeued(int count) {
    if (count <= 0) return;
    PulsrToast.show(
      context,
      message: context.l10n.downloadsRequeued(count),
      icon: Icons.schedule_rounded,
    );
  }

  Future<void> _addSelectedToPlaylist(
      BuildContext context, List<DownloadTask> completedTasks) async {
    final db = _db;
    if (db == null) return;
    final songIds = completedTasks.map((t) => t.localSongId!).toSet();
    final songs = await (db.select(db.songsTable)
          ..where((t) => t.id.isIn(songIds)))
        .get();
    if (songs.isEmpty || !context.mounted) return;
    await AddToPlaylistSheet.show(
      context,
      song: songs.first,
      songs: songs,
    );
    if (mounted) setState(() => _selectedVideoIds.clear());
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
      if (!context.mounted || !mounted) return;
      if (song == null) {
        PulsrToast.show(
          context,
          message: l10n.songNotFound,
          icon: Icons.music_off_rounded,
          isError: true,
          actionLabel: l10n.delete,
          onActionPressed: () {
            if (!downloadsCubit.isClosed) {
              downloadsCubit.deleteDownload(task.videoId);
            }
          },
        );
        return;
      }
      if (!playerCubit.isClosed) {
        playerCubit.playSong(song);
      }
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

  Future<void> _confirmClearCompleted(
      BuildContext context, List<DownloadTask> completedTasks) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await PulsrDialogHelper.showConfirmDialog(
      context,
      title: l10n.clear,
      message:
          'Remove ${completedTasks.length} completed download${completedTasks.length == 1 ? "" : "s"}?',
      confirmLabel: l10n.clear,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );

    if (confirmed == true && context.mounted) {
      final cubit = context.read<DownloadsCubit>();
      await Future.wait(
        completedTasks.map((t) => cubit.deleteDownload(t.videoId)),
      );
    }
  }
}
