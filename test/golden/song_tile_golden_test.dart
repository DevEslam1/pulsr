// test/golden/song_tile_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

const _song = SongsTableData(
  id: 101,
  title: 'Golden Track',
  artist: 'Golden Artist',
  album: 'Golden Album',
  durationMs: 180000,
  path: '/path/101.mp3',
  dateAdded: 0,
  isFavorite: false,
  isMissing: false,
  isDownloaded: false,
  playCount: 0,
  lastPositionMs: 0,
  source: 'local',
);

const _otherSong = SongsTableData(
  id: 202,
  title: 'Other Track',
  artist: 'Other Artist',
  album: 'Other Album',
  durationMs: 200000,
  path: '/path/202.mp3',
  dateAdded: 0,
  isFavorite: false,
  isMissing: false,
  isDownloaded: false,
  playCount: 0,
  lastPositionMs: 0,
  source: 'local',
);

Widget _harness({required PlayerState state, required Widget child}) {
  final cubit = MockPlayerCubit();
  when(() => cubit.state).thenReturn(state);
  when(() => cubit.stream).thenAnswer((_) => const Stream<PlayerState>.empty());

  return MultiBlocProvider(
    providers: [BlocProvider<PlayerCubit>.value(value: cubit)],
    child: MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            child: SizedBox(width: 390, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('SongTile normal golden', (tester) async {
    await tester.pumpWidget(
      _harness(
        state: const PlayerState(
          playback: PlaybackSlice(currentSong: _otherSong, isPlaying: false),
        ),
        child: SongTile(song: _song, onTap: () {}),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SongTile),
      matchesGoldenFile('goldens/song_tile_normal.png'),
    );
  });

  testWidgets('SongTile selected golden', (tester) async {
    await tester.pumpWidget(
      _harness(
        state: const PlayerState(
          playback: PlaybackSlice(currentSong: _otherSong, isPlaying: false),
        ),
        child: SongTile(song: _song, onTap: () {}, selected: true),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SongTile),
      matchesGoldenFile('goldens/song_tile_selected.png'),
    );
  });

  testWidgets('SongTile playing golden', (tester) async {
    await tester.pumpWidget(
      _harness(
        state: const PlayerState(
          playback: PlaybackSlice(currentSong: _song, isPlaying: true),
        ),
        child: SongTile(song: _song, onTap: () {}),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SongTile),
      matchesGoldenFile('goldens/song_tile_playing.png'),
    );
  });
}
