import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:pulsr/features/home/presentation/widgets/quran_radio_hero_carousel.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _FakeRadioStation extends Fake implements RadioStation {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockPlayerCubit playerCubit;

  setUpAll(() {
    registerFallbackValue(_FakeRadioStation());
  });

  setUp(() {
    playerCubit = _MockPlayerCubit();
    when(() => playerCubit.state).thenReturn(const PlayerState());
    when(() => playerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => playerCubit.playRadioStation(any())).thenAnswer((_) async {});
    when(() => playerCubit.togglePlayPause()).thenAnswer((_) async {});
  });

  Widget buildHarness({
    required Widget child,
    VoidCallback? onMoreStations,
  }) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(body: child),
        ),
        GoRoute(
          path: '/radio',
          builder: (_, __) => const Scaffold(body: Text('radio-directory-route')),
        ),
      ],
    );

    return BlocProvider<PlayerCubit>.value(
      value: playerCubit,
      child: MaterialApp.router(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  testWidgets('renders QuranRadioHeroCarousel starting with Menshawy',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        child: QuranRadioHeroCarousel(playerCubit: playerCubit),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Sheikh Minshawi is displayed on the initial card
    expect(find.text('الشيخ محمد صديق المنشاوي'), findsWidgets);
    expect(find.textContaining('المصحف المجود'), findsOneWidget);
    expect(find.text('1/11'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
  });

  testWidgets('tapping play button starts Minshawi radio stream',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        child: QuranRadioHeroCarousel(playerCubit: playerCubit),
      ),
    );
    await tester.pumpAndSettle();

    // Tap play button
    final playBtn = find.byIcon(Icons.play_arrow_rounded).first;
    await tester.tap(playBtn);
    await tester.pump();

    verify(() => playerCubit.playRadioStation(any(
          that: isA<RadioStation>()
              .having((s) => s.id, 'id', 'cur-quran-minshawi'),
        ))).called(1);
  });

  testWidgets('swiping card changes to the next Quran station',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        child: QuranRadioHeroCarousel(playerCubit: playerCubit),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/11'), findsOneWidget);

    // Swipe left (drag left) to view next station
    await tester.drag(
      find.byType(QuranRadioHeroCarousel),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();

    // Now page 2/11 is shown (Rare Khashia Recitations)
    expect(find.text('2/11'), findsOneWidget);
    expect(find.text('إذاعة تلاوات خاشعة نادرة'), findsOneWidget);

    // Swipe again to view 3rd station: Sheikh Minshawi rare recitations
    await tester.drag(
      find.byType(QuranRadioHeroCarousel),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('3/11'), findsOneWidget);
    expect(find.text('تلاوات نادرة ومحافل خاشعة'), findsOneWidget);
  });

  testWidgets('displays active playing live indicator when station is current',
      (tester) async {
    const minshawiUrl =
        'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi_mojawwad';
    const activeState = PlayerState(
      playback: PlaybackSlice(
        currentSong: SongsTableData(
          id: -100,
          title: 'إذاعة الشيخ محمد صديق المنشاوي (مجود)',
          artist: 'Quran',
          album: 'سورة يوسف - تلاوة خاشعة',
          durationMs: 0,
          path: minshawiUrl,
          source: SongSource.radio,
          remoteArtworkUrl: RadioStationStore.minshawiArtwork,
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 1,
          lastPositionMs: 0,
        ),
        isPlaying: true,
      ),
    );

    when(() => playerCubit.state).thenReturn(activeState);

    await tester.pumpWidget(
      buildHarness(
        child: QuranRadioHeroCarousel(playerCubit: playerCubit),
      ),
    );
    await tester.pump();

    // Shows live broadcasting pill and pause button
    expect(find.text('بث مباشر'), findsOneWidget);
    expect(find.text('سورة يوسف - تلاوة خاشعة'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // Tapping pause calls togglePlayPause
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();

    verify(() => playerCubit.togglePlayPause()).called(1);
  });

  testWidgets('tapping Radio navigation link routes to /radio',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        child: QuranRadioHeroCarousel(playerCubit: playerCubit),
      ),
    );
    await tester.pumpAndSettle();

    final radioLink = find.text('Radio');
    expect(radioLink, findsOneWidget);

    await tester.tap(radioLink);
    await tester.pumpAndSettle();

    expect(find.text('radio-directory-route'), findsOneWidget);
  });
}
