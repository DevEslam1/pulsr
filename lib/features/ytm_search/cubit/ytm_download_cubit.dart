// lib/features/ytm_search/cubit/ytm_download_cubit.dart
import 'dart:async';
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
  final double? progress;
  final double? speedKbps;
  final int? etaSeconds;
  final String? error;
  const YtDownloadItem({
    this.status = YtDownloadStatus.idle,
    this.progress,
    this.speedKbps,
    this.etaSeconds,
    this.error,
  });

  Map<String, dynamic> toJson() => {'status': status.name, 'error': error};
  factory YtDownloadItem.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'idle';
    return YtDownloadItem(
      status: YtDownloadStatus.values.firstWhere((e) => e.name == statusName,
          orElse: () => YtDownloadStatus.idle),
      error: json['error'] as String?,
    );
  }
}

class YtmDownloadState {
  final Map<String, YtDownloadItem> items;
  const YtmDownloadState({this.items = const {}});
  YtDownloadItem itemFor(String videoId) =>
      items[videoId] ?? const YtDownloadItem();
}

@singleton
class YtmDownloadCubit extends Cubit<YtmDownloadState> {
  static const String _prefKey = 'ytm_download_states';
  final YtDownloadService _service;
  final PlayerCubit _playerCubit;

  Timer? _saveDebounce; // ⚡ FIX: Debounce timer for I/O operations
  final Map<String, int> _lastEmitTimeByVideoId = {};

  YtmDownloadCubit(this._service, this._playerCubit)
      : super(const YtmDownloadState()) {
    _loadPersistedState();
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final rawMap = jsonDecode(jsonStr) as Map<String, dynamic>;
        final restored = rawMap.map((k, v) {
          final item = YtDownloadItem.fromJson(v as Map<String, dynamic>);
          final cleanItem = (item.status == YtDownloadStatus.running ||
                  item.status == YtDownloadStatus.queued)
              ? const YtDownloadItem(status: YtDownloadStatus.idle)
              : item;
          return MapEntry(k, cleanItem);
        });
        if (!isClosed) {
          emit(YtmDownloadState(items: {...restored, ...state.items}));
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
    if ([
      YtDownloadStatus.running,
      YtDownloadStatus.queued,
      YtDownloadStatus.done
    ].contains(current.status)) {
      return;
    }

    _set(videoId,
        const YtDownloadItem(status: YtDownloadStatus.queued, progress: 0));

    final result = await _service.download(song, onProgress: (p) {
      if (isClosed) return;
      if (p.stage == YtDownloadStage.canceled) {
        _set(videoId, const YtDownloadItem(status: YtDownloadStatus.canceled));
        return;
      }
      _set(
          videoId,
          YtDownloadItem(
            status: p.stage == YtDownloadStage.queued
                ? YtDownloadStatus.queued
                : YtDownloadStatus.running,
            progress:
                p.stage == YtDownloadStage.downloading ? p.fraction : null,
            speedKbps:
                p.stage == YtDownloadStage.downloading ? p.speedKbps : null,
            etaSeconds:
                p.stage == YtDownloadStage.downloading ? p.etaSeconds : null,
          ));
    });

    if (state.itemFor(videoId).status == YtDownloadStatus.canceled) return;
    if (result.isLeft()) {
      if (isClosed) return;
      final message =
          result.getLeft().toNullable()?.message ?? 'Download failed';
      _set(videoId,
          YtDownloadItem(status: YtDownloadStatus.failed, error: message));
      return;
    }

    final newId = result.getOrElse((_) => song.id);
    await _playerCubit.swapReconciledSong(song.id, newId);
    _set(videoId, const YtDownloadItem(status: YtDownloadStatus.done));
  }

  /// Queues multiple songs for download in batch.
  /// Downloads are processed concurrently according to the service limit (3 active).
  /// Returns the number of songs newly queued.
  int downloadAll(Iterable<SongsTableData> songs) {
    int queuedCount = 0;
    for (final song in songs) {
      final videoId = song.remoteId;
      if (videoId == null || videoId.isEmpty) continue;

      // Skip tracks that are already local on disk
      if (song.source == SongSource.local) continue;

      final current = state.itemFor(videoId);
      if ([
        YtDownloadStatus.running,
        YtDownloadStatus.queued,
        YtDownloadStatus.done
      ].contains(current.status)) {
        continue;
      }

      download(song);
      queuedCount++;
    }
    return queuedCount;
  }

  static const int _maxThrottleEntries = 200;

  void _set(String videoId, YtDownloadItem item) {
    if (isClosed) return;

    if (_lastEmitTimeByVideoId.length >= _maxThrottleEntries &&
        !_lastEmitTimeByVideoId.containsKey(videoId)) {
      _lastEmitTimeByVideoId.remove(_lastEmitTimeByVideoId.keys.first);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastEmit = _lastEmitTimeByVideoId[videoId] ?? 0;

    // Throttle progress updates to at most 5 updates/sec (>= 200ms interval) per videoId.
    // State transitions (e.g. idle -> queued -> running -> done/failed/canceled) and completion (progress >= 1.0)
    // are emitted immediately without throttling.
    final currentItem = state.itemFor(videoId);
    final isIntermediateProgress = item.status == YtDownloadStatus.running &&
        currentItem.status == YtDownloadStatus.running &&
        item.progress != null &&
        item.progress! < 1.0;

    if (isIntermediateProgress && (now - lastEmit < 200)) {
      return;
    }

    _lastEmitTimeByVideoId[videoId] = now;
    emit(YtmDownloadState(items: {...state.items, videoId: item}));

    // Persist only on terminal states to avoid disk churn during downloads
    if (item.status == YtDownloadStatus.done ||
        item.status == YtDownloadStatus.failed ||
        item.status == YtDownloadStatus.canceled) {
      _lastEmitTimeByVideoId.remove(videoId);
      _saveDebounce?.cancel();
      _saveDebounce = Timer(const Duration(milliseconds: 1500), () {
        _saveDebounce = null;
        _savePersistedState();
      });
    }
  }

  @override
  Future<void> close() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _savePersistedState();
    _lastEmitTimeByVideoId.clear();
    return super.close();
  }
}
