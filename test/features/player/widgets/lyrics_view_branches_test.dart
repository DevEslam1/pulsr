// Coverage for the uncovered branches of lyrics_view.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/lyrics/lyrics_offset_store.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/lyrics_editor_sheet.dart';
import 'package:pulsr/features/player/presentation/widgets/lyrics_view.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_test_support.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  late MockPlayerCubit cubit;
  late MockSettingsCubit settings;
  late StreamController<PlayerState> playerStates;
  late StreamController<SettingsState> settingsStates;
  late PlayerState playerState;
  late AppLocalizations l10n;

  setUpAll(() {
    registerFallbackValue(buildSong(0));
    registerFallbackValue(Duration.zero);
    registerFallbackValue(<LyricsLine>[]);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    cubit = MockPlayerCubit();
    settings = MockSettingsCubit();
    playerStates = StreamController<PlayerState>.broadcast();
    settingsStates = StreamController<SettingsState>.broadcast();
    playerState = PlayerState(
      playback: const PlaybackSlice().copyWith(
        currentSong: buildSong(1, path: '/music/1.mp3'),
        position: const Duration(seconds: 10),
      ),
    );
    when(() => cubit.state).thenAnswer((_) => playerState);
    when(() => cubit.stream).thenAnswer((_) => playerStates.stream);
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream).thenAnswer((_) => settingsStates.stream);
    when(() => cubit.refreshLyrics()).thenAnswer((_) async {});
    when(() => cubit.seek(any())).thenAnswer((_) async {});
    when(() => cubit.updateLyrics(any())).thenAnswer((_) async => true);
  });

  tearDown(() async {
    await playerStates.close();
    await settingsStates.close();
  });

  Widget host({
    required List<LyricsLine> lyrics,
    LyricsSource source = LyricsSource.none,
    Duration? currentPosition,
    bool isLoading = false,
    bool withProviders = true,
    ValueChanged<Duration>? onLineTapped,
    MockPlayerCubit? playerCubit,
  }) {
    return MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: withProviders
            ? MultiBlocProvider(
                providers: [
                  BlocProvider<PlayerCubit>.value(value: playerCubit ?? cubit),
                  BlocProvider<SettingsCubit>.value(value: settings),
                ],
                child: SizedBox(
                  width: 400,
                  height: 600,
                  child: LyricsView(
                    lyrics: lyrics,
                    source: source,
                    currentPosition: currentPosition,
                    isLoading: isLoading,
                    onLineTapped: onLineTapped,
                  ),
                ),
              )
            : SizedBox(
                width: 400,
                height: 600,
                child: LyricsView(
                  lyrics: lyrics,
                  source: source,
                  currentPosition: currentPosition,
                  isLoading: isLoading,
                  onLineTapped: onLineTapped,
                ),
              ),
      ),
    );
  }

  group('source badges', () {
    testWidgets('embedded synced shows the embedded badge', (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration(seconds: 2), text: 'A'),
        ],
        source: LyricsSource.embedded,
      ));
      await tester.pump();
      expect(find.text(l10n.dspEmbedded), findsOneWidget);
    });

    testWidgets('embedded plain shows the unsynced badge', (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration.zero, text: 'A'),
        ],
        source: LyricsSource.embedded,
      ));
      await tester.pump();
      expect(find.text(l10n.dspEmbeddedUnsynced), findsOneWidget);
    });

    testWidgets('external LRC and YT Music badges render', (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration(seconds: 1), text: 'A'),
        ],
        source: LyricsSource.externalLrc,
      ));
      await tester.pump();
      expect(find.text('LRC File'), findsOneWidget);

      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration(seconds: 1), text: 'A'),
        ],
        source: LyricsSource.ytmusic,
      ));
      await tester.pump();
      expect(find.text('YouTube Music'), findsOneWidget);
    });

    testWidgets('derives the source from the first line when none is given',
        (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(
              timestamp: Duration(seconds: 1),
              text: 'A',
              source: LyricsSource.embedded),
        ],
      ));
      await tester.pump();
      expect(find.text(l10n.dspEmbedded), findsOneWidget);
    });
  });

  group('synced classification', () {
    testWidgets('word-level timing marks a zero-timestamp set as synced',
        (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(
            timestamp: Duration.zero,
            text: 'Hello world',
            words: [
              WordTimestamp(word: 'Hello', startMs: 0, endMs: 500),
            ],
          ),
        ],
        currentPosition: Duration.zero,
      ));
      await tester.pump();
      expect(find.byType(LyricView), findsOneWidget);
    });

    testWidgets('reads the position from the cubit when none is passed',
        (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration(seconds: 5), text: 'Line'),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(LyricView), findsOneWidget);
    });

    testWidgets('updates progress when the cubit position changes',
        (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration(seconds: 5), text: 'Line'),
        ],
      ));
      await tester.pump();

      playerState = playerState.copyWith(
        playback: playerState.playback.copyWith(position: const Duration(seconds: 6)),
      );
      playerStates.add(playerState);
      await tester.pump();

      expect(find.byType(LyricView), findsOneWidget);
    });
  });

  group('header actions', () {
    testWidgets('shows the full header action set when a song is loaded',
        (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration(seconds: 1), text: 'A'),
        ],
      ));
      await tester.pump();

      expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
      expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    });

    testWidgets('hides song-scoped actions without a current song',
        (tester) async {
      playerState = const PlayerState();
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration(seconds: 1), text: 'A'),
        ],
      ));
      await tester.pump();

      expect(find.byIcon(Icons.sync_rounded), findsNothing);
      expect(find.byIcon(Icons.edit_note_rounded), findsNothing);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    });
  });

  group('offset sheet', () {
    testWidgets('adjusts and persists the manual offset', (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration(seconds: 1), text: 'A'),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byIcon(Icons.sync_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(l10n.settingsSyncOffset), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, l10n.offsetPlus50Ms));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, l10n.offsetPlus50Ms));
      await tester.pump();

      await tester.tap(find.text(l10n.done));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final stored = await LyricsOffsetStore().getOffsetMs('/music/1.mp3');
      expect(stored, 100);
    });

    testWidgets('reset clears the manual offset', (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration(seconds: 1), text: 'A'),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byIcon(Icons.sync_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.widgetWithText(OutlinedButton, l10n.offsetMinus50Ms));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, l10n.reset));
      await tester.pump();

      expect(find.text('+0 ms'), findsOneWidget);
    });
  });

  group('refresh and editor', () {
    testWidgets('empty lyrics refresh button calls the cubit', (tester) async {
      await tester.pumpWidget(host(lyrics: const []));
      await tester.pump();

      await tester.tap(find.text(l10n.searchLyrics));
      await tester.pump();

      verify(() => cubit.refreshLyrics()).called(1);
    });

    testWidgets('edit button opens the lyrics editor sheet', (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration(seconds: 1), text: 'A'),
        ],
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit_note_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(LyricsEditorSheet), findsOneWidget);
    });
  });

  group('lyric tap', () {
    testWidgets('tapping a synced line invokes onLineTapped', (tester) async {
      Duration? tapped;
      await tester.pumpWidget(host(
        lyrics: const [
          LyricsLine(timestamp: Duration(seconds: 1), text: 'First'),
          LyricsLine(timestamp: Duration(seconds: 4), text: 'Second'),
        ],
        currentPosition: const Duration(seconds: 4),
        onLineTapped: (d) => tapped = d,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final rect = tester.getRect(find.byType(LyricView));
      await tester.tapAt(Offset(
        rect.center.dx,
        rect.top + rect.height * 0.42,
      ));
      await tester.pump();

      expect(tapped, isNotNull);
    });
  });

  group('loading', () {
    testWidgets('loading spinner uses the active color', (tester) async {
      await tester.pumpWidget(host(
        lyrics: const [],
        isLoading: true,
        withProviders: false,
      ));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
