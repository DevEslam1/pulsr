// test/features/downloads/presentation/storage_stats_header_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/usecases/download_lifecycle_usecases.dart';
import 'package:pulsr/domain/usecases/download_query_usecases.dart';
import 'package:pulsr/domain/usecases/download_queue_usecases.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
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

Widget buildTestableWidget({required Widget child, DownloadsCubit? cubit}) {
  return MaterialApp(
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
    home: Scaffold(
      body:
          cubit != null
              ? BlocProvider<DownloadsCubit>.value(value: cubit, child: child)
              : child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageStatsHeader Widget Tests (H-14)', () {
    testWidgets('renders zero bytes and empty progress correctly', (
      tester,
    ) async {
      const stats = StorageStats(
        usedBytes: 0,
        freeBytes: 0,
        totalBytes: 0,
        downloadedSongsCount: 0,
      );

      await tester.pumpWidget(
        buildTestableWidget(child: const StorageStatsHeader(stats: stats)),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 B / Free Space: 0 B'), findsOneWidget);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, equals(0.0));
    });

    testWidgets(
      'formats MB and GB correctly with accurate progress bar percentage',
      (tester) async {
        const used = 500 * 1024 * 1024; // 500 MB
        const free = 1500 * 1024 * 1024; // 1.5 GB
        const total = used + free; // 2 GB

        const stats = StorageStats(
          usedBytes: used,
          freeBytes: free,
          totalBytes: total,
          downloadedSongsCount: 42,
        );

        await tester.pumpWidget(
          buildTestableWidget(child: const StorageStatsHeader(stats: stats)),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('500.0 MB'), findsOneWidget);
        expect(find.textContaining('1.5 GB'), findsOneWidget);

        final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(progress.value, closeTo(0.25, 0.01));
      },
    );

    testWidgets(
      'subscribes to DownloadsCubit state and updates on state emission',
      (tester) async {
        final mockQueue = MockQueueDownloadUseCase();
        final mockPause = MockPauseDownloadUseCase();
        final mockResume = MockResumeDownloadUseCase();
        final mockRetry = MockRetryDownloadUseCase();
        final mockDelete = MockDeleteDownloadUseCase();
        final mockObserve = MockObserveDownloadsUseCase();
        final mockStats = MockGetDownloadStorageStatsUseCase();

        when(() => mockObserve.getAll()).thenAnswer((_) async => []);
        when(() => mockObserve.call()).thenAnswer((_) => const Stream.empty());
        when(() => mockStats.call()).thenAnswer(
          (_) async => const Right(
            StorageStats(
              usedBytes: 100 * 1024 * 1024,
              freeBytes: 900 * 1024 * 1024,
              totalBytes: 1000 * 1024 * 1024,
              downloadedSongsCount: 10,
            ),
          ),
        );

        final cubit = DownloadsCubit(
          mockQueue,
          mockPause,
          mockResume,
          mockRetry,
          mockDelete,
          mockObserve,
          mockStats,
        );
        addTearDown(cubit.close);

        await tester.pumpWidget(
          buildTestableWidget(cubit: cubit, child: const StorageStatsHeader()),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('100.0 MB'), findsOneWidget);
        expect(find.textContaining('900.0 MB'), findsOneWidget);
      },
    );
  });
}
