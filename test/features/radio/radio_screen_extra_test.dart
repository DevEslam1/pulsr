// Additional coverage for lib/features/radio/presentation/radio_screen.dart
//
// Complements radio_screen_test.dart with the populated list, genre chips,
// search + clear, station playback (idle + currently playing), add-dialog
// validation, manual import and curated import.
//
// NOTE: the long-press actions sheet is intentionally not driven here:
// PulsrBottomSheet wraps its ListTiles in a coloured DecoratedBox with no
// intervening Material, which trips ListTile's debug assertion and fails any
// widget test that opens it. That is a lib-side invariant, not a test gap.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/radio/presentation/radio_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_song_factory.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

const _s1 = {
  'id': 's1',
  'name': 'Chill Beats',
  'url': 'https://a.example.com/live',
  'genre': 'Chill',
};
const _s2 = {
  'id': 's2',
  'name': 'Rock Radio',
  'url': 'https://b.example.com/live',
  'genre': 'Rock',
};
const _s3 = {
  'id': 's3',
  'name': 'Deep Ambient',
  'url': 'https://c.example.com/live',
  'genre': 'Chill',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockPlayerCubit player;

  setUpAll(() {
    registerFallbackValue(const RadioStation(
      id: 'fallback',
      name: 'Fallback',
      url: 'https://fallback.example.com/live',
    ));
  });

  setUp(() {
    RadioStationStore.resetForTesting();
    SharedPreferences.setMockInitialValues({
      RadioStationStore.prefsKey: jsonEncode([_s1, _s2, _s3]),
    });
    player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => player.playRadioStation(any())).thenAnswer((_) async {});
    when(() => player.togglePlayPause()).thenAnswer((_) async {});
  });

  tearDown(RadioStationStore.resetForTesting);

  Future<void> pumpRadio(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 1600);
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
        home: BlocProvider<PlayerCubit>.value(
          value: player,
          child: const RadioScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  // Flushes StaggeredReveal / toast timers so no timer outlives the test.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('populated list renders stations and genre chips',
      (tester) async {
    await pumpRadio(tester);

    expect(find.text('Chill Beats'), findsOneWidget);
    expect(find.text('Rock Radio'), findsOneWidget);
    expect(find.text('Deep Ambient'), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(3));
    expect(find.widgetWithText(FilterChip, l10n.all), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Rock'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('search narrows the list and the clear action restores it',
      (tester) async {
    await pumpRadio(tester);

    await tester.enterText(find.byType(TextField).first, 'rock');
    await tester.pump();

    expect(find.text('Rock Radio'), findsOneWidget);
    expect(find.text('Chill Beats'), findsNothing);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(find.text('Chill Beats'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('genre chips filter the list', (tester) async {
    await pumpRadio(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Rock'));
    await tester.pump();

    expect(find.text('Rock Radio'), findsOneWidget);
    expect(find.text('Chill Beats'), findsNothing);

    await drain(tester);
  });

  testWidgets('tapping a station starts playback', (tester) async {
    await pumpRadio(tester);

    await tester.tap(find.text('Rock Radio'));
    await tester.pump();

    verify(() => player.playRadioStation(any())).called(1);

    await drain(tester);
  });

  testWidgets('the currently-playing station toggles playback',
      (tester) async {
    final song = createTestSong(path: 'https://b.example.com/live');
    when(() => player.state).thenReturn(PlayerState(
      playback: PlaybackSlice(currentSong: song, isPlaying: true),
    ));

    await pumpRadio(tester);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Rock Radio'));
    await tester.pump();

    verify(() => player.togglePlayPause()).called(1);
    verifyNever(() => player.playRadioStation(any()));

    await drain(tester);
  });

  testWidgets('add dialog validates the stream URL', (tester) async {
    await pumpRadio(tester);

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();

    final urlField = find.descendant(
      of: find.byType(Dialog),
      matching: find.widgetWithText(TextField, l10n.radioStationUrl),
    );

    await tester.tap(find.widgetWithText(FilledButton, l10n.radioAdd));
    await tester.pump();
    expect(find.text(l10n.radioErrorEnterUrl), findsOneWidget);

    await tester.enterText(urlField, 'ftp://nope');
    await tester.tap(find.widgetWithText(FilledButton, l10n.radioAdd));
    await tester.pump();
    expect(find.text(l10n.radioErrorUrlScheme), findsOneWidget);

    await tester.enterText(urlField, 'https://valid.example.com/stream');
    await tester.tap(find.widgetWithText(FilledButton, l10n.radioAdd));
    await tester.pumpAndSettle();

    expect(find.text('valid.example.com'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('manual import adds the parsed stream URLs', (tester) async {
    await pumpRadio(tester);

    await tester.tap(find.byIcon(Icons.playlist_add_rounded));
    await tester.pumpAndSettle();

    final dialogField = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(
        dialogField, '#EXTM3U\nhttps://stream.example.com/live.mp3\n');
    await tester.tap(find.widgetWithText(FilledButton, l10n.radioImport));
    await tester.pumpAndSettle();

    expect(find.text('stream.example.com'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('manual import with no valid streams reports it',
      (tester) async {
    await pumpRadio(tester);

    await tester.tap(find.byIcon(Icons.playlist_add_rounded));
    await tester.pumpAndSettle();

    final dialogField = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogField, 'this is not a stream');
    await tester.tap(find.widgetWithText(FilledButton, l10n.radioImport));
    await tester.pumpAndSettle();

    expect(find.text(l10n.radioNoStreamsFound), findsOneWidget);

    await drain(tester);
  });

  testWidgets('curated import adds stations then reports up-to-date',
      (tester) async {
    await pumpRadio(tester);

    await tester.tap(find.byIcon(Icons.explore_rounded));
    await tester.pumpAndSettle();

    expect(find.text(l10n.radioCuratedAdded(11)), findsOneWidget);

    await tester.tap(find.byIcon(Icons.explore_rounded));
    await tester.pumpAndSettle();

    expect(find.text(l10n.radioCuratedUpToDate), findsOneWidget);

    await drain(tester);
  });
}
