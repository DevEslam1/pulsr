// lib/features/downloads/presentation/downloads_screen.dart
// DL-22: Dismissible × Reorderable conflict resolution & 5s soft-delete undo snackbar.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../domain/models/download_task.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/bloc/base_cubit.dart';
import '../cubit/downloads_cubit.dart';
import '../cubit/downloads_state.dart';
import 'widgets/download_tile.dart';
import 'widgets/storage_stats_header.dart';

/// Offline downloads hub: storage usage header, the task list with
/// swipe-to-delete + undo, and resume-all affordances.
///
/// State is observed exclusively through [DownloadsCubit]; per-tile rebuilds
/// are isolated with [BlocSelector] so progress storms only rebuild the tile
/// whose task actually changed.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  DownloadTask? _recentlyDeletedTask;
  StreamSubscription<UiEffect>? _effectSub;

  @override
  void initState() {
    super.initState();
    // Consume one-shot effects exactly once; effects are never stored in state,
    // so rebuilds can never re-fire a consumed toast.
    _effectSub =
        context.read<DownloadsCubit>().effects.listen((effect) {
      if (!mounted) return;
      if (effect is ShowToastEffect) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(effect.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _effectSub?.cancel();
    super.dispose();
  }

  void _handleDelete(BuildContext context, DownloadTask task) {
    HapticFeedback.mediumImpact();
    final cubit = context.read<DownloadsCubit>();
    final l10n = AppLocalizations.of(context)!;
    _recentlyDeletedTask = task;
    cubit.deleteDownload(task.videoId);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.downloadDeletedSnackbar(task.title)),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () {
            if (_recentlyDeletedTask != null) {
              cubit.queueDownload(_recentlyDeletedTask!);
              _recentlyDeletedTask = null;
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          l10n.downloadsTitle,
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: p.textSecondary),
            tooltip: l10n.settings,
            onPressed: () {
              HapticFeedback.lightImpact();
              context.push('/settings');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: p.accent,
        backgroundColor: p.surfaceContainerHigh,
        onRefresh: () async {
          final cubit = context.read<DownloadsCubit>();
          await HapticFeedback.lightImpact();
          await Future.wait([
            cubit.loadInitialTasks(),
            cubit.refreshStorageStats(),
          ]);
        },
        child: BlocBuilder<DownloadsCubit, DownloadsState>(
          builder: (context, state) {
            if (state.isLoading && state.tasks.isEmpty) {
              return Center(
                child: CircularProgressIndicator(color: p.accent),
              );
            }

            final tasks = state.taskList;

            if (tasks.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (state.storageStats.totalBytes > 0)
                    StorageStatsHeader(stats: state.storageStats),
                  if (state.showNotificationPermissionBanner)
                    Padding(
                      key: const ValueKey('notification_permission_banner'),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.error.withValues(alpha: 0.3)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.notifications_off_outlined, color: p.error, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Notifications disabled. Download progress won\'t appear in your shade, but downloads continue.',
                                style: TextStyle(color: p.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: p.textSecondary, size: 18),
                              onPressed: () => context.read<DownloadsCubit>().dismissNotificationBanner(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 80.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.download_done_rounded,
                          size: 64,
                          color: p.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.noDownloadsTitle,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.noDownloadsSubtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: tasks.length + 1,
            findChildIndexCallback: (Key key) {
              if (key is ValueKey<String>) {
                final id = key.value;
                if (id == 'storage_stats_header') return 0;
                final idx = tasks.indexWhere((t) => (t.id.isNotEmpty ? t.id : t.videoId) == id);
                return idx >= 0 ? idx + 1 : null;
              }
              return null;
            },
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BlocSelector<DownloadsCubit, DownloadsState, StorageStats>(
                      selector: (s) => s.storageStats,
                      builder: (_, stats) => StorageStatsHeader(
                        key: const ValueKey('storage_stats_header'),
                        stats: stats,
                      ),
                    ),
                    if (state.showNotificationPermissionBanner)
                      Padding(
                        key: const ValueKey('notification_permission_banner'),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: p.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: p.error.withValues(alpha: 0.3)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.notifications_off_outlined, color: p.error, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Notifications disabled. Download progress won\'t appear in your shade, but downloads continue.',
                                  style: TextStyle(color: p.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, color: p.textSecondary, size: 18),
                                onPressed: () => context.read<DownloadsCubit>().dismissNotificationBanner(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (state.hasPausedTasks)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: p.accent.withValues(alpha: 0.3)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, color: p.accent, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${state.pausedCount} ${l10n.statusPaused}',
                                  style: TextStyle(color: p.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                              TextButton(
                                onPressed: () => context.read<DownloadsCubit>().resumeAllPaused(),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  backgroundColor: p.accent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(
                                  l10n.resume,
                                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              }

              final task = tasks[index - 1];
              final uniqueKey = task.id.isNotEmpty ? task.id : task.videoId;
              return Padding(
                key: ValueKey(uniqueKey),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Dismissible(
                  key: ValueKey('dismiss_$uniqueKey'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: p.error,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    if (task.status.isActive) {
                      return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l10n.cancel),
                          content: Text(l10n.deleteSongConfirmation),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: Text(l10n.cancel),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: Text(l10n.delete,
                                  style: TextStyle(color: p.error)),
                            ),
                          ],
                        ),
                      ) ?? false;
                    }
                    return true;
                  },
                  onDismissed: (_) => _handleDelete(context, task),
                  child: BlocSelector<DownloadsCubit, DownloadsState, DownloadTask?>(
                    selector: (s) => s.byId(uniqueKey),
                    builder: (_, currentTask) {
                      if (currentTask == null) return const SizedBox.shrink();
                      return DownloadTile(task: currentTask);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}
}

