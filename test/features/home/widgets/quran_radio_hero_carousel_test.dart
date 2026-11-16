import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:pulsr/features/home/presentation/widgets/quran_radio_hero_carousel.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _FakeRadioStation extends Fake implements RadioStation {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockPlayerCubit playerCubit;

  setUpAll(() {
    registerFallbackValue(_FakeRadioStation());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RadioStationStore.resetForTesting();
    playerCubit = _MockPlayerCubit();
    when(() => playerCubit.state).thenReturn(const PlayerState());
    when(() => playerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => playerCubit.playRadioStation(any())).thenAnswer((_) async {});
    when(() => playerCubit.togglePlayPause()).thenAnswer((_) async {});
  });

  tearDown(() {
    RadioStationStore.resetForTesting();
  });

  Widget buildHarness({
    required Widget child,
    VoidCallback? onMoreStations,
    Locale locale = const Locale('ar'),
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
          builder: (_, __) =>
              const Scaffold(body: Text('radio-directory-route')),
        ),
      ],
    );

    return BlocProvider<PlayerCubit>.value(
      value: playerCubit,
      child: MaterialApp.router(
        theme: AuraTheme.darkTheme,
        locale: locale,
        localizationsDelegates: appLocalizationsDelegates,
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

  testWidgets('swiping card changes to the next Quran station', (tester) async {
    await tester.pumpWidget(
      buildHarness(
        child: QuranRadioHeroCarousel(playerCubit: playerCubit),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/11'), findsOneWidget);

    // In RTL (Arabic), swiping forward to next page is dragging to the right (positive dx)
    await tester.fling(
      find.byType(PageView),
      const Offset(400, 0),
      1000,
    );
    await tester.pumpAndSettle();

    // Now page 2/11 is centered (Rare Khashia Recitations)
    expect(find.text('2/11'), findsOneWidget);
    expect(find.text('إذاعة تلاوات خاشعة نادرة'), findsOneWidget);

    // Swipe again to view 3rd station: Sheikh Minshawi rare recitations
    await tester.fling(
      find.byType(PageView),
      const Offset(400, 0),
      1000,
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

  testWidgets('tapping Radio navigation link routes to /radio', (tester) async {
    await tester.pumpWidget(
      buildHarness(
        locale: const Locale('en'),
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

  testWidgets('renders English text when locale is English', (tester) async {
    await tester.pumpWidget(
      buildHarness(
        locale: const Locale('en'),
        child: QuranRadioHeroCarousel(playerCubit: playerCubit),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sheikh Mohamed Siddiq El-Minshawi'), findsWidgets);
    expect(
      find.textContaining('Holy Quran • Reverent Mujawwad Recitation'),
      findsWidgets,
    );
    expect(find.text('Listen Now'), findsWidgets);
    // Windowed dot indicator caps visible dots at 7 even for 11+ stations.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics && (w.properties.label?.endsWith('/ 11') ?? false),
      ),
      findsNWidgets(7),
    );
  });

  testWidgets('landscape wide carousel aligns first card to leading edge',
      (tester) async {
    tester.view.physicalSize = const Size(850, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildHarness(
        locale: const Locale('en'),
        child: QuranRadioHeroCarousel(playerCubit: playerCubit),
      ),
    );
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.padEnds, isFalse);

    final carouselLeft =
        tester.getTopLeft(find.byType(QuranRadioHeroCarousel)).dx;
    final firstCardLeft = tester.getTopLeft(find.byType(InkWell).first).dx;
    expect(firstCardLeft - carouselLeft, lessThanOrEqualTo(6.0));
  });

  test(
      'buildMergedHeroItem localizes curated stations without Custom Station badge',
      () {
    const curatedMurattal = RadioStation(
      id: 'cur-quran-minshawi-murattal',
      name: 'إذاعة الشيخ محمد صديق المنشاوي (مرتل)',
      url: 'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi',
      genre: 'Quran',
    );
    final curatedItem =
        QuranRadioHeroCarousel.buildMergedHeroItem(curatedMurattal);
    expect(
      curatedItem.getReciterTitle(false),
      'Sheikh Mohamed Siddiq El-Minshawi (Murattal)',
    );
    expect(curatedItem.getBadgeText(false), 'Murattal');
    expect(curatedItem.getSubtitle(false), 'Holy Quran • Murattal Recitation');

    const userStation = RadioStation(
      id: 'user-123',
      name: 'My Local Quran Stream',
      url: 'https://example.com/quran.mp3',
      genre: 'Quran',
    );
    final customItem = QuranRadioHeroCarousel.buildMergedHeroItem(userStation);
    expect(customItem.getBadgeText(false), 'Custom Station');
    expect(customItem.getReciterTitle(false), 'My Local Quran Stream');
  });

  testWidgets('long-press opens Pin to First and Sorting options',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(
        locale: const Locale('en'),
        child: QuranRadioHeroCarousel(playerCubit: playerCubit),
      ),
    );
    await tester.pumpAndSettle();

    // Swipe to page 2 (Holy Quran Radio - Cairo or Rare Khashia Recitations)
    await tester.fling(
      find.byType(PageView),
      const Offset(-400, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('2/11'), findsOneWidget);

    // Long-press the 2nd card to open options sheet
    await tester.longPress(find.text('Rare Khashia Recitations Radio'));
    await tester.pumpAndSettle();

    expect(find.text('Pin to First'), findsOneWidget);
    expect(find.text('Sort Order'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('A–Z'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Hide Radio Cards from Home'), findsOneWidget);

    // Pin the 2nd card to first
    await tester.tap(find.text('Pin to First'));
    await tester.pumpAndSettle();

    // Carousel jumps to page 1/11 and shows the pinned card with pin icon
    expect(find.text('1/11'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_rounded), findsWidgets);
    expect(
      RadioStationStore.heroPinnedUrls.value,
      contains('https://backup.qurango.net/radio/salma'),
    );

    // Long-press again and unpin
    await tester.longPress(find.text('Rare Khashia Recitations Radio').first);
    await tester.pumpAndSettle();
    expect(find.text('Unpin'), findsOneWidget);
    await tester.tap(find.text('Unpin'));
    await tester.pumpAndSettle();

    expect(RadioStationStore.heroPinnedUrls.value, isEmpty);

    // Wait for the unpin toast overlay to dismiss before re-opening the sheet
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Long-press and switch sort order to A-Z
    await tester
        .longPress(find.text('Sheikh Mohamed Siddiq El-Minshawi').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('A–Z'));
    await tester.pumpAndSettle();

    expect(
        RadioStationStore.heroSortMode.value, QuranHeroSortMode.alphabetical);
    expect(find.text('Holy Quran Radio - Cairo'), findsWidgets);
  });

  test('sortAndPinItems respects pinned priority and sort modes', () {
    final base = QuranRadioHeroCarousel.defaultQuranStations();
    final cairoUrl = base[3].station.url; // Holy Quran Radio - Cairo
    final minshawiUrl = base[0].station.url;

    final sortedAlpha = QuranRadioHeroCarousel.sortAndPinItems(
      base,
      pinnedUrls: [minshawiUrl],
      sortMode: QuranHeroSortMode.alphabetical,
      isArabic: false,
    );
    expect(sortedAlpha.first.station.url, minshawiUrl);
    expect(
      sortedAlpha[1].getReciterTitle(false),
      'Holy Quran Radio - Cairo',
    );

    final sortedRecent = QuranRadioHeroCarousel.sortAndPinItems(
      base,
      pinnedUrls: const [],
      sortMode: QuranHeroSortMode.recentlyPlayed,
      isArabic: false,
      lastPlayedByUrl: {cairoUrl: 999999},
    );
    expect(sortedRecent.first.station.url, cairoUrl);
  });
}
