// lib/features/ytm_search/cubit/ytm_download_cubit.dart
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/yt_download_service.dart';
import '../../../data/db/app_database.dart';
import '../../player/cubit/player_cubit.dart';

enum YtDownloadStatus { idle, queued, running, done, failed, canceled }

class YtDownloadItem {
  final YtDownloadStatus status;

  /// 0..1 while bytes are transferring, null during resolve/tag/index.
  final double? progress;
  final String? error;

  const YtDownloadItem({this.status = YtDownloadStatus.idle, this.progress, this.error});

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'error': error,
      };

  factory YtDownloadItem.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'idle';
    final status = YtDownloadStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => YtDownloadStatus.idle,
    );
    return YtDownloadItem(
      status: status,
      error: json['error'] as String?,
    );
  }
}

class YtmDownloadState {
  /// Keyed by videoId so state survives list reordering.
  final Map<String, YtDownloadItem> items;

  const YtmDownloadState({this.items = const {}});

  YtDownloadItem itemFor(String videoId) => items[videoId] ?? const YtDownloadItem();
}

@injectable
class YtmDownloadCubit extends Cubit<YtmDownloadState> {
  static const String _prefKey = 'ytm_download_states';
  final YtDownloadService _service;
  final PlayerCubit _playerCubit;

  YtmDownloadCubit(this._service, this._playerCubit) : super(const YtmDownloadState()) {
    _loadPersistedState();
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final rawMap = jsonDecode(jsonStr) as Map<String, dynamic>;
        final restored = rawMap.map((k, v) => MapEntry(k, YtDownloadItem.fromJson(v as Map<String, dynamic>)));
        if (!isClosed) {
          emit(YtmDownloadState(items: restored));
        }
      }
    } catch (_) {}
  }

  Future<void> _savePersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mapToSave = state.items.map((k, v) => MapEntry(k, v.toJson()));
      await prefs.setString(_prefKey, jsonEncode(mapToSave));
    } catch (_) {}
  }

  void cancelDownload(String videoId) {
    _service.cancel(videoId);
    _set(videoId, const YtDownloadItem(status: YtDownloadStatus.canceled));
  }

  Future<void> download(SongsTableData song) async {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;
    final current = state.itemFor(videoId);
    if (current.status == YtDownloadStatus.running ||
        current.status == YtDownloadStatus.queued ||
        current.status == YtDownloadStatus.done) {
      return;
    }

    _set(videoId, const YtDownloadItem(status: YtDownloadStatus.queued, progress: 0));

    final result = await _service.download(song, onProgress: (p) {
      if (isClosed) return;
      if (p.stage == YtDownloadStage.canceled) {
        _set(videoId, const YtDownloadItem(status: YtDownloadStatus.canceled));
        return;
      }
      _set(videoId, YtDownloadItem(
        status: p.stage == YtDownloadStage.queued ? YtDownloadStatus.queued : YtDownloadStatus.running,
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
    await _playerCubit.swapReconciledSong(song.id, newId);
    if (!isClosed) _set(videoId, const YtDownloadItem(status: YtDownloadStatus.done));
  }

  void _set(String videoId, YtDownloadItem item) {
    emit(YtmDownloadState(items: {...state.items, videoId: item}));
    _savePersistedState();
  }
}
