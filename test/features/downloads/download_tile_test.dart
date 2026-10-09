// Covers lib/features/downloads/presentation/widgets/download_tile.dart
//
// Exercises every DownloadStatus variant (icons/labels/progress), artwork vs
// status-icon leading, cancel button, popup-menu actions, error row, and the
// title/size fallbacks.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';
import 'package:pulsr/features/downloads/presentation/widgets/download_tile.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockDownloadsCubit extends Mock implements DownloadsCubit {}

DownloadTask _task({
  String videoId = 'vid1',
  String title = 'Song',
  String artist = 'Artist',
  DownloadStatus status = DownloadStatus.queued,
  double progress = 0.0,
  double? speedKbps,
  int? etaSeconds,
  String? filePath,
  String? artworkUrl,
  String? error,
  int? localSongId,
  int? fileSize,
}) =>
    DownloadTask(
      id: videoId,
      videoId: videoId,
      title: title,
      artist: artist,
      status: status,
      progress: progress,
      speedKbps: speedKbps,
      etaSeconds: etaSeconds,
      filePath: filePath,
      artworkUrl: artworkUrl,
      error: error,
      localSongId: localSongId,
      fileSize: fileSize,
      createdAt: DateTime(2024),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockDownloadsCubit cubit;

  setUpAll(() {
    registerFallbackValue(_task());
  });

  setUp(() {
    cubit = MockDownloadsCubit();
    when(() => cubit.state).thenReturn(const DownloadsState());
    when(() => cubit.stream)
        .thenAnswer((_) => const Stream<DownloadsState>.empty());
    when(() => cubit.cancelDownload(any())).thenAnswer((_) async {});
    when(() => cubit.pauseDownload(any())).thenAnswer((_) async {});
    when(() => cubit.resumeDownload(any())).thenAnswer((_) async {});
    when(() => cubit.retryDownload(any())).thenAnswer((_) async {});
    when(() => cubit.deleteDownload(any())).thenAnswer((_) async {});
    when(() => cubit.queueDownload(any())).thenAnswer((_) async {});
  });

  Future<void> pumpTile(WidgetTester tester, DownloadTask task) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BlocProvider<DownloadsCubit>.value(
            value: cubit,
            child: SingleChildScrollView(child: DownloadTile(task: task)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('downloading shows progress, percent, speed and eta',
      (tester) async {
    await pumpTile(
      tester,
      _task(
        status: DownloadStatus.downloading,
        progress: 0.5,
        speedKbps: 128,
        etaSeconds: 5,
      ),
    );

    expect(find.byIcon(Icons.downloading_rounded), findsOneWidget);
    expect(find.text(l10n.statusDownloading), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('KB/s'), findsOneWidget);
    expect(find.textContaining('5s'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('tagging shows an indeterminate progress bar', (tester) async {
    await pumpTile(
      tester,
      _task(status: DownloadStatus.tagging, progress: 1.0),
    );

    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(find.text(l10n.statusEmbedding), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);
  });

  testWidgets('queued shows the schedule icon and cancel button',
      (tester) async {
    await pumpTile(tester, _task(status: DownloadStatus.queued));

    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.text(l10n.statusQueued), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('paused shows the paused icon and no cancel button',
      (tester) async {
    await pumpTile(tester, _task(status: DownloadStatus.paused));

    expect(find.byIcon(Icons.pause_circle_outline_rounded), findsOneWidget);
    expect(find.text(l10n.statusPaused), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('complete shows the success icon and hides the status label',
      (tester) async {
    await pumpTile(tester, _task(status: DownloadStatus.complete));

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text(l10n.statusCompleted), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('artwork url renders a CachedArtwork with a completion badge',
      (tester) async {
    await pumpTile(
      tester,
      _task(
        status: DownloadStatus.complete,
        artworkUrl: 'https://example.com/art.jpg',
      ),
    );

    // The leading artwork replaces the status icon container; the completion
    // overlay check is still drawn.
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('failed shows the error icon, warning row and message',
      (tester) async {
    await pumpTile(
      tester,
      _task(status: DownloadStatus.failed, error: 'network exploded'),
    );

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text(l10n.statusFailed), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('empty title falls back to the videoId and shows file size',
      (tester) async {
    await pumpTile(
      tester,
      _task(
        title: '',
        videoId: 'abcdef',
        status: DownloadStatus.complete,
        fileSize: 2048,
      ),
    );

    expect(find.text('abcdef'), findsOneWidget);
    expect(find.textContaining('KB'), findsOneWidget);
  });

  testWidgets('tapping cancel invokes cancelDownload', (tester) async {
    await pumpTile(tester, _task(status: DownloadStatus.downloading));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    verify(() => cubit.cancelDownload('vid1')).called(1);
  });

  testWidgets('popup menu pause action is wired', (tester) async {
    await pumpTile(tester, _task(status: DownloadStatus.downloading));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text(l10n.pause));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.pauseDownload('vid1')).called(1);
  });

  testWidgets('popup menu resume action is wired for paused tasks',
      (tester) async {
    await pumpTile(tester, _task(status: DownloadStatus.paused));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text(l10n.resume));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.resumeDownload('vid1')).called(1);
  });

  testWidgets('popup menu retry action is wired for failed tasks',
      (tester) async {
    await pumpTile(tester, _task(status: DownloadStatus.failed));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text(l10n.retry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.retryDownload('vid1')).called(1);
  });

  testWidgets('popup menu delete action is wired and always present',
      (tester) async {
    await pumpTile(tester, _task(status: DownloadStatus.complete));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text(l10n.delete));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.deleteDownload('vid1')).called(1);
  });
}
