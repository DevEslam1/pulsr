// test/features/player/platter_scrub_song_change_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/cd_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/vinyl_player_theme.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  const song1 = SongsTableData(
    id: 101,
    title: 'Track One',
    artist: 'Artist A',
    album: 'Album A',
    durationMs: 300000,
    path: '/music/101.flac',
    dateAdded: 1600000000,
    playCount: 1,
    lastPositionMs: 60000,
    isFavorite: false,
    isMissing: false,
    source: 'local',
    isDownloaded: true,
  );

  const song2 = SongsTableData(
    id: 202,
    title: 'Track Two',
    artist: 'Artist B',
    album: 'Album B',
    durationMs: 240000,
    path: '/music/202.flac',
    dateAdded: 1600000001,
    playCount: 0,
    lastPositionMs: 0,
    isFavorite: false,
    isMissing: false,
    source: 'local',
    isDownloaded: true,
  );

  late _MockPlayerCubit mockPlayerCubit;
  late _MockSettingsCubit mockSettingsCubit;
  late PlayerState activeState;

  setUp(() {
    mockPlayerCubit = _MockPlayerCubit();
    mockSettingsCubit = _MockSettingsCubit();
    activeState = const PlayerState(
      playback: PlaybackSlice(
        currentSong: song1,
        isPlaying: true,
        duration: Duration(minutes: 5),
        position: Duration(minutes: 1),
      ),
    );

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());

    when(() => mockPlayerCubit.state).thenAnswer((_) => activeState);
    when(() => mockPlayerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => mockPlayerCubit.seek(any())).thenAnswer((_) async {});
  });

  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(500, 950),
          padding: EdgeInsets.zero,
        ),
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
              BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
            ],
            child: child,
          ),
        ),
      ),
    );
  }

  Finder scrubPillTextFinder() => find.byWidgetPredicate((widget) {
        if (widget is Text && widget.data != null) {
          return RegExp(r'^[+-]\d+\.\d+s$').hasMatch(widget.data!);
        }
        return false;
      });

  Future<TestGesture> startPlatterScrub(WidgetTester tester) async {
    final gestureDetector = find
        .byWidgetPredicate(
          (w) => w is GestureDetector && w.onPanStart != null,
        )
        .first;
    final center = tester.getCenter(gestureDetector);
    final gesture = await tester.startGesture(center + const Offset(50, 0));
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(scrubPillTextFinder(), findsOneWidget);
    return gesture;
  }

  for (final isCd in [true, false]) {
    final label = isCd ? '_CdJewelStage' : '_VinylTurntableDeck';

    Widget buildDeck(PlayerState state) {
      final props = PlayerThemeProps(
        state: state,
        cubit: mockPlayerCubit,
        activeColor: isCd ? Colors.cyanAccent : Colors.amberAccent,
        bgColor: Colors.black,
      );
      return wrapWithTheme(
        isCd ? CdPlayerTheme(props: props) : VinylPlayerTheme(props: props),
      );
    }

    testWidgets(
      '$label cancels in-progress platter scrub when currentSong.id changes and does not seek new track',
      (tester) async {
        await tester.pumpWidget(buildDeck(activeState));
        await tester.pump(const Duration(milliseconds: 100));

        final gesture = await startPlatterScrub(tester);

        // Track changes mid-drag.
        activeState = const PlayerState(
          playback: PlaybackSlice(
            currentSong: song2,
            isPlaying: true,
            duration: Duration(minutes: 4),
            position: Duration.zero,
          ),
        );
        await tester.pumpWidget(buildDeck(activeState));
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(scrubPillTextFinder(), findsNothing);

        // Subsequent drag updates and finger release must not seek the new track.
        await gesture.moveBy(const Offset(-20, 15));
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        verifyNever(() => mockPlayerCubit.seek(any()));
      },
    );

    testWidgets(
      '$label preserves in-progress platter scrub when position updates on same song id',
      (tester) async {
        await tester.pumpWidget(buildDeck(activeState));
        await tester.pump(const Duration(milliseconds: 100));

        final gesture = await startPlatterScrub(tester);

        // Position advances on the same song.
        activeState = const PlayerState(
          playback: PlaybackSlice(
            currentSong: song1,
            isPlaying: true,
            duration: Duration(minutes: 5),
            position: Duration(minutes: 1, seconds: 2),
          ),
        );
        await tester.pumpWidget(buildDeck(activeState));
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(scrubPillTextFinder(), findsOneWidget);

        await gesture.up();
        await tester.pump(const Duration(milliseconds: 100));

        verify(() => mockPlayerCubit.seek(any())).called(1);
      },
    );
  }
}
