// Additional coverage for lib/features/downloads/presentation/downloads_screen.dart
//
// Complements downloads_selection_pruning_test.dart with the empty/populated
// layouts, storage header, filter chips + per-filter empty states, selection
// bulk actions, clear-completed, retry-all-failed and pull-to-refresh.
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
import 'package:pulsr/features/downloads/presentation/widgets/storage_stats_header.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockDownloadsCubit extends Mock implements DownloadsCubit {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

DownloadTask _task(
  String id,
  DownloadStatus status, {
  int minute = 0,
  int? localSongId,
  String? error,
}) =>
    DownloadTask(
      id: id,
      videoId: id,
      title: 'Song $id',
      artist: 'Artist',
      status: status,
      progress: status == DownloadStatus.downloading ? 0.4 : 0.0,
      localSongId: localSongId,
      error: error,
      createdAt: DateTime(2024, 1, 1, 0, minute),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

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
    when(() => cubit.loadInitialTasks()).thenAnswer((_) async {});
    when(() => cubit.refreshStorageStats()).thenAnswer((_) async {});
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

  DownloadsState populated() => DownloadsState(
        tasks: {
          'a': _task('a', DownloadStatus.downloading, minute: 4),
          'b': _task('b', DownloadStatus.complete, minute: 3, localSongId: 11),
          'c': _task('c', DownloadStatus.failed, minute: 2, error: 'nope'),
          'd': _task('d', DownloadStatus.paused, minute: 1),
        },
        storageStats: const StorageStats(
          usedBytes: 1024,
          freeBytes: 2048,
          totalBytes: 4096,
          downloadedSongsCount: 1,
        ),
      );

  testWidgets('empty state shows storage stats and the browse action',
      (tester) async {
    await pumpScreen(
      tester,
      const DownloadsState(
        storageStats: StorageStats(totalBytes: 100, usedBytes: 10),
      ),
    );

    expect(find.byType(StorageStatsHeader), findsOneWidget);
    expect(find.text(l10n.noDownloadsTitle), findsOneWidget);

    await tester.tap(find.text(l10n.searchOnline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('browse-route'), findsOneWidget);
  });

  testWidgets('empty state hides storage stats when no space is reported',
      (tester) async {
    await pumpScreen(tester, const DownloadsState());

    expect(find.byType(StorageStatsHeader), findsNothing);
    expect(find.text(l10n.noDownloadsTitle), findsOneWidget);
  });

  testWidgets('populated state renders the header, banner, chips and tiles',
      (tester) async {
    await pumpScreen(tester, populated());

    expect(find.byType(StorageStatsHeader), findsOneWidget);
    expect(find.byType(DownloadTile), findsNWidgets(4));
    expect(find.textContaining('Downloading 1'), findsOneWidget);
    expect(find.text('${l10n.all} (4)'), findsOneWidget);
    expect(find.text('${l10n.statusDownloading} (1)'), findsOneWidget);
    expect(find.text('${l10n.statusCompleted} (1)'), findsOneWidget);
    expect(find.text('${l10n.statusFailed} (1)'), findsOneWidget);
    // Clear-completed + retry-all-failed app-bar actions are both present.
    expect(find.byIcon(Icons.delete_sweep_rounded), findsOneWidget);
    expect(find.text('${l10n.retry} (1)'), findsOneWidget);
  });

  testWidgets('filter chips narrow the visible tasks', (tester) async {
    await pumpScreen(tester, populated());

    await tester.tap(find.text('${l10n.statusFailed} (1)'));
    await tester.pump();

    expect(find.byType(DownloadTile), findsOneWidget);
    expect(find.text('Song c'), findsOneWidget);

    await tester.tap(find.text('${l10n.statusCompleted} (1)'));
    await tester.pump();

    expect(find.text('Song b'), findsOneWidget);
    expect(find.text('Song c'), findsNothing);
  });

  testWidgets('an empty filter shows its dedicated empty state and retries',
      (tester) async {
    await pumpScreen(
      tester,
      DownloadsState(
        tasks: {'b': _task('b', DownloadStatus.complete, minute: 1)},
      ),
    );

    await tester.tap(find.text('${l10n.statusFailed} (0)'));
    await tester.pump();

    expect(find.byType(DownloadTile), findsNothing);
    expect(find.textContaining(l10n.noDownloadsTitle), findsWidgets);

    await tester.tap(find.text(l10n.retry).last);
    await tester.pump();

    verify(() => cubit.retryAllFailed()).called(1);
  });

  testWidgets('long-press enters selection and select-all toggles the set',
      (tester) async {
    await pumpScreen(tester, populated());

    await tester.longPress(find.byType(DownloadTile).first);
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pump();
    expect(find.text('4 selected'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.deselect_rounded));
    await tester.pump();
    expect(find.text(l10n.downloadsTitle), findsOneWidget);
  });

  testWidgets('bulk delete confirms then deletes every selected task',
      (tester) async {
    await pumpScreen(tester, populated());

    await tester.longPress(find.byType(DownloadTile).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pump();

    await tester.tap(find.text(l10n.delete));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(FilledButton, l10n.delete));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.deleteDownload(any())).called(4);
    expect(find.text(l10n.downloadsTitle), findsOneWidget);
  });

  testWidgets('clear-completed confirms and deletes the completed task',
      (tester) async {
    await pumpScreen(tester, populated());

    await tester.tap(find.byIcon(Icons.delete_sweep_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.clear), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, l10n.clear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.deleteDownload('b')).called(1);
  });

  testWidgets('retry-all-failed app-bar action retries failed tasks',
      (tester) async {
    await pumpScreen(tester, populated());

    await tester.tap(find.text('${l10n.retry} (1)'));
    await tester.pump();

    verify(() => cubit.retryAllFailed()).called(1);
  });

  testWidgets('pull-to-refresh reloads tasks and storage stats',
      (tester) async {
    await pumpScreen(tester, populated());

    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    await refresh.onRefresh();
    await tester.pump();

    verify(() => cubit.loadInitialTasks()).called(1);
    verify(() => cubit.refreshStorageStats()).called(1);
  });

  testWidgets('tapping a playable task without a database surfaces an error',
      (tester) async {
    await pumpScreen(tester, populated());

    await tester.tap(find.text('Song b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.libraryReadError), findsOneWidget);
  });
}
