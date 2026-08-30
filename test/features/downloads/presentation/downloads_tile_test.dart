// test/features/downloads/presentation/downloads_tile_test.dart
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
import 'package:pulsr/domain/usecases/queue_download.dart';
import 'package:pulsr/domain/usecases/resume_download.dart';
import 'package:pulsr/domain/usecases/retry_download.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/downloads/presentation/downloads_screen.dart';
import 'package:pulsr/features/downloads/presentation/widgets/download_tile.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockQueueDownloadUseCase mockQueue;
  late MockPauseDownloadUseCase mockPause;
  late MockResumeDownloadUseCase mockResume;
  late MockRetryDownloadUseCase mockRetry;
  late MockDeleteDownloadUseCase mockDelete;
  late MockObserveDownloadsUseCase mockObserve;
  late MockGetDownloadStorageStatsUseCase mockStorageStats;
  late StreamController<DownloadTask> downloadStreamController;

  setUp(() {
    mockQueue = MockQueueDownloadUseCase();
    mockPause = MockPauseDownloadUseCase();
    mockResume = MockResumeDownloadUseCase();
    mockRetry = MockRetryDownloadUseCase();
    mockDelete = MockDeleteDownloadUseCase();
    mockObserve = MockObserveDownloadsUseCase();
    mockStorageStats = MockGetDownloadStorageStatsUseCase();
    downloadStreamController = StreamController<DownloadTask>.broadcast();

    when(
      () => mockObserve(),
    ).thenAnswer((_) => downloadStreamController.stream);
    when(() => mockObserve.getAll()).thenAnswer((_) async => []);
    when(() => mockStorageStats()).thenAnswer(
      (_) async => const Right(
        StorageStats(
          usedBytes: 104857600,
          freeBytes: 10737418240,
          totalBytes: 21474836480,
          downloadedSongsCount: 2,
        ),
      ),
    );
  });

  tearDown(() {
    downloadStreamController.close();
  });

  group('DownloadTile Unique Keying & Collision Safety Tests', () {
    testWidgets(
      'Renders two distinct tiles for two tasks sharing the same videoId',
      (tester) async {
        final taskHighQuality = DownloadTask(
          id: 'task_high_q_123',
          videoId: 'shared_video_id',
          title: 'Song Title (320kbps)',
          artist: 'Artist Name',
          status: DownloadStatus.complete,
          progress: 1.0,
          createdAt: DateTime(2026, 1, 1, 10, 0),
        );

        final taskLowQuality = DownloadTask(
          id: 'task_low_q_456',
          videoId: 'shared_video_id',
          title: 'Song Title (128kbps)',
          artist: 'Artist Name',
          status: DownloadStatus.queued,
          progress: 0.0,
          createdAt: DateTime(2026, 1, 1, 10, 5),
        );

        when(
          () => mockObserve.getAll(),
        ).thenAnswer((_) async => [taskHighQuality, taskLowQuality]);

        final cubit = DownloadsCubit(
          mockQueue,
          mockPause,
          mockResume,
          mockRetry,
          mockDelete,
          mockObserve,
          mockStorageStats,
        );

        await tester.pumpWidget(
          BlocProvider<DownloadsCubit>.value(
            value: cubit,
            child: MaterialApp(
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
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Song Title (320kbps)'), findsOneWidget);
        expect(find.text('Song Title (128kbps)'), findsOneWidget);
        expect(find.byKey(const ValueKey('task_high_q_123')), findsOneWidget);
        expect(find.byKey(const ValueKey('task_low_q_456')), findsOneWidget);
        expect(find.byType(DownloadTile), findsNWidgets(2));

        await cubit.close();
      },
    );
  });
}
