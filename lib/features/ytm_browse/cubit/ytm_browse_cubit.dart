// lib/features/ytm_browse/cubit/ytm_browse_cubit.dart
import '../../../core/bloc/base_cubit.dart';
import '../../../core/errors/ytm_error_classifier.dart';
import '../../../core/services/ytm_browse_service.dart';
import '../../../core/utils/error_logger.dart';
import 'ytm_browse_state.dart';

/// Owns the YTM browse feed lifecycle.
///
/// The screen previously held `sections`/`_isLoading`/`_error` in `setState`
/// and called the service directly from `initState`. That made overlapping
/// refreshes last-writer-wins and left the feed untestable without pumping a
/// widget tree. This cubit makes the request generation explicit: only the
/// newest [load] may emit, so a slow first request can never overwrite a newer
/// refresh.
class YtmBrowseCubit extends PulsrCubit<YtmBrowseState> {
  YtmBrowseCubit(this._service) : super(const YtmBrowseState());

  final YtmBrowseService _service;

  /// Monotonic request token. Bumped by every [load]; a completion whose token
  /// no longer matches is dropped instead of emitted.
  int _generation = 0;

  /// Loads the home feed. Pass [force] to bypass the service's 6-hour TTL.
  Future<void> load({bool force = false}) async {
    final generation = ++_generation;
    final keepExisting = state.sections.isNotEmpty;

    safeEmit(state.copyWith(
      isLoading: !keepExisting,
      isRefreshing: keepExisting,
      clearFailure: true,
    ));

    try {
      final fetched = await _service.getHomeFeed(force: force);
      if (isClosed || generation != _generation) return;

      final nonEmpty = List<YtmBrowseSection>.unmodifiable(
        fetched.where((section) => section.items.isNotEmpty),
      );
      safeEmit(state.copyWith(
        sections: nonEmpty,
        isLoading: false,
        isRefreshing: false,
        hasLoaded: true,
        lastUpdatedAt: _service.lastFetchTime ?? DateTime.now(),
        sectionFailures: const <String, YtmBrowseFailureReason>{},
        refreshingSectionIds: const <String>{},
        clearFailure: true,
      ));
    } catch (e, st) {
      ErrorLogger.log('Failed to load YTM browse feed',
          error: e, stackTrace: st, category: 'YtmBrowseCubit');
      if (isClosed || generation != _generation) return;

      safeEmit(state.copyWith(
        isLoading: false,
        isRefreshing: false,
        hasLoaded: true,
        failure: YtmBrowseFailure.loadFailed,
        failureReason: classifyBrowseFailure(e),
      ));
    }
  }

  /// Refetches one section in place. A failed section no longer forces the
  /// user to reload the whole feed and lose the sections that succeeded.
  Future<void> refreshSection(YtmBrowseSection section) async {
    if (isClosed || section.id.isEmpty) return;
    if (state.refreshingSectionIds.contains(section.id)) return;

    final id = section.id;
    final generation = _generation;
    safeEmit(state.copyWith(
      refreshingSectionIds: {...state.refreshingSectionIds, id},
      sectionFailures: Map.unmodifiable(
        Map<String, YtmBrowseFailureReason>.from(state.sectionFailures)
          ..remove(id),
      ),
    ));

    try {
      final refreshed = await _service.refreshSection(section);
      if (isClosed || generation != _generation) return;
      if (refreshed.items.isEmpty) {
        _markSectionFailure(id, YtmBrowseFailureReason.unknown);
        return;
      }
      final sections = List<YtmBrowseSection>.unmodifiable([
        for (final existing in state.sections)
          if (existing.id == id) refreshed else existing,
      ]);
      safeEmit(state.copyWith(
        sections: sections,
        refreshingSectionIds: Set.unmodifiable(
          Set<String>.from(state.refreshingSectionIds)..remove(id),
        ),
        sectionFailures: Map.unmodifiable(
          Map<String, YtmBrowseFailureReason>.from(state.sectionFailures)
            ..remove(id),
        ),
      ));
    } catch (e, st) {
      ErrorLogger.log('Failed to refresh YTM browse section $id',
          error: e, stackTrace: st, category: 'YtmBrowseCubit');
      if (isClosed || generation != _generation) return;
      _markSectionFailure(id, classifyBrowseFailure(e));
    }
  }

  void _markSectionFailure(String id, YtmBrowseFailureReason reason) {
    safeEmit(state.copyWith(
      refreshingSectionIds: Set.unmodifiable(
        Set<String>.from(state.refreshingSectionIds)..remove(id),
      ),
      sectionFailures: Map.unmodifiable(
        Map<String, YtmBrowseFailureReason>.from(state.sectionFailures)
          ..[id] = reason,
      ),
    ));
  }

  /// Turns a YTM exception into the copy bucket the screen should use.
  static YtmBrowseFailureReason classifyBrowseFailure(Object error) {
    final signal = YtmErrorClassifier.classify(error).signal;
    switch (signal) {
      case YtmBlockSignal.networkUnavailable:
        return YtmBrowseFailureReason.offline;
      case YtmBlockSignal.geoBlocked:
        return YtmBrowseFailureReason.geoBlocked;
      case YtmBlockSignal.botChallenge:
      case YtmBlockSignal.poTokenInvalid:
      case YtmBlockSignal.ipBlocked:
      case YtmBlockSignal.rateLimited:
      case YtmBlockSignal.signInRequired:
        return YtmBrowseFailureReason.botBlocked;
      case YtmBlockSignal.videoGone:
        return YtmBrowseFailureReason.unavailable;
      case YtmBlockSignal.ageRestricted:
        return YtmBrowseFailureReason.unavailable;
      case YtmBlockSignal.interrupted:
        return YtmBrowseFailureReason.unknown;
      case YtmBlockSignal.clientDeprecated:
      case YtmBlockSignal.signatureDecipherFailed:
      case YtmBlockSignal.sabrEnforced:
      case null:
        return YtmBrowseFailureReason.unknown;
    }
  }
}
