// lib/features/home/cubit/home_cubit.dart
import 'dart:async';

import '../../../core/bloc/base_cubit.dart';
import '../../../core/network/connectivity_guard.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../domain/models/ytm_track.dart';

/// Minimal state: [loginEpoch] bumps whenever the account login state flips so
/// the screen can reset its selected category, and [isLoggedIn] mirrors the
/// account service.
class HomeState {
  const HomeState({this.loginEpoch = 0, this.isLoggedIn = false});

  final int loginEpoch;
  final bool isLoggedIn;

  HomeState copyWith({int? loginEpoch, bool? isLoggedIn}) => HomeState(
        loginEpoch: loginEpoch ?? this.loginEpoch,
        isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      );
}

/// Owns the Home online-category data fetching and its TTL cache so the UI no
/// longer calls YTM services directly or manages future maps (I2).
class HomeCubit extends PulsrCubit<HomeState> {
  HomeCubit({
    required YtmService ytmService,
    required YtmAccountService accountService,
    Stopwatch? clock,
  })  : _ytm = ytmService,
        _account = accountService,
        _monotonicClock = (clock ?? Stopwatch())..start(),
        super(HomeState(isLoggedIn: accountService.isLoggedIn)) {
    _account.loginState.addListener(_onLoginChanged);
  }

  final YtmService _ytm;
  final YtmAccountService _account;
  final Stopwatch _monotonicClock;

  /// Resolved once and reused across rebuilds with a 10-minute TTL.
  static const Duration categoryTtl = Duration(minutes: 10);

  // FIX-L03: Single source of truth for categories, queries, and login requirements
  static const List<(String name, String query, bool requiresLogin)> _allCategories = [
    ('Recommended For You', 'recommended music', true),
    ('Trending Egypt', 'أغاني مصرية جديدة تريند', false),
    ('Mahraganat', 'مهرجانات مصرية جديدة', false),
    ('Arabic Pop', 'أغاني عربي عمرو دياب تامر حسني حماقي', false),
    ('Global Top Hits', 'global top hits songs', false),
    ('New Releases', 'new music releases', false),
    ('Chill & Lo-Fi', 'chill lofi beats', false),
    ('Pop Mix', 'pop hits playlist', false),
    ('Hip-Hop', 'arabic hip hop rap ويجز', false),
    ('Workout Energy', 'workout gym motivation music', false),
    ('Rock & Metal', 'rock metal playlist', false),
    ('Acoustic', 'acoustic guitar relax', false),
  ];

  static final Map<String, String> categoryQueries = {
    for (final c in _allCategories) c.$1: c.$2,
  };

  static final List<String> _loggedInCategories =
      _allCategories.map((c) => c.$1).toList();

  static final List<String> _anonymousCategories =
      _allCategories.where((c) => !c.$3).map((c) => c.$1).toList();

  final Map<String, Future<List<YtmTrack>>> _categoryFutures = {};
  final Map<String, int> _categoryFetchTimestamps = {};
  // FIX-H6: Track in-flight categories to prevent TTL eviction while request is pending
  final Set<String> _inFlightCategories = {};

  bool get isLoggedIn => _account.isLoggedIn;

  List<String> get onlineCategories =>
      isLoggedIn ? _loggedInCategories : _anonymousCategories;

  void _onLoginChanged() {
    clearCache();
    if (isClosed) return;
    safeEmit(state.copyWith(
      loginEpoch: state.loginEpoch + 1,
      isLoggedIn: isLoggedIn,
    ));
  }

  static const int _maxCachedCategories = 20;

  /// Returns the cached future for [category], refetching once its TTL lapses.
  Future<List<YtmTrack>> categoryFuture(String category) {
    final existingFuture = _categoryFutures[category];
    if (existingFuture != null) {
      if (_inFlightCategories.contains(category)) {
        return existingFuture;
      }
      final nowMs = _monotonicClock.elapsedMilliseconds;
      final lastFetchMs = _categoryFetchTimestamps[category];
      if (lastFetchMs != null &&
          (nowMs - lastFetchMs <= categoryTtl.inMilliseconds)) {
        return existingFuture;
      }
      // TTL expired and not in-flight: evict stale entry
      _categoryFutures.remove(category);
      _categoryFetchTimestamps.remove(category);
    }

    // Prune oldest non-in-flight entries if exceeding capacity
    if (_categoryFutures.length >= _maxCachedCategories) {
      final evictable = _categoryFetchTimestamps.entries
          .where((e) => !_inFlightCategories.contains(e.key))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final e in evictable.take(_categoryFutures.length - _maxCachedCategories + 1)) {
        _categoryFutures.remove(e.key);
        _categoryFetchTimestamps.remove(e.key);
      }
    }

    _inFlightCategories.add(category);
    _categoryFetchTimestamps[category] = _monotonicClock.elapsedMilliseconds;

    late final Future<List<YtmTrack>> future;
    future = () async {
      try {
        if (!await ConnectivityGuard.hasConnection()) {
          ErrorLogger.log('Skipping category $category fetch: no network connectivity',
              category: 'HomeCubit');
          return <YtmTrack>[];
        }
        if (category == 'Recommended For You') {
          if (_account.isLoggedIn) {
            try {
              final recs =
                  await _account.fetchHomeRecommendations(maxTracks: 50);
              if (recs.isNotEmpty) return recs;
            } catch (_) {}
          }
          try {
            final trending = await _ytm.trending(limit: 25);
            if (trending.isNotEmpty) return trending;
          } catch (_) {}
          return await _ytm.searchWithFallback(
              categoryQueries['Recommended For You'] ?? 'top hits music',
              limit: 25);
        }
        if (category == 'Trending Egypt') {
          try {
            final trending = await _ytm.trending(limit: 25);
            if (trending.isNotEmpty) return trending;
          } catch (_) {}
          return await _ytm.searchWithFallback(
              categoryQueries['Trending Egypt'] ?? 'أغاني مصرية جديدة تريند',
              limit: 25);
        }
        final query = categoryQueries[category] ?? '$category songs';
        return await _ytm.searchWithFallback(query, limit: 25);
      } catch (e, st) {
        // C-05: Only remove if the cached future is still this in-flight instance
        if (identical(_categoryFutures[category], future)) {
          _categoryFutures.remove(category);
          _categoryFetchTimestamps.remove(category);
        }
        // FIX-H05: Return empty list and log error instead of unhandled rethrow in widget FutureBuilder
        ErrorLogger.log('Failed to fetch home category $category',
            error: e, stackTrace: st, category: 'HomeCubit');
        return <YtmTrack>[];
      } finally {
        _inFlightCategories.remove(category);
      }
    }();

    _categoryFutures[category] = future;
    return future;
  }

  void retryCategory(String category) {
    _inFlightCategories.remove(category);
    _categoryFutures.remove(category);
    _categoryFetchTimestamps.remove(category);
  }

  void clearCache() {
    _inFlightCategories.clear();
    _categoryFutures.clear();
    _categoryFetchTimestamps.clear();
  }

  @override
  Future<void> close() {
    _account.loginState.removeListener(_onLoginChanged);
    clearCache();
    return super.close();
  }
}
