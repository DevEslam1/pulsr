// test/features/downloads/presentation/downloads_screen_widget_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/usecases/delete_download.dart';
import 'package:pulsr/domain/usecases/get_download_storage_stats.dart';
import 'package:pulsr/domain/usecases/observe_downloads.dart';
import 'package:pulsr/domain/usecases/pause_download.dart';
import 'package:pulsr/domain/usecases/prioritize_download.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/domain/usecases/queue_download.dart';
import 'package:pulsr/domain/usecases/reorder_downloads.dart';
import 'package:pulsr/domain/usecases/resume_download.dart';
import 'package:pulsr/domain/usecases/retry_download.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/downloads/presentation/downloads_screen.dart';
import 'package:pulsr/features/downloads/presentation/widgets/download_tile.dart';
import 'package:pulsr/features/downloads/presentation/widgets/storage_stats_header.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockQueueDownloadUseCase extends Mock implements QueueDownloadUseCase {}

class MockPauseDownloadUseCase extends Mock implements PauseDownloadUseCase {}

class MockResumeDownloadUseCase extends Mock implements ResumeDownloadUseCase {}

class MockRetryDownloadUseCase extends Mock implements RetryDownloadUseCase {}

class MockDeleteDownloadUseCase extends Mock implements DeleteDownloadUseCase {}

class MockObserveDownloadsUseCase extends Mock
    implements ObserveDownloadsUseCase {}

class MockGetDownloadStorageStatsUseCase extends Mock
    implements GetDownloadStorageStatsUseCase {}

class MockReorderDownloadsUseCase extends Mock
    implements ReorderDownloadsUseCase {}

class MockPrioritizeDownloadUseCase extends Mock
    implements PrioritizeDownloadUseCase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockQueueDownloadUseCase mockQueue;
  late MockPauseDownloadUseCase mockPause;
  late MockResumeDownloadUseCase mockResume;
  late MockRetryDownloadUseCase mockRetry;
  late MockDeleteDownloadUseCase mockDelete;
  late MockObserveDownloadsUseCase mockObserve;
  late MockGetDownloadStorageStatsUseCase mockStorageStats;
  late MockReorderDownloadsUseCase mockReorder;
  late MockPrioritizeDownloadUseCase mockPrioritize;
  late StreamController<DownloadTask> downloadStreamController;

  setUp(() {
    mockQueue = MockQueueDownloadUseCase();
    mockPause = MockPauseDownloadUseCase();
    mockResume = MockResumeDownloadUseCase();
    mockRetry = MockRetryDownloadUseCase();
    mockDelete = MockDeleteDownloadUseCase();
    mockObserve = MockObserveDownloadsUseCase();
    mockStorageStats = MockGetDownloadStorageStatsUseCase();
    mockReorder = MockReorderDownloadsUseCase();
    mockPrioritize = MockPrioritizeDownloadUseCase();
    downloadStreamController = StreamController<DownloadTask>.broadcast();

    when(
      () => mockObserve(),
    ).thenAnswer((_) => downloadStreamController.stream);
    when(() => mockObserve.getAll()).thenAnswer((_) async => []);
    when(() => mockStorageStats()).thenAnswer(
      (_) async => const Right(
        StorageStats(
          usedBytes: 104857600, // 100 MB
          freeBytes: 10737418240, // 10 GB
          totalBytes: 21474836480, // 20 GB
          downloadedSongsCount: 15,
        ),
      ),
    );
  });

  tearDown(() {
    downloadStreamController.close();
  });

  DownloadsCubit createCubit([List<DownloadTask> initialTasks = const []]) {
    when(() => mockObserve.getAll()).thenAnswer((_) async => initialTasks);
    // _init() calls these too; without stubs mocktail throws mid-init and
    // isLoading stays true forever (spinner -> 10-minute pumpAndSettle
    // timeouts). Stub them so init completes deterministically.
    when(() => mockObserve()).thenAnswer(
        (_) => const Stream<DownloadTask>.empty());
    when(() => mockStorageStats()).thenAnswer((_) async =>
        Either<AppFailure, StorageStats>.right(const StorageStats(
          usedBytes: 100,
          freeBytes: 900,
          totalBytes: 1000,
          downloadedSongsCount: 0,
        )));
    return DownloadsCubit(
      mockQueue,
      mockPause,
      mockResume,
      mockRetry,
      mockDelete,
      mockObserve,
      mockStorageStats,
      mockReorder,
      mockPrioritize,
    );
  }

  Widget createTestWidget(
    DownloadsCubit cubit, {
    Locale locale = const Locale('en'),
  }) {
    return BlocProvider<DownloadsCubit>.value(
      value: cubit,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AuraTheme.customTheme(
          const Color(0xFF00E5FF),
          brightness: Brightness.dark,
        ),
        home: const DownloadsScreen(),
      ),
    );
  }

  group('DownloadsScreen Widget Tests', () {
    testWidgets('Renders empty state when no tasks exist', (tester) async {
      final cubit = createCubit();

      await tester.pumpWidget(createTestWidget(cubit));

      await tester.pump();

      await tester.pump();

      await tester.pump(const Duration(milliseconds: 400));

      await tester.pump(const Duration(milliseconds: 400));

      await tester.pump();

      // The tile's indeterminate progress bar animates forever: bounded pumps
      // instead of pumpAndSettle, which would wedge for 10 minutes.
      await tester.pump(const Duration(milliseconds: 300));


      expect(find.byType(DownloadsScreen), findsOneWidget);
      expect(find.byType(StorageStatsHeader), findsOneWidget);
      expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
            // Awaiting close() inside the fake-async test zone can deadlock (close
      // races the bloc's pending-emit machinery, and timeout timers never
      // advance without pumps). Fire-and-forget instead: the zone teardown
      // reclaims the bloc with the test.
      unawaited(cubit.close().catchError((_) {}));
    });

    testWidgets('Renders active downloads with progress, speed and ETA', (
      tester,
    ) async {
      final activeTask = DownloadTask(
        id: 'task_1',
        videoId: 'vid_1',
        title: 'Marthnash',
        artist: 'Bahaa Sultan',
        status: DownloadStatus.downloading,
        progress: 0.65,
        speedKbps: 512.0,
        etaSeconds: 12,
        createdAt: DateTime(2026, 1, 1),
      );

      final cubit = createCubit([activeTask]);
      await tester.pumpWidget(createTestWidget(cubit));
      await tester.pump();

      // The tile's indeterminate progress bar animates forever: bounded pumps
      // instead of pumpAndSettle, which would wedge for 10 minutes.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Marthnash'), findsOneWidget);
      expect(find.text('Bahaa Sultan'), findsOneWidget);
      expect(find.byType(DownloadTile), findsOneWidget);
      expect(find.textContaining('65%'), findsOneWidget);
      expect(find.textContaining('512'), findsOneWidget);
            // Awaiting close() inside the fake-async test zone can deadlock (close
      // races the bloc's pending-emit machinery, and timeout timers never
      // advance without pumps). Fire-and-forget instead: the zone teardown
      // reclaims the bloc with the test.
      unawaited(cubit.close().catchError((_) {}));
    });

    testWidgets('Renders Arabic script and RTL without flex overflow', (
      tester,
    ) async {
      final arabicTask = DownloadTask(
        id: 'task_ar',
        videoId: 'vid_ar',
        title: 'مخاصمني ومش بيكلمني حبيبي يا ناس',
        artist: 'نوال الزغبي - نغمات الشرق العربي',
        status: DownloadStatus.complete,
        progress: 1.0,
        createdAt: DateTime(2026, 1, 1),
      );

      final cubit = createCubit([arabicTask]);
      await tester.pumpWidget(
        createTestWidget(cubit, locale: const Locale('ar')),
      );
      await tester.pump();

      // The tile's indeterminate progress bar animates forever: bounded pumps
      // instead of pumpAndSettle, which would wedge for 10 minutes.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('مخاصمني ومش بيكلمني حبيبي يا ناس'), findsOneWidget);
      expect(find.byType(DownloadTile), findsOneWidget);
      expect(tester.takeException(), isNull); // Zero layout overflows
            // Awaiting close() inside the fake-async test zone can deadlock (close
      // races the bloc's pending-emit machinery, and timeout timers never
      // advance without pumps). Fire-and-forget instead: the zone teardown
      // reclaims the bloc with the test.
      unawaited(cubit.close().catchError((_) {}));
    });

    testWidgets(
      'Swipe to delete triggers deleteDownload and shows undo snackbar',
      (tester) async {
        final task = DownloadTask(
          id: 'task_del',
          videoId: 'vid_del',
          title: 'Track To Delete',
          artist: 'Artist',
          status: DownloadStatus.complete,
          progress: 1.0,
          createdAt: DateTime(2026, 1, 1),
        );

        when(
          () => mockDelete('vid_del'),
        ).thenAnswer((_) async => const Right(unit));

        final cubit = createCubit([task]);
        await tester.pumpWidget(createTestWidget(cubit));
        await tester.pump();

      // The tile's indeterminate progress bar animates forever: bounded pumps
      // instead of pumpAndSettle, which would wedge for 10 minutes.
      await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Track To Delete'), findsOneWidget);

        // Swipe dismissible: pump through the dismiss + resize animation so
        // onDismissed fires, then the snackbar entrance frame.
        await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 350));

      // The tile's indeterminate progress bar animates forever: bounded pumps
      // instead of pumpAndSettle, which would wedge for 10 minutes.
      await tester.pump(const Duration(milliseconds: 300));

        verify(() => mockDelete('vid_del')).called(1);
        expect(find.text('Deleted "Track To Delete"'), findsOneWidget);
        expect(find.text('Undo'), findsOneWidget);
              // Awaiting close() inside the fake-async test zone can deadlock (close
      // races the bloc's pending-emit machinery, and timeout timers never
      // advance without pumps). Fire-and-forget instead: the zone teardown
      // reclaims the bloc with the test.
      unawaited(cubit.close().catchError((_) {}));
      },
    );

    testWidgets(
      '[B6] Two tasks sharing videoId at different qualities render simultaneously without key collision',
      (tester) async {
        final flacTask = DownloadTask(
          id: 'task_vid_123_flac',
          videoId: 'vid_123',
          title: 'Song (FLAC)',
          artist: 'Artist',
          status: DownloadStatus.complete,
          progress: 1.0,
          createdAt: DateTime(2026, 1, 1),
        );

        final opusTask = DownloadTask(
          id: 'task_vid_123_opus',
          videoId: 'vid_123',
          title: 'Song (Opus)',
          artist: 'Artist',
          status: DownloadStatus.downloading,
          progress: 0.5,
          createdAt: DateTime(2026, 1, 2),
        );

        final cubit = createCubit([flacTask, opusTask]);
        await tester.pumpWidget(createTestWidget(cubit));
        await tester.pump();

      // The tile's indeterminate progress bar animates forever: bounded pumps
      // instead of pumpAndSettle, which would wedge for 10 minutes.
      await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(DownloadTile), findsNWidgets(2));
        expect(find.text('Song (FLAC)'), findsOneWidget);
        expect(find.text('Song (Opus)'), findsOneWidget);
        expect(tester.takeException(), isNull);
              // Awaiting close() inside the fake-async test zone can deadlock (close
      // races the bloc's pending-emit machinery, and timeout timers never
      // advance without pumps). Fire-and-forget instead: the zone teardown
      // reclaims the bloc with the test.
      unawaited(cubit.close().catchError((_) {}));
      },
    );
  });
}
