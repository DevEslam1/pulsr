// lib/features/downloads/presentation/downloads_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/errors/error_message_resolver.dart';
import '../../../../core/theme/aura_theme.dart';
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

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

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
                    style: TextStyle(color: p.accent, fontSize: AppFontSize.bodySmall),
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

          final tasks = state.taskList;

          // FIX-A11: Pull-to-refresh on downloads screen
          Widget content;
          if (tasks.isEmpty) {
            content = LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
              itemCount: tasks.length + 1,
              findChildIndexCallback: (Key key) {
                if (key is ValueKey<String>) {
                  final id = key.value;
                  if (id == 'storage_stats_header') return 0;
                  final idx = tasks.indexWhere((t) => t.videoId == id);
                  return idx >= 0 ? idx + 1 : null;
                }
                return null;
              },
              itemBuilder: (context, index) {
                if (index == 0) {
                  return StorageStatsHeader(
                    key: const ValueKey('storage_stats_header'),
                    stats: state.storageStats,
                  );
                }

                final task = tasks[index - 1];
                final playable =
                    task.status == DownloadStatus.complete &&
                        task.localSongId != null;
                return Padding(
                  key: ValueKey(task.videoId),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.s6),
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
    } catch (_) {
      if (context.mounted) {
        PulsrToast.show(context,
            message: AppLocalizations.of(context)!.songNotFound,
            icon: Icons.music_off_rounded,
            isError: true);
      }
    }
  }
}
