// Downloads screen: visibility-scoped selection pruning (selection cannot
// survive a filter change onto hidden tasks) and the paced bulk-retry wiring
// with its "N re-queued" feedback.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';
import 'package:pulsr/features/downloads/presentation/downloads_screen.dart';
import 'package:pulsr/features/downloads/presentation/widgets/download_tile.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockDownloadsCubit extends Mock implements DownloadsCubit {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

DownloadTask _task(
  String id,
  DownloadStatus status, {
  int minute = 0,
}) =>
    DownloadTask(
      id: id,
      videoId: id,
      title: 'Song $id',
      artist: 'Artist',
      status: status,
      error: status == DownloadStatus.failed ? 'nope' : null,
      createdAt: DateTime(2024, 1, 1, 0, minute),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  group('filterDownloadTasks', () {
    final tasks = [
      _task('a', DownloadStatus.downloading, minute: 4),
      _task('b', DownloadStatus.complete, minute: 3),
      _task('c', DownloadStatus.failed, minute: 2),
      _task('d', DownloadStatus.paused, minute: 1),
    ];

    test('all returns everything, statuses filter to their own list', () {
      expect(filterDownloadTasks(tasks, DownloadFilter.all), tasks);
      expect(
        filterDownloadTasks(tasks, DownloadFilter.downloading)
            .map((t) => t.videoId),
        ['a'],
      );
      expect(
        filterDownloadTasks(tasks, DownloadFilter.completed)
            .map((t) => t.videoId),
        ['b'],
      );
      expect(
        filterDownloadTasks(tasks, DownloadFilter.failed).map((t) => t.videoId),
        ['c'],
      );
    });
  });

  group('sameTaskListShape', () {
    test('ignores progress but catches status, id and length changes', () {
      final a = _task('a', DownloadStatus.downloading);
      final b = _task('b', DownloadStatus.complete);
      final progressed = a.copyWith(progress: 0.9);

      expect(sameTaskListShape([a, b], [progressed, b]), isTrue);
      expect(
          sameTaskListShape(
              [a, b], [a.copyWith(status: DownloadStatus.failed), b]),
          isFalse);
      expect(sameTaskListShape([a, b], [b, a]), isFalse);
      expect(sameTaskListShape([a, b], [a]), isFalse);
    });
  });

  late MockDownloadsCubit cubit;
  late MockPlayerCubit player;
  late StreamController<DownloadsState> controller;

  setUp(() {
    cubit = MockDownloadsCubit();
    player = MockPlayerCubit();
    controller = StreamController<DownloadsState>.broadcast();
    addTearDown(controller.close);

    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => cubit.stream).thenAnswer((_) => controller.stream);
    when(() => cubit.deleteDownload(any())).thenAnswer((_) async {});
    when(() => cubit.retryDownload(any())).thenAnswer((_) async {});
    when(() => cubit.retryAllFailed()).thenAnswer((_) async => 0);
    when(() => cubit.retryDownloads(any())).thenAnswer((_) async => 0);
  });

  Future<void> pumpScreen(WidgetTester tester, DownloadsState state) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    when(() => cubit.state).thenReturn(state);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const DownloadsScreen()),
        GoRoute(
            path: '/browse',
            builder: (_, __) => const Scaffold(body: Text('browse-route'))),
      ],
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<DownloadsCubit>.value(value: cubit),
          BlocProvider<PlayerCubit>.value(value: player),
        ],
        child: MaterialApp.router(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  DownloadsState twoStatuses() => DownloadsState(
        tasks: {
          'b': _task('b', DownloadStatus.complete, minute: 2),
          'c': _task('c', DownloadStatus.failed, minute: 1),
        },
      );

  testWidgets('selection is pruned when the filter hides the selected task',
      (tester) async {
    await pumpScreen(tester, twoStatuses());

    await tester.longPress(find.byType(DownloadTile).first);
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('${l10n.statusFailed} (1)'));
    await tester.pump();

    expect(find.textContaining('selected'), findsNothing);
    expect(find.text(l10n.downloadsTitle), findsOneWidget);
  });

  testWidgets('a progress-only emit still rebuilds the affected tile',
      (tester) async {
    final task = _task('a', DownloadStatus.downloading, minute: 2);
    await pumpScreen(tester, DownloadsState(tasks: {'a': task}));
    expect(find.text('0%'), findsOneWidget);

    controller.add(DownloadsState(tasks: {
      'a': task.copyWith(progress: 0.8),
    }));
    await tester.pump();

    expect(find.text('80%'), findsOneWidget);
  });

  testWidgets('bulk retry goes through the paced cubit path and reports count',
      (tester) async {
    when(() => cubit.retryDownloads(any())).thenAnswer((_) async => 3);
    await pumpScreen(tester, twoStatuses());

    await tester.longPress(find.text('Song c'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, l10n.retry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final captured = verify(() => cubit.retryDownloads(captureAny())).captured;
    expect((captured.single as Iterable<String>).toList(), ['c']);
    expect(find.text('3 re-queued'), findsOneWidget);
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('retry-all is disabled while the batch is running',
      (tester) async {
    final completer = Completer<int>();
    when(() => cubit.retryAllFailed()).thenAnswer((_) => completer.future);
    await pumpScreen(tester, twoStatuses());

    final retryAll = find.widgetWithText(TextButton, '${l10n.retry} (1)');
    expect(tester.widget<TextButton>(retryAll).onPressed, isNotNull);

    await tester.tap(retryAll);
    await tester.pump();
    expect(tester.widget<TextButton>(retryAll).onPressed, isNull);

    completer.complete(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 re-queued'), findsOneWidget);
    expect(tester.widget<TextButton>(retryAll).onPressed, isNotNull);
  });
}
