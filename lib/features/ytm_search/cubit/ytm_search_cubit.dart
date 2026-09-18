import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/ytm_error_classifier.dart';
import '../../../core/services/file_intent_handler.dart';
import '../../../core/services/ytm_service.dart';
import '../../../domain/models/ytm_track.dart';
import 'ytm_search_state.dart';

@injectable
class YtmSearchCubit extends Cubit<YtmSearchState> {
  final YtmService _service;
  Timer? _debounceTimer;

  int _generation = 0;

  YtmSearchCubit({required YtmService service})
      : _service = service,
        super(const YtmSearchState());

  static const _historyKey = 'ytm_search_history';
  static const _maxHistory = 20;

  Future<List<String>> getSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_historyKey) ?? [];
    } catch (_) {
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
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (_) {}
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
    emit(state.copyWith(query: query));
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _executeSearch(query);
    });
  }

  void clearQuery() {
    _debounceTimer?.cancel();
    _generation++;
    emit(const YtmSearchState());
  }

  void clearError() {
    emit(state.copyWith(errorMessage: null));
  }

  Future<void> retry() => _executeSearch(state.query);

  Future<void> _executeSearch(
    String query, {
    bool isRetryAfterBotBlock = false,
    int retryDepth = 0,
  }) async {
    final generation = ++_generation;

    if (query.trim().isEmpty) {
      emit(state.copyWith(results: [], isLoading: false, errorMessage: null));
      return;
    }

    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final videoId = FileIntentHandler.extractYouTubeVideoId(query);
      if (videoId != null) {
        try {
          final stream = await _service.resolveStream(videoId);
          if (generation != _generation || isClosed) return;
          final track = YtmTrack(
            videoId: videoId,
            title: stream.title.isNotEmpty ? stream.title : 'YouTube Track',
            artist: stream.artist.isNotEmpty ? stream.artist : 'YouTube Music',
            duration: stream.duration,
            artworkUrl: stream.artworkUrl,
          );
          emit(state.copyWith(
              results: [track], isLoading: false, errorMessage: null));
          return;
        } catch (_) {
          // Fall through to regular search if resolving by ID fails
        }
      }

      final results = await _service.searchWithFallback(query);
      if (generation != _generation || isClosed) return;
      emit(state.copyWith(
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
        } catch (_) {}
      }
    } on YtmException catch (e) {
      if (generation != _generation || isClosed) return;

      // Auto-recovery: On bot block or recaptcha, invalidate poToken and retry with depth bound
      if (e.isBotBlocked && !isRetryAfterBotBlock && retryDepth < 2) {
        var refreshed = false;
        try {
          await _service.invalidatePoToken();
          await _service.ensurePoTokenReady();
          refreshed = true;
        } catch (_) {
          // A failing poToken refresh must not escape this handler, or the
          // spinner below is never cleared and the block is never reported.
        }
        if (generation != _generation || isClosed) return;
        if (refreshed) {
          return _executeSearch(query,
              isRetryAfterBotBlock: true, retryDepth: retryDepth + 1);
        }
      }

      // FIX-C04: Ensure generation guard precedes every emit in catch blocks
      if (generation != _generation || isClosed) return;
      final errorInfo = YtmErrorClassifier.classify(e);
      emit(state.copyWith(
          isLoading: false, results: [], errorMessage: errorInfo.message));
    } catch (e) {
      // FIX-C04: Ensure generation guard precedes emit
      if (generation != _generation || isClosed) return;
      final errorInfo = YtmErrorClassifier.classify(e);
      emit(state.copyWith(
          isLoading: false, results: [], errorMessage: errorInfo.message));
    }
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
