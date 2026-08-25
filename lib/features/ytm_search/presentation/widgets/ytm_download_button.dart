import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../data/db/app_database.dart';
import '../../cubit/ytm_download_cubit.dart';

/// Per-result download control: shows an idle download icon, a determinate
/// progress ring while transferring, a check once it lands in the library, and
/// a retry icon on failure. Keyed by the track's video id so its state survives
/// list reordering.
class YtmDownloadButton extends StatelessWidget {
  final SongsTableData song;
  final Color? activeColor;
  final Color? iconColor;
  final double iconSize;

  const YtmDownloadButton({
    super.key,
    required this.song,
    this.activeColor,
    this.iconColor,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.ytmEnabled) return const SizedBox.shrink();

    final p = context.palette;
    final videoId = song.remoteId ?? '';
    if (videoId.isEmpty) return const SizedBox.shrink();

    final tintColor = activeColor ?? p.accent;
    final baseColor = iconColor ?? p.textTertiary;

    final cubit = context.watch<YtmDownloadCubit?>() ?? getIt<YtmDownloadCubit>();

    return BlocBuilder<YtmDownloadCubit, YtmDownloadState>(
      bloc: cubit,
      buildWhen: (a, b) =>
          a.itemFor(videoId).status != b.itemFor(videoId).status ||
          a.itemFor(videoId).progress != b.itemFor(videoId).progress,
      builder: (context, state) {
        final item = state.itemFor(videoId);
        final isAlreadyLocal = song.source == SongSource.local && (song.remoteId != null && song.remoteId!.isNotEmpty);
        if (isAlreadyLocal || item.status == YtDownloadStatus.done) {
          return SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.download_done_rounded, size: iconSize, color: tintColor),
          );
        }

        switch (item.status) {
          case YtDownloadStatus.queued:
          case YtDownloadStatus.running:
            return SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    value: item.status == YtDownloadStatus.queued ? null : item.progress,
                    color: tintColor,
                  ),
                ),
              ),
            );
          case YtDownloadStatus.done:
            return SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.download_done_rounded, size: iconSize, color: tintColor),
            );
          case YtDownloadStatus.failed:
            return IconButton(
              tooltip: item.error,
              icon: Icon(Icons.error_outline_rounded, size: iconSize, color: p.error),
              onPressed: () => cubit.download(song),
              visualDensity: VisualDensity.compact,
            );
          case YtDownloadStatus.canceled:
          case YtDownloadStatus.idle:
            return IconButton(
              tooltip: 'Download offline',
              icon: Icon(Icons.download_rounded, size: iconSize, color: baseColor),
              onPressed: () => cubit.download(song),
              visualDensity: VisualDensity.compact,
            );
        }
      },
    );
  }
}
