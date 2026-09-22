import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/bloc/base_cubit.dart';
import '../../../core/errors/ytm_error_classifier.dart';
import '../../../core/services/file_intent_handler.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../domain/models/ytm_track.dart';
import 'ytm_search_state.dart';

// FIX-A01: Migrate to PulsrCubit
@injectable
class YtmSearchCubit extends PulsrCubit<YtmSearchState> {
  final YtmService _service;
  Timer? _debounceTimer;

  int _generation = 0;
  // FIX-C7: Latch to prevent concurrent bot-block retries
  bool _botRetryInFlight = false;

  YtmSearchCubit({required YtmService service})
      : _service = service,
        super(const YtmSearchState());

  static const _historyKey = 'ytm_search_history';
  static const _maxHistory = 20;

  Future<List<String>> getSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_historyKey) ?? [];
    } catch (e, st) {
      // FIX-A05: Log failure to read history
      ErrorLogger.log('Failed to read search history', error: e, stackTrace: st, category: 'YtmSearchCubit');
      return [];
    }
  }

  Future<void> _saveToHistory(String query) async {
    final q = query.trim();
    if (q.isEmpty || q.length < 2) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_historyKey) ?? [];
      list.remove(q);
      list.insert(0, q);
      if (list.length > _maxHistory) list.removeRange(_maxHistory, list.length);
      await prefs.setStringList(_historyKey, list);
    } catch (e, st) {
      // FIX-A05: Log failure to save history
      ErrorLogger.log('Failed to save query to search history', error: e, stackTrace: st, category: 'YtmSearchCubit');
    }
  }

  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (e, st) {
      // FIX-A05: Log failure to clear history
      ErrorLogger.log('Failed to clear search history', error: e, stackTrace: st, category: 'YtmSearchCubit');
    }
  }

  /// Persistent YTM health strip for the search screen: bot cooldown, offline
  /// (last error was connectivity), or null when healthy. The cooldown half is
  /// pushed to the UI via [botCooldown] so the screen never polls.
  String? get statusMessage => statusMessageFor(_service.isBotCoolingDown);

  /// Cooldown transitions from [YtmService], so the health strip can react
  /// without a periodic setState.
  ValueListenable<bool> get botCooldown => _service.botCooldownNotifier;

  String? statusMessageFor(bool coolingDown) {
    if (coolingDown) {
      return 'YTM cooling down (bot protection) — retry shortly';
    }
    final err = state.errorMessage;
    if (err != null && err.isNotEmpty) {
      final lower = err.toLowerCase();
      if (lower.contains('offline') ||
          lower.contains('network') ||
          lower.contains('connection') ||
          lower.contains('timeout')) {
        return 'YTM offline — showing local results';
      }
    }
    return null;
  }

  void onQueryChanged(String query) {
    safeEmit(state.copyWith(query: query));
    _debounceTimer?.cancel();
    _debounceTimer = autoTimer(Timer(const Duration(milliseconds: 300), () {
      _executeSearch(query);
    }));
  }

  void clearQuery() {
    _debounceTimer?.cancel();
    _generation++;
    safeEmit(const YtmSearchState());
  }

  void clearError() {
    safeEmit(state.copyWith(errorMessage: null));
  }

  Future<void> retry() => _executeSearch(state.query);

  Future<void> retryAfterCooldown() async {
    if (_service.isBotCoolingDown) {
      safeEmit(state.copyWith(
        errorMessage: 'YouTube is rate-limiting requests. Please wait a few minutes.',
      ));
      while (_service.isBotCoolingDown && !isClosed) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (isClosed) return;
    }
    await retry();
  }

  Future<void> _executeSearch(
    String query, {
    bool isRetryAfterBotBlock = false,
    int retryDepth = 0,
    int? generation,
  }) async {
    // FIX-C7: Parameterize generation and do not increment on recursive retry
    final effectiveGeneration = generation ?? ++_generation;

    if (query.trim().isEmpty) {
      safeEmit(state.copyWith(results: [], isLoading: false, errorMessage: null));
      return;
    }

    safeEmit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final videoId = FileIntentHandler.extractYouTubeVideoId(query);
      if (videoId != null) {
        try {
          final stream = await _service.resolveStream(videoId);
          if (effectiveGeneration != _generation || isClosed) return;
          final track = YtmTrack(
            videoId: videoId,
            title: stream.title.isNotEmpty ? stream.title : 'YouTube Track',
            artist: stream.artist.isNotEmpty ? stream.artist : 'YouTube Music',
            duration: stream.duration,
            artworkUrl: stream.artworkUrl,
          );
          safeEmit(state.copyWith(
              results: [track], isLoading: false, errorMessage: null));
          return;
        } catch (e, st) {
          // FIX-A05: Log failure before falling back to regular search
          ErrorLogger.log('Failed to resolve stream by video ID, falling back to text search',
              error: e, stackTrace: st, category: 'YtmSearchCubit');
        }
      }

      final results = await _service.searchWithFallback(query);
      if (effectiveGeneration != _generation || isClosed) return;
      safeEmit(state.copyWith(
          results: results, isLoading: false, errorMessage: null));
      if (results.isNotEmpty) unawaited(_saveToHistory(query));
      // Speculative warm: the top hit is the most likely tap. Resolving its
      // stream URL now (one background player request) turns that tap into a
      // cache hit (~62ms) instead of a full multi-engine resolve (seconds).
      // Skipped while bot-cooling so a flagged IP isn't hammered further.
      // Fully defensive: warming must never disturb search results.
      if (results.isNotEmpty) {
        try {
          final topId = results.first.videoId;
          if (topId.isNotEmpty && !_service.isBotCoolingDown) {
            unawaited(_service
                .resolveStream(topId)
                .timeout(const Duration(seconds: 25))
                .then((_) {})
                .catchError((_) {}));
          }
        } catch (_) {
          // FIX-A05: Speculative warming failure is intentionally non-fatal
        }
      }
    } on YtmException catch (e) {
      if (effectiveGeneration != _generation || isClosed) return;

      // FIX-C7: Auto-recovery with _botRetryInFlight latch
      if (e.isBotBlocked && !isRetryAfterBotBlock && retryDepth < 2 && !_botRetryInFlight) {
        _botRetryInFlight = true;
        try {
          var refreshed = false;
          try {
            await _service.invalidatePoToken();
            await _service.ensurePoTokenReady();
            refreshed = true;
          } catch (e2, st2) {
            // FIX-A05: Log failed token refresh during bot block recovery
            ErrorLogger.log('Failed poToken refresh in recovery',
                error: e2, stackTrace: st2, category: 'YtmSearchCubit');
          }
          if (effectiveGeneration != _generation || isClosed) return;
          if (refreshed) {
            try {
              await _executeSearch(
                query,
                isRetryAfterBotBlock: true,
                retryDepth: retryDepth + 1,
                generation: effectiveGeneration,
              );
              return;
            } catch (retryErr, retrySt) {
              ErrorLogger.log('Bot block retry search failed',
                  error: retryErr, stackTrace: retrySt, category: 'YtmSearchCubit');
              return;
            }
          }
        } finally {
          _botRetryInFlight = false;
        }
      }

      // FIX-C04: Ensure generation guard precedes every emit in catch blocks
      if (effectiveGeneration != _generation || isClosed) return;
      final errorInfo = YtmErrorClassifier.classify(e);
      final msg = e.isBotBlocked
          ? 'YouTube is rate-limiting requests. Please wait a few minutes.'
          : errorInfo.message;
      safeEmit(state.copyWith(
          isLoading: false, results: [], errorMessage: msg));
    } catch (e) {
      // FIX-C04: Ensure generation guard precedes emit
      if (effectiveGeneration != _generation || isClosed) return;
      final errorInfo = YtmErrorClassifier.classify(e);
      safeEmit(state.copyWith(
          isLoading: false, results: [], errorMessage: errorInfo.message));
    }
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
