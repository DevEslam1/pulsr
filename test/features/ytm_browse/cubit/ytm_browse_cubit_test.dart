// test/features/ytm_browse/cubit/ytm_browse_cubit_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/core/services/ytm_browse_service.dart';
import 'package:pulsr/features/ytm_browse/cubit/ytm_browse_cubit.dart';
import 'package:pulsr/features/ytm_browse/cubit/ytm_browse_state.dart';

class _MockYtmBrowseService extends Mock implements YtmBrowseService {}

YtmBrowseSection _section(String title, {int count = 1, String id = ''}) {
  return YtmBrowseSection(
    id: id,
    title: title,
    subtitle: '$title subtitle',
    items: List<YtmBrowseItem>.generate(
      count,
      (i) => YtmBrowseItem(
        id: '$title-$i',
        title: '$title track $i',
        subtitle: 'Artist $i',
        type: 'song',
      ),
    ),
  );
}

void main() {
  late _MockYtmBrowseService service;

  setUpAll(() {
    registerFallbackValue(false);
    registerFallbackValue(_section('fallback'));
  });

  setUp(() {
    service = _MockYtmBrowseService();
  });

  YtmBrowseCubit buildCubit() {
    final cubit = YtmBrowseCubit(service);
    addTearDown(cubit.close);
    return cubit;
  }

  test('load emits a loading state and then the populated feed', () async {
    when(() => service.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async => [_section('Charts', count: 2)]);

    final cubit = buildCubit();
    final states = <YtmBrowseState>[];
    final sub = cubit.stream.listen(states.add);
    addTearDown(sub.cancel);

    await cubit.load();

    expect(states.first.isLoading, isTrue);
    expect(states.first.sections, isEmpty);
    expect(cubit.state.sections, hasLength(1));
    expect(cubit.state.sections.single.title, 'Charts');
    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.isRefreshing, isFalse);
    expect(cubit.state.hasLoaded, isTrue);
    expect(cubit.state.failure, isNull);
  });

  test('empty upstream sections never reach the UI', () async {
    when(() => service.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async => [
              _section('Empty', count: 0),
              _section('Top Charts', count: 3),
            ]);

    final cubit = buildCubit();
    await cubit.load();

    expect(cubit.state.sections, hasLength(1));
    expect(cubit.state.sections.single.title, 'Top Charts');
    expect(cubit.state.isEmpty, isFalse);
  });

  test('a first-load failure sets a typed failure and marks the load done',
      () async {
    when(() => service.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async => throw Exception('offline'));

    final cubit = buildCubit();
    await cubit.load();

    expect(cubit.state.failure, YtmBrowseFailure.loadFailed);
    expect(cubit.state.hasLoaded, isTrue);
    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.sections, isEmpty);
  });

  test('a network failure is reported as offline, not a generic error',
      () async {
    when(() => service.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async => throw const YtmException('YTM_NETWORK'));

    final cubit = buildCubit();
    await cubit.load();

    expect(cubit.state.failureReason, YtmBrowseFailureReason.offline);
  });

  test('bot and geo signals map to their own copy buckets', () {
    expect(
      YtmBrowseCubit.classifyBrowseFailure(const YtmException('BOT_CHALLENGE')),
      YtmBrowseFailureReason.botBlocked,
    );
    expect(
      YtmBrowseCubit.classifyBrowseFailure(const YtmException('GEO_BLOCKED')),
      YtmBrowseFailureReason.geoBlocked,
    );
    expect(
      YtmBrowseCubit.classifyBrowseFailure(const YtmException('VIDEO_GONE')),
      YtmBrowseFailureReason.unavailable,
    );
  });

  test('a successful load records the service fetch time', () async {
    final fetchedAt = DateTime(2026, 10, 27, 14, 32);
    when(() => service.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async => [_section('Charts', id: 'charts')]);
    when(() => service.lastFetchTime).thenReturn(fetchedAt);

    final cubit = buildCubit();
    await cubit.load();

    expect(cubit.state.lastUpdatedAt, fetchedAt);
  });

  test('refreshing one section replaces only that section', () async {
    when(() => service.getHomeFeed(force: any(named: 'force'))).thenAnswer(
      (_) async => [
        _section('Charts', id: 'charts'),
        _section('New Releases', id: 'newReleases'),
      ],
    );
    when(() => service.refreshSection(any())).thenAnswer(
      (_) async => _section('Charts Refreshed', id: 'charts', count: 3),
    );

    final cubit = buildCubit();
    await cubit.load();
    final target = cubit.state.sections.first;
    await cubit.refreshSection(target);

    expect(cubit.state.sections, hasLength(2));
    expect(cubit.state.sections.first.title, 'Charts Refreshed');
    expect(cubit.state.sections.last.title, 'New Releases');
    expect(cubit.state.isSectionRefreshing('charts'), isFalse);
    expect(cubit.state.sectionFailure('charts'), isNull);
  });

  test('a failed section refresh keeps the old cards and exposes the reason',
      () async {
    when(() => service.getHomeFeed(force: any(named: 'force'))).thenAnswer(
      (_) async => [_section('Charts', id: 'charts', count: 2)],
    );
    when(() => service.refreshSection(any()))
        .thenAnswer((_) async => throw const YtmException('YTM_NETWORK'));

    final cubit = buildCubit();
    await cubit.load();
    await cubit.refreshSection(cubit.state.sections.first);

    expect(cubit.state.sections.single.title, 'Charts');
    expect(cubit.state.sections.single.items, hasLength(2));
    expect(
      cubit.state.sectionFailure('charts'),
      YtmBrowseFailureReason.offline,
    );
    expect(cubit.state.isSectionRefreshing('charts'), isFalse);
  });

  test('an empty section refresh is treated as a failure', () async {
    when(() => service.getHomeFeed(force: any(named: 'force'))).thenAnswer(
      (_) async => [_section('Charts', id: 'charts', count: 2)],
    );
    when(() => service.refreshSection(any()))
        .thenAnswer((_) async => _section('Charts', id: 'charts', count: 0));

    final cubit = buildCubit();
    await cubit.load();
    await cubit.refreshSection(cubit.state.sections.first);

    expect(cubit.state.sections.single.items, hasLength(2));
    expect(
      cubit.state.sectionFailure('charts'),
      YtmBrowseFailureReason.unknown,
    );
  });

  test('a refresh failure keeps the previous feed and exposes stale failure',
      () async {
    var call = 0;
    when(() => service.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) async {
      call++;
      if (call == 1) return [_section('Cached', count: 2)];
      throw Exception('offline');
    });

    final cubit = buildCubit();
    await cubit.load();
    await cubit.load(force: true);

    expect(cubit.state.sections.single.title, 'Cached');
    expect(cubit.state.failure, YtmBrowseFailure.loadFailed);
    expect(cubit.state.hasStaleFailure, isTrue);
    expect(cubit.state.isRefreshing, isFalse);
  });

  test('a stale in-flight response cannot overwrite a newer one', () async {
    final first = Completer<List<YtmBrowseSection>>();
    final second = Completer<List<YtmBrowseSection>>();
    when(() => service.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) => first.future);
    when(() => service.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) => second.future);

    final cubit = buildCubit();
    final firstLoad = cubit.load();
    final secondLoad = cubit.load(force: true);

    second.complete([_section('Newest', count: 1)]);
    await secondLoad;
    expect(cubit.state.sections.single.title, 'Newest');

    first.complete([_section('Stale', count: 1)]);
    await firstLoad;
    expect(cubit.state.sections.single.title, 'Newest');
  });

  test('force is forwarded to the service', () async {
    when(() => service.getHomeFeed(force: true))
        .thenAnswer((_) async => [_section('Forced')]);

    final cubit = buildCubit();
    await cubit.load(force: true);

    verify(() => service.getHomeFeed(force: true)).called(1);
  });

  test('closing while a load is in flight never emits after close', () async {
    final pending = Completer<List<YtmBrowseSection>>();
    when(() => service.getHomeFeed(force: any(named: 'force')))
        .thenAnswer((_) => pending.future);

    final cubit = YtmBrowseCubit(service);
    final load = cubit.load();
    await cubit.close();
    pending.complete([_section('Late', count: 1)]);

    await expectLater(load, completes);
    expect(cubit.isClosed, isTrue);
    expect(cubit.state.sections, isEmpty);
  });
}
