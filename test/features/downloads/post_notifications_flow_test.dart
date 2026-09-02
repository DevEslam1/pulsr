// test/features/downloads/post_notifications_flow_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/services/notification_permission_service.dart';
import 'package:pulsr/domain/usecases/download_lifecycle_usecases.dart';
import 'package:pulsr/domain/usecases/download_query_usecases.dart';
import 'package:pulsr/domain/usecases/download_queue_usecases.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/downloads/presentation/downloads_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockQueueDownloadUseCase extends Mock implements QueueDownloadUseCase {}
class MockPauseDownloadUseCase extends Mock implements PauseDownloadUseCase {}
class MockResumeDownloadUseCase extends Mock implements ResumeDownloadUseCase {}
class MockRetryDownloadUseCase extends Mock implements RetryDownloadUseCase {}
class MockDeleteDownloadUseCase extends Mock implements DeleteDownloadUseCase {}
class MockObserveDownloadsUseCase extends Mock implements ObserveDownloadsUseCase {}
class MockGetDownloadStorageStatsUseCase extends Mock implements GetDownloadStorageStatsUseCase {}

class MockNotificationPermissionService implements INotificationPermissionService {
  bool granted;
  bool isPreApi33;
  int checkCount = 0;
  int requestCount = 0;

  MockNotificationPermissionService({
    this.granted = false,
    this.isPreApi33 = false,
  });

  @override
  Future<bool> checkPermission() async {
    checkCount++;
    if (isPreApi33) return true;
    return granted;
  }

  @override
  Future<bool> requestPermission() async {
    requestCount++;
    if (isPreApi33) return true;
    return granted;
  }

  @override
  Future<bool> shouldShowRationale() async => false;
}

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

  final testTask = DownloadTask(
    id: 'task_1',
    videoId: 'vid_123',
    title: 'Test Song',
    artist: 'Test Artist',
    status: DownloadStatus.queued,
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    mockQueue = MockQueueDownloadUseCase();
    mockPause = MockPauseDownloadUseCase();
    mockResume = MockResumeDownloadUseCase();
    mockRetry = MockRetryDownloadUseCase();
    mockDelete = MockDeleteDownloadUseCase();
    mockObserve = MockObserveDownloadsUseCase();
    mockStorageStats = MockGetDownloadStorageStatsUseCase();
    downloadStreamController = StreamController<DownloadTask>.broadcast();

    when(() => mockObserve.call()).thenAnswer((_) => downloadStreamController.stream);
    when(() => mockObserve.getAll()).thenAnswer((_) async => []);
    when(() => mockStorageStats.call()).thenAnswer((_) async => const Right(StorageStats()));
    when(() => mockQueue.call(any())).thenAnswer((_) async => const Right('task_1'));
  });
 
  tearDown(() {
    downloadStreamController.close();
  });

  setUpAll(() {
    registerFallbackValue(testTask);
  });

  Widget buildTestApp(DownloadsCubit cubit) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BlocProvider<DownloadsCubit>.value(
        value: cubit,
        child: const DownloadsScreen(),
      ),
    );
  }

  testWidgets('T6 · request -> allow: no banner, download enqueues cleanly', (tester) async {
    final notifService = MockNotificationPermissionService(granted: true);
    final cubit = DownloadsCubit(
      mockQueue,
      mockPause,
      mockResume,
      mockRetry,
      mockDelete,
      mockObserve,
      mockStorageStats,
      null,
      null,
      null,
      notifService,
    );

    await tester.pumpWidget(buildTestApp(cubit));
    await tester.pumpAndSettle();

    // Enqueue download
    await cubit.queueDownload(testTask);
    await tester.pumpAndSettle();

    expect(notifService.checkCount, greaterThanOrEqualTo(1));
    verify(() => mockQueue.call(testTask)).called(1);
    expect(find.byKey(const ValueKey('notification_permission_banner')), findsNothing);
  });

  testWidgets('T6 · request -> deny: banner visible, download runs without crash', (tester) async {
    final notifService = MockNotificationPermissionService(granted: false);
    final cubit = DownloadsCubit(
      mockQueue,
      mockPause,
      mockResume,
      mockRetry,
      mockDelete,
      mockObserve,
      mockStorageStats,
      null,
      null,
      null,
      notifService,
    );

    await tester.pumpWidget(buildTestApp(cubit));
    await tester.pumpAndSettle();

    // Enqueue download
    await cubit.queueDownload(testTask);
    await tester.pumpAndSettle();

    // Banner should be visible explaining notification progress won't show
    expect(find.byKey(const ValueKey('notification_permission_banner')), findsOneWidget);
    // Download proceeded regardless
    verify(() => mockQueue.call(testTask)).called(1);

    // Dismiss banner
    cubit.dismissNotificationBanner();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification_permission_banner')), findsNothing);
  });

  testWidgets('T6 · pre-API 33 no-op: checkPermission is true, no request dialog, no banner', (tester) async {
    final notifService = MockNotificationPermissionService(isPreApi33: true);
    final cubit = DownloadsCubit(
      mockQueue,
      mockPause,
      mockResume,
      mockRetry,
      mockDelete,
      mockObserve,
      mockStorageStats,
      null,
      null,
      null,
      notifService,
    );

    await tester.pumpWidget(buildTestApp(cubit));
    await tester.pumpAndSettle();

    await cubit.queueDownload(testTask);
    await tester.pumpAndSettle();

    expect(notifService.requestCount, equals(0)); // Never requests dialog on pre-API 33
    verify(() => mockQueue.call(testTask)).called(1);
    expect(find.byKey(const ValueKey('notification_permission_banner')), findsNothing);
  });
}
