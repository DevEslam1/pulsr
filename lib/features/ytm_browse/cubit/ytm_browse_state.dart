// lib/features/ytm_browse/cubit/ytm_browse_state.dart
import 'package:flutter/foundation.dart';

import '../../../core/services/ytm_browse_service.dart';

/// Why the browse feed could not be refreshed.
///
/// The screen owns the user-facing copy; the cubit only carries the verdict so
/// it stays free of `BuildContext` and is unit-testable.
enum YtmBrowseFailure {
  /// The feed request failed and no cached feed was available.
  loadFailed,
}

/// Why a feed or a single section failed, in terms the screen can turn into
/// actionable copy. The cubit carries the verdict; the widget owns the words.
enum YtmBrowseFailureReason {
  offline,
  geoBlocked,
  botBlocked,
  unavailable,
  unknown,
}

@immutable
class YtmBrowseState {
  const YtmBrowseState({
    this.sections = const <YtmBrowseSection>[],
    this.isLoading = false,
    this.isRefreshing = false,
    this.hasLoaded = false,
    this.failure,
    this.failureReason,
    this.lastUpdatedAt,
    this.sectionFailures = const <String, YtmBrowseFailureReason>{},
    this.refreshingSectionIds = const <String>{},
  });

  /// Non-empty sections only. Empty upstream sections are dropped before they
  /// reach the UI so a section header can never render with no cards under it.
  final List<YtmBrowseSection> sections;

  /// True only for the first load (no sections on screen). A refresh keeps the
  /// existing feed visible and uses [isRefreshing] instead.
  final bool isLoading;

  /// True while a feed that is already on screen is being refreshed.
  final bool isRefreshing;

  /// True once at least one load attempt has completed, successfully or not.
  /// Distinguishes "not loaded yet" from "loaded and genuinely empty".
  final bool hasLoaded;

  final YtmBrowseFailure? failure;

  /// Structured cause of [failure]; null for an unclassified error.
  final YtmBrowseFailureReason? failureReason;

  /// When the currently displayed feed was fetched. Null before the first
  /// successful load.
  final DateTime? lastUpdatedAt;

  /// Per-section failures from a section refresh, keyed by section id. A full
  /// reload clears the map.
  final Map<String, YtmBrowseFailureReason> sectionFailures;

  /// Section ids with a refresh in flight, so each header can show its own
  /// spinner instead of disabling the whole feed.
  final Set<String> refreshingSectionIds;

  bool get isEmpty => sections.isEmpty;

  bool get hasFailure => failure != null;

  /// A stale-while-error feed: content is still usable, but the last refresh
  /// failed. The screen shows a retry banner instead of replacing the feed.
  bool get hasStaleFailure => failure != null && sections.isNotEmpty;

  bool isSectionRefreshing(String id) => refreshingSectionIds.contains(id);

  YtmBrowseFailureReason? sectionFailure(String id) => sectionFailures[id];

  YtmBrowseState copyWith({
    List<YtmBrowseSection>? sections,
    bool? isLoading,
    bool? isRefreshing,
    bool? hasLoaded,
    YtmBrowseFailure? failure,
    YtmBrowseFailureReason? failureReason,
    DateTime? lastUpdatedAt,
    Map<String, YtmBrowseFailureReason>? sectionFailures,
    Set<String>? refreshingSectionIds,
    bool clearFailure = false,
  }) {
    return YtmBrowseState(
      sections: sections ?? this.sections,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      failure: clearFailure ? null : (failure ?? this.failure),
      failureReason:
          clearFailure ? null : (failureReason ?? this.failureReason),
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      sectionFailures: sectionFailures ?? this.sectionFailures,
      refreshingSectionIds: refreshingSectionIds ?? this.refreshingSectionIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YtmBrowseState &&
          listEquals(other.sections, sections) &&
          other.isLoading == isLoading &&
          other.isRefreshing == isRefreshing &&
          other.hasLoaded == hasLoaded &&
          other.failure == failure &&
          other.failureReason == failureReason &&
          other.lastUpdatedAt == lastUpdatedAt &&
          mapEquals(other.sectionFailures, sectionFailures) &&
          setEquals(other.refreshingSectionIds, refreshingSectionIds);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(sections),
        isLoading,
        isRefreshing,
        hasLoaded,
        failure,
        failureReason,
        lastUpdatedAt,
        Object.hashAllUnordered(sectionFailures.entries
            .map((entry) => Object.hash(entry.key, entry.value))),
        Object.hashAllUnordered(refreshingSectionIds),
      );
}
