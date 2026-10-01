import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/sheets/song_info_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;

  const dummySong = SongsTableData(
    id: 42,
    title: 'BPM Test Track',
    artist: 'BPM Artist',
    album: 'BPM Album',
    path: '/music/bpm_test.mp3',
    durationMs: 180000,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    dateAdded: 0,
    lastPositionMs: 0,
    source: SongSource.local,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockPlayerCubit = MockPlayerCubit();
    mockSettingsCubit = MockSettingsCubit();

    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayerCubit.setTrackBpm(any(), any()))
        .thenAnswer((_) async {});

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream.empty());
  });

  setUpAll(() {
    registerFallbackValue(dummySong);
  });

  testWidgets(
      '[M-12] _showBpmDialog distinguishes null (cancel) from empty string (clear)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
          BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SongInfoSheet(song: dummySong),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Scroll to Track BPM
    final bpmFinder = find.text('Track BPM');
    await tester.scrollUntilVisible(bpmFinder, 100);
    await tester.pumpAndSettle();

    // 1. Initial state: BPM is not set ("Not set")
    expect(find.text('Not set'), findsOneWidget);

    // 2. Tap to open BPM dialog
    await tester.tap(bpmFinder);
    await tester.pumpAndSettle();

    // Dialog is open with Cancel and Save buttons
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    // Clear button should not appear when currentBpm is null
    expect(find.text('Clear'), findsNothing);

    // 3. User cancels: tap Cancel (returns null)
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Null returned: no BPM cleared snackbar, no changes
    expect(find.text('BPM override cleared.'), findsNothing);
    expect(find.text('Not set'), findsOneWidget);

    // 4. Open dialog again, enter 128, and tap Save
    await tester.tap(bpmFinder);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '128');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Verified BPM is set to 128
    expect(find.text('128 BPM'), findsOneWidget);
    verify(() => mockPlayerCubit.setTrackBpm(dummySong, 128.0)).called(1);

    // 5. Open dialog again: now currentBpm is 128, so Clear button should appear
    await tester.tap(bpmFinder);
    await tester.pumpAndSettle();

    expect(find.text('Clear'), findsOneWidget);

    // 6. Tap Clear (returns empty string)
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    // Empty string returned with active BPM: cleared properly with snackbar
    expect(find.text('BPM override cleared.'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    verify(() => mockPlayerCubit.setTrackBpm(dummySong, null)).called(1);
  });
}
