// lib/features/home/cubit/home_cubit.dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/services/ytm_account_service.dart';
import '../../../core/services/ytm_service.dart';
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
class HomeCubit extends Cubit<HomeState> {
  HomeCubit({
    required YtmService ytmService,
    required YtmAccountService accountService,
  })  : _ytm = ytmService,
        _account = accountService,
        super(HomeState(isLoggedIn: accountService.isLoggedIn)) {
    _account.loginState.addListener(_onLoginChanged);
  }

  final YtmService _ytm;
  final YtmAccountService _account;

  /// Resolved once and reused across rebuilds with a 10-minute TTL.
  static const Duration categoryTtl = Duration(minutes: 10);

  static const Map<String, String> categoryQueries = {
    'Recommended For You': 'recommended music',
    'Trending Egypt': 'أغاني مصرية جديدة تريند',
    'Mahraganat': 'مهرجانات مصرية جديدة',
    'Arabic Pop': 'أغاني عربي عمرو دياب تامر حسني حماقي',
    'Global Top Hits': 'global top hits songs',
    'New Releases': 'new music releases',
    'Chill & Lo-Fi': 'chill lofi beats',
    'Pop Mix': 'pop hits playlist',
    'Hip-Hop': 'arabic hip hop rap ويجز',
    'Workout Energy': 'workout gym motivation music',
    'Rock & Metal': 'rock metal playlist',
    'Acoustic': 'acoustic guitar relax',
  };

  static const List<String> _loggedInCategories = [
    'Recommended For You',
    'Trending Egypt',
    'Mahraganat',
    'Arabic Pop',
    'Global Top Hits',
    'New Releases',
    'Chill & Lo-Fi',
    'Pop Mix',
    'Hip-Hop',
    'Workout Energy',
    'Rock & Metal',
    'Acoustic',
  ];

  static const List<String> _anonymousCategories = [
    'Trending Egypt',
    'Mahraganat',
    'Arabic Pop',
    'Global Top Hits',
    'New Releases',
    'Chill & Lo-Fi',
    'Pop Mix',
    'Hip-Hop',
    'Workout Energy',
    'Rock & Metal',
    'Acoustic',
  ];

  final Map<String, Future<List<YtmTrack>>> _categoryFutures = {};
  final Map<String, DateTime> _categoryFetchTimestamps = {};

  bool get isLoggedIn => _account.isLoggedIn;

  List<String> get onlineCategories =>
      isLoggedIn ? _loggedInCategories : _anonymousCategories;

  void _onLoginChanged() {
    clearCache();
    if (isClosed) return;
    emit(state.copyWith(
      loginEpoch: state.loginEpoch + 1,
      isLoggedIn: isLoggedIn,
    ));
  }

  /// Returns the cached future for [category], refetching once its TTL lapses.
  Future<List<YtmTrack>> categoryFuture(String category) {
    final now = DateTime.now();
    final lastFetch = _categoryFetchTimestamps[category];
    if (lastFetch != null && now.difference(lastFetch) > categoryTtl) {
      _categoryFutures.remove(category);
      _categoryFetchTimestamps.remove(category);
    }

    return _categoryFutures.putIfAbsent(
      category,
      () async {
        _categoryFetchTimestamps[category] = DateTime.now();
        try {
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
        } catch (e) {
          _categoryFutures.remove(category);
          _categoryFetchTimestamps.remove(category);
          rethrow;
        }
      },
    );
  }

  void retryCategory(String category) {
    _categoryFutures.remove(category);
    _categoryFetchTimestamps.remove(category);
  }

  void clearCache() {
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
