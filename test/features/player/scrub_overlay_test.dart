import 'package:flutter/material.dart';
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
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}
class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });
  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;

  const testSong = SongsTableData(
    id: 1,
    title: 'Scrub Test Song',
    artist: 'Audiophile Artist',
    album: 'Audiophile Master',
    durationMs: 300000,
    path: '/path/test.flac',
    dateAdded: 1600000000,
    playCount: 1,
    lastPositionMs: 60000,
    isFavorite: false,
    isMissing: false,
    source: 'local',
    isDownloaded: true,
  );

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    mockSettingsCubit = MockSettingsCubit();

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockPlayerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          duration: Duration(minutes: 5),
          position: Duration(minutes: 1),
        ),
      ),
    );
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayerCubit.seek(any())).thenAnswer((_) async {});
  });

  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
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

  testWidgets('0.3 CD stage renders signed seconds with 1 decimal while scrubbing', (tester) async {
    final state = PlayerState(
      playback: PlaybackSlice(
        currentSong: testSong,
        isPlaying: true,
        duration: const Duration(minutes: 5),
        position: const Duration(minutes: 1),
      ),
    );

    await tester.pumpWidget(
      wrapWithTheme(
        CdPlayerTheme(
          props: PlayerThemeProps(
            state: state,
            cubit: mockPlayerCubit,
            activeColor: Colors.cyanAccent,
            bgColor: Colors.black,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Find the turntable gesture detector with onPanStart
    final gestureDetector = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onPanStart != null,
    ).first;
    final center = tester.getCenter(gestureDetector);
    final gesture = await tester.startGesture(center + const Offset(50, 0));
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump(const Duration(milliseconds: 50));

    // Verify the scrub seconds overlay appears with a signed number and 1 decimal place, not literal 's'
    final signedSecondsFinder = find.byWidgetPredicate((widget) {
      if (widget is Text && widget.data != null) {
        return RegExp(r'^[+-]\d+\.\d+s$').hasMatch(widget.data!);
      }
      return false;
    });

    expect(signedSecondsFinder, findsOneWidget);
    // Explicitly confirm literal standalone 's' is NOT rendered
    expect(find.text('s'), findsNothing);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('0.3 Vinyl deck renders signed seconds with 1 decimal while scrubbing', (tester) async {
    final state = PlayerState(
      playback: PlaybackSlice(
        currentSong: testSong,
        isPlaying: true,
        duration: const Duration(minutes: 5),
        position: const Duration(minutes: 1),
      ),
    );

    await tester.pumpWidget(
      wrapWithTheme(
        VinylPlayerTheme(
          props: PlayerThemeProps(
            state: state,
            cubit: mockPlayerCubit,
            activeColor: Colors.amberAccent,
            bgColor: Colors.black,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Find the platter gesture detector with onPanStart
    final gestureDetector = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onPanStart != null,
    ).first;
    final center = tester.getCenter(gestureDetector);
    final gesture = await tester.startGesture(center + const Offset(50, 0));
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump(const Duration(milliseconds: 50));

    final signedSecondsFinder = find.byWidgetPredicate((widget) {
      if (widget is Text && widget.data != null) {
        return RegExp(r'^[+-]\d+\.\d+s$').hasMatch(widget.data!);
      }
      return false;
    });

    expect(signedSecondsFinder, findsOneWidget);
    expect(find.text('s'), findsNothing);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
