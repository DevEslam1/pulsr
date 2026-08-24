// lib/features/ytm_search/cubit/ytm_download_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../core/services/yt_download_service.dart';
import '../../../data/db/app_database.dart';
import '../../player/cubit/player_cubit.dart';

enum YtDownloadStatus { idle, running, done, failed }

class YtDownloadItem {
  final YtDownloadStatus status;

  /// 0..1 while the bytes are transferring, null during resolve/tag/index.
  final double? progress;
  final String? error;

  const YtDownloadItem({this.status = YtDownloadStatus.idle, this.progress, this.error});
}

class YtmDownloadState {
  /// Keyed by videoId so state survives list reordering as results change.
  final Map<String, YtDownloadItem> items;

  const YtmDownloadState({this.items = const {}});

  YtDownloadItem itemFor(String videoId) => items[videoId] ?? const YtDownloadItem();
}

@injectable
class YtmDownloadCubit extends Cubit<YtmDownloadState> {
  final YtDownloadService _service;
  final PlayerCubit _playerCubit;

  YtmDownloadCubit(this._service, this._playerCubit) : super(const YtmDownloadState());

  Future<void> download(SongsTableData song) async {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;
    final current = state.itemFor(videoId);
    if (current.status == YtDownloadStatus.running || current.status == YtDownloadStatus.done) return;

    _set(videoId, const YtDownloadItem(status: YtDownloadStatus.running, progress: 0));

    final result = await _service.download(song, onProgress: (p) {
      if (isClosed) return;
      _set(videoId, YtDownloadItem(
        status: YtDownloadStatus.running,
        progress: p.stage == YtDownloadStage.downloading ? p.fraction : null,
      ));
    });
    if (isClosed) return;

    if (result.isLeft()) {
      final message = result.getLeft().toNullable()?.message ?? 'Download failed';
      _set(videoId, YtDownloadItem(status: YtDownloadStatus.failed, error: message));
      return;
    }

    final newId = result.getOrElse((_) => song.id);
    // Keep the player's in-memory queue pointing at the new local row.
    await _playerCubit.swapReconciledSong(song.id, newId);
    if (!isClosed) _set(videoId, const YtDownloadItem(status: YtDownloadStatus.done));
  }

  void _set(String videoId, YtDownloadItem item) {
    emit(YtmDownloadState(items: {...state.items, videoId: item}));
  }
}
