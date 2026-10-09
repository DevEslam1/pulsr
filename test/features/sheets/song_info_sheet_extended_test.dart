// test/features/sheets/song_info_sheet_extended_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';
import 'package:pulsr/data/audio/playback_bookmark_store.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/sheets/song_info_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/widgets/player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(testSong);
    registerFallbackValue(0.0);
    registerFallbackValue(0);
    registerFallbackValue('');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  MockPlayerCubit baseCubit({PlayerState? state, PlaybackBookmark? bookmark}) {
    final cubit = stubPlayerCubit(state: state ?? const PlayerState());
    when(() => cubit.storedBookmarkFor(any())).thenReturn(bookmark);
    when(() => cubit.setSongRating(any(), any())).thenAnswer((_) async {});
    when(() => cubit.setSongEqOverride(any(), any())).thenAnswer((_) async {});
    when(() => cubit.setSongVolumeOverride(any(), any()))
        .thenAnswer((_) async {});
    when(() => cubit.saveDspSnapshot()).thenAnswer((_) async {});
    when(() => cubit.saveBookmark()).thenAnswer((_) async => true);
    when(() => cubit.clearBookmark()).thenAnswer((_) async {});
    when(() => cubit.seek(any())).thenAnswer((_) async {});
    return cubit;
  }

  Future<void> pumpSheet(WidgetTester tester, MockPlayerCubit cubit) async {
    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: const SongInfoSheet(song: testSong),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders metadata and drives share, ringtone, rating and EQ',
      (tester) async {
    // Force a non-Android target so the ringtone capability is disabled.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final cubit = baseCubit();
    await pumpSheet(tester, cubit);

    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
    expect(find.text('QUALITY & CODEC'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Ringtone'), findsOneWidget);

    // Rating: tap a star.
    await tester.tap(find.byIcon(Icons.star_outline_rounded).first);
    await tester.pump();
    verify(() => cubit.setSongRating(testSong.id, 1)).called(1);

    // Ringtone is unsupported on this (non-Android) target.
    await tester.tap(find.text('Ringtone'));
    await tester.pump();
    expect(
      find.text('Ringtone setting is only supported on Android'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));

    // Volume slider commits a per-track override.
    final slider = find.byType(PulsrSlider);
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(60, 0));
    await tester.pumpAndSettle();
    verify(() => cubit.setSongVolumeOverride(any(), any()))
        .called(greaterThanOrEqualTo(1));

    // Share falls back to a text share; with no plugin it surfaces an error.
    await tester.ensureVisible(find.text('Share'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Share'));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(SnackBar), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('grants the playback tools: save DSP snapshot and bookmarks',
      (tester) async {
    final cubit = baseCubit(
      state: const PlayerState(
        playback: PlaybackSlice(currentSong: testSong),
      ),
      bookmark: PlaybackBookmark(
        trackKey: 'id:42',
        positionMs: 60000,
        durationMs: 210000,
        updatedAt: DateTime(2026),
      ),
    );
    await pumpSheet(tester, cubit);

    expect(find.text('Playback Tools'), findsOneWidget);
    expect(find.text('Bookmark'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    // Save the DSP snapshot.
    await tester.tap(find.text('Save DSP settings for this album'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    // Resume from the stored bookmark.
    await tester.tap(find.text('Resume'));
    await tester.pump();
    verify(() => cubit.seek(const Duration(milliseconds: 60000))).called(1);

    // Clear the bookmark.
    await tester.tap(find.text('Clear'));
    await tester.pump();
    verify(() => cubit.clearBookmark()).called(1);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('saves a bookmark for the active track', (tester) async {
    final cubit = baseCubit(
      state: const PlayerState(
        playback: PlaybackSlice(currentSong: testSong),
      ),
    );
    await pumpSheet(tester, cubit);

    await tester.tap(find.text('Save'));
    await tester.pump();
    verify(() => cubit.saveBookmark()).called(1);
    expect(find.text('Bookmark saved.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
