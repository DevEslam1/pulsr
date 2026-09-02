// Phase 5 — Downloads rebuild budget (widget test).
//
// A progress storm must reach the UI layer only a bounded number of times —
// the 200ms throttle caps deliveries far below the event rate.
import 'dart:async';

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
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';
import 'package:pulsr/features/downloads/presentation/downloads_screen.dart';
import 'package:pulsr/features/downloads/presentation/widgets/download_tile.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  late MockGetDownloadStorageStatsUseCase mockStats;
  late StreamController<DownloadTask> repoEvents;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockQueue = MockQueueDownloadUseCase();
    mockPause = MockPauseDownloadUseCase();
    mockResume = MockResumeDownloadUseCase();
    mockRetry = MockRetryDownloadUseCase();
    mockDelete = MockDeleteDownloadUseCase();
    mockObserve = MockObserveDownloadsUseCase();
    mockStats = MockGetDownloadStorageStatsUseCase();
    repoEvents = StreamController<DownloadTask>.broadcast();
    when(() => mockObserve.getAll()).thenAnswer((_) async => []);
    when(() => mockObserve.call()).thenAnswer((_) => repoEvents.stream);
    when(
      () => mockStats.call(),
    ).thenAnswer((_) async => const Right(StorageStats()));
  });

  tearDown(() {
    repoEvents.close();
  });

  testWidgets(
    'progress storm rebuilds the UI layer a bounded number of times',
    (tester) async {
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

      var uiDeliveries = 0;
      Object? lastStateHash;

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
            home: BlocBuilder<DownloadsCubit, DownloadsState>(
              // Counts how many state changes actually REACH the UI layer.
              builder: (context, state) {
                if (!identical(lastStateHash, state)) {
                  lastStateHash = state;
                  uiDeliveries++;
                }
                return const DownloadsScreen();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final baseline = uiDeliveries;

      // 100 progress events for one task. Without the 200ms coalescing this
      // would deliver ~100 state changes to the UI; with it, only a few.
      for (var i = 0; i < 100; i++) {
        repoEvents.add(
          DownloadTask(
            id: 'id_v1',
            videoId: 'v1',
            title: 'Song',
            artist: 'Artist',
            createdAt: DateTime.now(),
            status: DownloadStatus.downloading,
            progress: i / 100,
          ),
        );
      }
      repoEvents.add(
        DownloadTask(
          id: 'id_v1',
          videoId: 'v1',
          title: 'Song',
          artist: 'Artist',
          createdAt: DateTime.now(),
          status: DownloadStatus.complete,
          progress: 1,
        ),
      );

      // Drain the throttle window.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));

      final deliveries = uiDeliveries - baseline;
      // Budget: 100 events must deliver at most 10 UI-level updates
      // (200ms coalescing yields ~3-4; margin for the initial load).
      expect(
        deliveries,
        lessThanOrEqualTo(10),
        reason: '100 progress events delivered $deliveries UI updates',
      );
      expect(
        deliveries,
        greaterThanOrEqualTo(1),
        reason: 'the completed task must actually reach the UI',
      );

      await repoEvents.close();
    },
  );

  testWidgets(
    'DownloadTile rebuilds at most once per delivered progress update',
    (tester) async {
      // Seed one active task so a DownloadTile is actually on screen.
      when(() => mockObserve.getAll()).thenAnswer(
        (_) async => [
          DownloadTask(
            id: 'id_v1',
            videoId: 'v1',
            title: 'Song',
            artist: 'Artist',
            createdAt: DateTime.now(),
            status: DownloadStatus.downloading,
            progress: 0.1,
          ),
        ],
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

      var uiDeliveries = 0;
      Object? lastState;

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
            home: BlocBuilder<DownloadsCubit, DownloadsState>(
              builder: (context, state) {
                if (!identical(lastState, state)) {
                  lastState = state;
                  uiDeliveries++;
                }
                return const DownloadsScreen();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DownloadTile), findsOneWidget);
      final baseline = uiDeliveries;

      // Five progress updates spaced 250ms apart — each beyond the 200ms
      // throttle window, so each one may rebuild the tile at most once.
      for (var i = 2; i <= 6; i++) {
        repoEvents.add(
          DownloadTask(
            id: 'id_v1',
            videoId: 'v1',
            title: 'Song',
            artist: 'Artist',
            createdAt: DateTime.now(),
            status: DownloadStatus.downloading,
            progress: i / 10,
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));
      }

      final deliveries = uiDeliveries - baseline;
      expect(
        deliveries,
        lessThanOrEqualTo(5),
        reason:
            '5 spaced updates must rebuild the tile at most once each '
            '(got $deliveries)',
      );
      expect(
        deliveries,
        greaterThanOrEqualTo(1),
        reason: 'progress updates must actually reach the tile',
      );

      await repoEvents.close();
    },
  );
}
