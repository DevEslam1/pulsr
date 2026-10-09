// YtmSearchScreen widget coverage. The screen is route-gated behind
// `AppConfig.ytmEnabled`, so its cubits are driven directly here with a real
// YtmSearchCubit over a mock YtmService and a real YtmDownloadCubit over mocks.
// Exercises: the empty/history state, history chips, the loading skeleton, the
// no-results state, the result list + playback, the error/retry state and the
// clear-query affordance.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_search_cubit.dart';
import 'package:pulsr/features/ytm_search/presentation/ytm_search_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class MockYtmService extends Mock implements YtmService {}

class MockYtDownloadService extends Mock implements YtDownloadService {}

class MockDownloadsCubit extends Mock implements DownloadsCubit {}

YtmTrack _track(String id, String title, [String artist = 'Artist']) =>
    YtmTrack(
      videoId: id,
      title: title,
      artist: artist,
      duration: const Duration(minutes: 3),
    );

YtmStream _stream(String id) => YtmStream(
      videoId: id,
      url: 'https://example.com/$id.m4a',
      mimeType: 'audio/mp4',
      container: 'm4a',
      bitrateKbps: 128,
      duration: const Duration(minutes: 3),
      title: id,
      artist: 'Artist',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockYtmService service;
  late YtmSearchCubit searchCubit;
  late YtmDownloadCubit downloadCubit;
  late MockDownloadsCubit downloadsCubit;
  late StreamController<DownloadsState> downloadsController;
  late PlayerCubit player;

  setUpAll(() {
    registerFallbackValue(createTestSong(id: -1));
    registerFallbackValue(<SongsTableData>[]);
    registerFallbackValue(DownloadTask(
      id: 'fallbackVid1',
      videoId: 'fallbackVid1',
      title: 'Fallback',
      artist: 'Fallback',
      createdAt: DateTime(2026, 1, 1),
    ));
  });

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});

    service = MockYtmService();
    when(() => service.invalidatePoToken()).thenAnswer((_) async {});
    when(() => service.ensurePoTokenReady()).thenAnswer((_) async => true);
    when(() => service.isBotCoolingDown).thenReturn(false);
    when(() => service.botCooldownNotifier)
        .thenReturn(ValueNotifier<bool>(false));
    when(() => service.resolveStream(any()))
        .thenAnswer((inv) async => _stream(inv.positionalArguments.first as String));

    downloadsCubit = MockDownloadsCubit();
    downloadsController = StreamController<DownloadsState>.broadcast();
    when(() => downloadsCubit.stream)
        .thenAnswer((_) => downloadsController.stream);
    when(() => downloadsCubit.queueDownload(any())).thenAnswer((_) async {});
    when(() => downloadsCubit.cancelDownload(any())).thenAnswer((_) async {});

    downloadCubit = YtmDownloadCubit(
      MockYtDownloadService(),
      stubPlayerCubit(),
      downloadsCubit: downloadsCubit,
    );

    getIt.registerSingleton<YtmDownloadCubit>(downloadCubit);

    player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    // The screen's BlocProvider owns (and disposes) the YtmSearchCubit, so it
    // is deliberately not closed here. YtmDownloadCubit is provided by value
    // and therefore never disposed by the tree.
    await downloadsController.close();
    await downloadCubit.close();
    await getIt.reset();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // The cubit is constructed immediately before pumping so it reads the
    // SharedPreferences seeded by the test body.
    searchCubit = YtmSearchCubit(service: service);
    if (getIt.isRegistered<YtmSearchCubit>()) {
      getIt.unregister<YtmSearchCubit>();
    }
    getIt.registerSingleton<YtmSearchCubit>(searchCubit);

    useScreenSize(tester, const Size(800, 1400));
    await tester.pumpWidget(screenHarness(
      providers: [BlocProvider<PlayerCubit>.value(value: player)],
      child: const YtmSearchScreen(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty search prompt when there is no history',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byType(YtmSearchScreen), findsOneWidget);
    expect(find.byIcon(Icons.travel_explore_rounded), findsOneWidget);
    expect(find.text(l10n.searchYtm), findsWidgets);
  });

  testWidgets('renders history chips and tapping one runs a search',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ytm_search_history': ['Beatles', 'Queen'],
    });
    when(() => service.searchWithFallback(any()))
        .thenAnswer((_) async => [_track('dQw4w9WgXcQ', 'Hit')]);

    // pumpScreen builds the cubit so it reads the seeded history.
    await pumpScreen(tester);
    expect(find.byType(ActionChip), findsNWidgets(2));
    expect(find.text('Beatles'), findsOneWidget);

    await tester.tap(find.text('Queen'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    verify(() => service.searchWithFallback('Queen')).called(1);
    expect(find.byType(SongTile), findsOneWidget);
  });

  testWidgets('shows the skeleton while a search is in flight', (tester) async {
    final completer = Completer<List<YtmTrack>>();
    when(() => service.searchWithFallback(any()))
        .thenAnswer((_) => completer.future);

    await pumpScreen(tester);

    searchCubit.onQueryChanged('led zeppelin');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byType(SkeletonList), findsOneWidget);

    completer.complete([_track('dQw4w9WgXcQ', 'Kashmir')]);
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsNothing);
  });

  testWidgets('renders results and plays the tapped track', (tester) async {
    when(() => service.searchWithFallback(any()))
        .thenAnswer((_) async => [_track('dQw4w9WgXcQ', 'Never Gonna')]);

    await pumpScreen(tester);

    searchCubit.onQueryChanged('rick');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.byType(SongTile), findsOneWidget);
    expect(find.text('Never Gonna'), findsOneWidget);

    await tester.tap(find.byType(SongTile));
    await tester.pump();
    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('shows the no-results state when a search returns nothing',
      (tester) async {
    when(() => service.searchWithFallback(any()))
        .thenAnswer((_) async => const []);

    await pumpScreen(tester);
    searchCubit.onQueryChanged('nothing here');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    expect(find.text(l10n.browseNoResultsFound), findsOneWidget);
  });

  testWidgets('shows the error state and retries after a failure',
      (tester) async {
    var calls = 0;
    when(() => service.searchWithFallback(any())).thenAnswer((_) async {
      calls++;
      if (calls == 1) throw const YtmException('YTM_TIMEOUT');
      return [_track('dQw4w9WgXcQ', 'Recovered')];
    });

    await pumpScreen(tester);
    searchCubit.onQueryChanged('anything');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

    // Retry re-runs the search and this time it succeeds.
    await tester.tap(find.text(l10n.tryAgain));
    await tester.pumpAndSettle();

    expect(find.byType(SongTile), findsOneWidget);
    expect(find.text('Recovered'), findsOneWidget);
  });

  testWidgets('the clear affordance appears with a query and resets it',
      (tester) async {
    when(() => service.searchWithFallback(any()))
        .thenAnswer((_) async => [_track('dQw4w9WgXcQ', 'Hit')]);

    await pumpScreen(tester);
    searchCubit.onQueryChanged('typing');
    await tester.pumpAndSettle();

    final clearButton = find.byIcon(Icons.clear_rounded);
    expect(clearButton, findsOneWidget);

    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect(searchCubit.state.query, isEmpty);
    expect(find.byIcon(Icons.clear_rounded), findsNothing);
  });
}
