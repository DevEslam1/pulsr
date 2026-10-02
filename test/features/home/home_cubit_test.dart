// test/features/home/home_cubit_test.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/network/connectivity_guard.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/home/cubit/home_cubit.dart';

class _MockYtmService extends Mock implements YtmService {}

class _MockYtmAccountService extends Mock implements YtmAccountService {}

class _MockConnectivity extends Mock implements Connectivity {}

/// Deterministic [Stopwatch] so TTL lapses can be exercised without waiting.
class _FakeStopwatch extends Stopwatch {
  int _elapsedMs = 0;

  void advance(int ms) => _elapsedMs += ms;

  @override
  int get elapsedMilliseconds => _elapsedMs;

  @override
  void start() {}
}

void main() {
  late _MockYtmService mockYtm;
  late _MockYtmAccountService mockAccount;
  late _MockConnectivity mockConnectivity;
  late _FakeStopwatch clock;
  late ValueNotifier<bool> loginState;

  setUp(() {
    mockYtm = _MockYtmService();
    mockAccount = _MockYtmAccountService();
    mockConnectivity = _MockConnectivity();
    clock = _FakeStopwatch();
    loginState = ValueNotifier<bool>(false);

    when(() => mockAccount.loginState).thenReturn(loginState);
    when(() => mockAccount.isLoggedIn).thenReturn(false);
    when(() => mockConnectivity.checkConnectivity())
        .thenAnswer((_) async => [ConnectivityResult.wifi]);
    ConnectivityGuard.setMockConnectivity(mockConnectivity);
  });

  tearDown(() {
    loginState.dispose();
  });

  HomeCubit createCubit() => HomeCubit(
        ytmService: mockYtm,
        accountService: mockAccount,
        clock: clock,
      );

  group('HomeState', () {
    test('is value-equal and has a matching hashCode', () {
      const a = HomeState();
      const b = HomeState();
      const loggedIn = HomeState(isLoggedIn: true);
      const bumped = HomeState(loginEpoch: 1);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(loggedIn)));
      expect(a, isNot(equals(bumped)));
      expect(a.copyWith(), equals(a));
    });
  });

  group('HomeCubit category cache', () {
    test('reuses the cached future within TTL and refetches after expiry',
        () async {
      var calls = 0;
      when(() => mockYtm.searchWithFallback(any(), limit: any(named: 'limit')))
          .thenAnswer((_) async {
        calls++;
        return const <YtmTrack>[];
      });

      final cubit = createCubit();
      const category = 'Chill & Lo-Fi';

      await cubit.categoryFuture(category);
      expect(calls, 1, reason: 'first call fetches');

      await cubit.categoryFuture(category);
      expect(calls, 1, reason: 'cached inside the TTL window');

      clock.advance(HomeCubit.categoryTtl.inMilliseconds + 1);
      await cubit.categoryFuture(category);
      expect(calls, 2, reason: 'TTL lapsed so it refetches');

      await cubit.close();
    });

    test('never overshoots the cap and evicts the oldest entry', () async {
      final calls = <String, int>{};
      when(() => mockYtm.searchWithFallback(any(), limit: any(named: 'limit')))
          .thenAnswer((invocation) async {
        final query = invocation.positionalArguments.first as String;
        calls[query] = (calls[query] ?? 0) + 1;
        return const <YtmTrack>[];
      });

      final cubit = createCubit();
      const cap = 20;

      for (var i = 0; i < cap + 3; i++) {
        clock.advance(1);
        await cubit.categoryFuture('cat$i');
      }

      expect(cubit.cachedCategoryCount, lessThanOrEqualTo(cap),
          reason: 'insertion before pruning must keep the cache within cap');

      const oldestQuery = 'cat0 songs';
      expect(calls[oldestQuery], 1);
      await cubit.categoryFuture('cat0');
      expect(calls[oldestQuery], 2,
          reason: 'oldest entry should have been evicted');
      expect(cubit.cachedCategoryCount, lessThanOrEqualTo(cap));

      await cubit.close();
    });
  });
}
