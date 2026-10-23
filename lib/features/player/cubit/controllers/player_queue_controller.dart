// lib/features/player/cubit/controllers/player_queue_controller.dart
// FIX-A1: Focused PlayerQueueController extracted from PlayerCubit
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/services/radio_station_store.dart';
import '../../../../core/services/ytm_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/telemetry/playback_latency_tracker.dart';
import '../../../../core/utils/async_guard.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../../../../domain/models/radio_station.dart';
import '../../../../domain/repositories/music_repository_interface.dart';
import '../../../../data/scanner/media_scanner_service.dart';
import '../player_state.dart';
import '../queue_slot_codec.dart';
import 'queue_slot_data.dart';

part 'player_queue_playback.dart';
part 'player_queue_slots.dart';
part 'player_queue_warming.dart';
part 'player_queue_radio.dart';

/// Controls playback queue management, slot switching, and reordering.
class PlayerQueueController {
  static const int maxQueueSize = 500;

  final PulsrAudioHandler _audioHandler;
  final IMusicRepository _repository;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final bool Function() _isClosed;
  final Mutex _queueMutex;
  final Map<int, SongsTableData> _slotLookupCache;
  final Map<int, QueueSlotData> _queueSlots;
  final void Function({bool force}) _updateWidgetThrottled;
  final void Function(SongsTableData song) _loadLyrics;
  final void Function() _debouncedPersistQueueSlots;
  final void Function() _bumpQueueVersion;
  final bool Function(SongsTableData? a, SongsTableData? b) _isSameTrack;
  final PlaybackLatencyTracker? _latencyTracker;
  final MediaScannerService? _mediaScannerService;
  final YtmService? _ytmService;

  /// A-01: Invoked when a track is resumed (initialPosition provided) so the
  /// per-song speed/pitch/volume/EQ memory can be re-applied.
  final void Function(SongsTableData song)? _onResumePerSongMemory;

  /// Invalidates any in-flight restored-queue resolver on the owning cubit so a
  /// slow DB lookup for an older engine-queue snapshot cannot clobber a
  /// just-applied programmatic queue mutation. No-op when not wired.
  final void Function() _invalidateQueueSyncResolution;

  /// Drops any coalesced trailing seek on the transport so a track change
  /// cannot land a pending seek from the previous track. No-op when not wired.
  final void Function() _cancelPendingSeek;

  Timer? _persistQueueDebounce;

  // Async guards for coordination
  final AsyncGuard _mediaItemResolutionGuard = AsyncGuard();
  final AsyncGuard _localMatchSwapGuard = AsyncGuard();
  final AsyncGuard _mediaItemGuard = AsyncGuard();
  final AsyncGuard _lyricsGuard = AsyncGuard();

  AsyncGuard get mediaItemResolutionGuard => _mediaItemResolutionGuard;
  AsyncGuard get localMatchSwapGuard => _localMatchSwapGuard;
  AsyncGuard get mediaItemGuard => _mediaItemGuard;
  AsyncGuard get lyricsGuard => _lyricsGuard;

  bool _isSwitchingSlot = false;

  PlayerQueueController({
    required PulsrAudioHandler audioHandler,
    required IMusicRepository repository,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required bool Function() isClosed,
    required Mutex queueMutex,
    required Map<int, SongsTableData> slotLookupCache,
    required Map<int, QueueSlotData> queueSlots,
    required void Function({bool force}) updateWidgetThrottled,
    required void Function(SongsTableData song) loadLyrics,
    void Function()? debouncedPersistQueueSlots,
    required void Function() bumpQueueVersion,
    required bool Function(SongsTableData? a, SongsTableData? b) isSameTrack,
    PlaybackLatencyTracker? latencyTracker,
    MediaScannerService? mediaScannerService,
    YtmService? ytmService,
    void Function(SongsTableData song)? onResumePerSongMemory,
    void Function()? invalidateQueueSyncResolution,
    void Function()? cancelPendingSeek,
  })  : _audioHandler = audioHandler,
        _repository = repository,
        _getState = getState,
        _emit = emit,
        _isClosed = isClosed,
        _queueMutex = queueMutex,
        _slotLookupCache = slotLookupCache,
        _queueSlots = queueSlots,
        _updateWidgetThrottled = updateWidgetThrottled,
        _loadLyrics = loadLyrics,
        _debouncedPersistQueueSlots = debouncedPersistQueueSlots ?? (() {}),
        _bumpQueueVersion = bumpQueueVersion,
        _isSameTrack = isSameTrack,
        _latencyTracker = latencyTracker,
        _mediaScannerService = mediaScannerService,
        _ytmService = ytmService,
        _onResumePerSongMemory = onResumePerSongMemory,
        _invalidateQueueSyncResolution =
            invalidateQueueSyncResolution ?? (() {}),
        _cancelPendingSeek = cancelPendingSeek ?? (() {});

  void dispose() {
    if (_persistQueueDebounce != null) {
      _persistQueueDebounce?.cancel();
      _persistQueueDebounce = null;
      persistQueueSlotsNow();
    }
    _mediaItemResolutionGuard.invalidate();
    _localMatchSwapGuard.invalidate();
    _mediaItemGuard.invalidate();
    _lyricsGuard.invalidate();
  }
}
