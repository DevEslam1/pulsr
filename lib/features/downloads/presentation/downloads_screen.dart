// lib/features/downloads/presentation/downloads_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../cubit/downloads_cubit.dart';
import '../cubit/downloads_state.dart';
import 'widgets/download_tile.dart';
import 'widgets/storage_stats_header.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

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
      ),
      body: BlocBuilder<DownloadsCubit, DownloadsState>(
        builder: (context, state) {
          if (state.isLoading && state.tasks.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: p.accent),
            );
          }

          final tasks = state.taskList;

          if (tasks.isEmpty) {
            return Column(
              children: [
                if (state.storageStats.totalBytes > 0)
                  StorageStatsHeader(stats: state.storageStats),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
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
              return Padding(
                key: ValueKey(task.videoId),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: DownloadTile(task: task),
              );
            },
          );
        },
      ),
    );
  }
}
