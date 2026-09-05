import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

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

      final errorInfo = YtmErrorClassifier.classify(e);
      emit(state.copyWith(
          isLoading: false, results: [], errorMessage: errorInfo.message));
    } catch (e) {
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
