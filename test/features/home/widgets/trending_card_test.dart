import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/home/presentation/widgets/home_card_metrics.dart';
import 'package:pulsr/features/home/presentation/widgets/trending_card.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _song = SongsTableData(
  id: 7,
  title: 'Trending Track',
  artist: 'Trending Artist',
  album: 'Trending Album',
  durationMs: 210000,
  path: 'ytmusic://video7',
  source: SongSource.youtube,
  remoteId: 'video7',
  isFavorite: false,
  isMissing: false,
  isDownloaded: false,
  playCount: 0,
  lastPositionMs: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget app(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Center(child: child)),
        ),
      );

  group('TrendingCard', () {
    testWidgets('renders harmonized 2-tier title, artist, frame, and play badge',
        (tester) async {
      await tester.pumpWidget(app(TrendingCard(song: _song, onTap: () {})));
      await tester.pump();

      final titleText = tester.widget<Text>(find.text(_song.title));
      expect(titleText.maxLines, 1);
      expect(titleText.style?.fontSize, AppFontSize.bodySmall);
      expect(titleText.style?.fontWeight, FontWeight.w700);

      final artistText = tester.widget<Text>(find.text(_song.artist));
      expect(artistText.maxLines, 1);
      expect(artistText.style?.fontSize, AppFontSize.caption);

      expect(find.byType(HomeCardArtworkFrame), findsOneWidget);
      expect(find.byType(HomeCardPlayBadge), findsOneWidget);
    });

    testWidgets('shows equalizer badge when active and playing', (tester) async {
      await tester.pumpWidget(
        app(
          TrendingCard(
            song: _song,
            onTap: () {},
            isCurrent: true,
            isPlaying: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('eq')), findsOneWidget);
    });

    testWidgets('fires onTap when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        app(TrendingCard(song: _song, onTap: () => taps++)),
      );
      await tester.pump();

      await tester.tap(find.byType(TrendingCard));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
