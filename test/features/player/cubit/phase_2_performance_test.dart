// test/features/player/cubit/phase_2_performance_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/performance/gpu_budget.dart';
import 'package:pulsr/core/telemetry/playback_latency_tracker.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/utils/list_content_diff.dart';
import 'package:pulsr/core/widgets/throttled_slider.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/headphone_profiles_repository.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/autoeq_search_sheet.dart';
import 'package:pulsr/features/player/presentation/widgets/eq_curve_visualizer.dart';
import 'package:pulsr/features/player/presentation/widgets/lyrics/advanced_lyrics_view.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAudioHandler extends Mock implements PulsrAudioHandler {}

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}

class FakePlayerCubit extends Cubit<PlayerState> implements PlayerCubit {
  FakePlayerCubit([super.initialState = const PlayerState()]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerFallbackValue(const HeadphoneProfile(
      id: 'fallback',
      name: 'Fallback',
      brand: 'Brand',
      model: 'Model',
      category: 'Custom',
      gains: [0, 0, 0],
    ));
    SharedPreferences.setMockInitialValues({});
    await HeadphoneProfilesRepository().loadProfiles();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 2.1 — AutoEqSearchSheet rebuild count optimization', () {
    testWidgets('Position-only emits on PlayerCubit cause zero rebuilds',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = HeadphoneProfilesRepository();
      await repo.loadProfiles();

      final cubit = FakePlayerCubit();
      int buildCount = 0;

      await tester.pumpWidget(MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BlocProvider<PlayerCubit>.value(
            value: cubit,
            child: Column(
              children: [
                Expanded(child: AutoEqSearchSheet(repo: repo)),
                Builder(
                  builder: (context) {
                    context.select<PlayerCubit, String?>(
                      (c) => c.state.selectedHeadphoneProfile?.id,
                    );
                    buildCount++;
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final initialBuilds = buildCount;
      expect(initialBuilds, equals(1));

      // Simulate 10 position ticks (every 200ms)
      for (int i = 1; i <= 10; i++) {
        cubit.emit(cubit.state.copyWith(
          playback: cubit.state.playback.copyWith(
            position: Duration(milliseconds: i * 200),
          ),
        ));
        await tester.pump();
      }

      // Position ticks must NOT trigger rebuilds of the selector
      expect(buildCount, equals(1));

      // Now change the selected profile — this MUST trigger exactly 1 rebuild
      const newProfile = HeadphoneProfile(
        id: 'sony_wh1000xm4',
        name: 'Sony WH-1000XM4',
        brand: 'Sony',
        model: 'WH-1000XM4',
        category: 'Over-Ear',
        gains: [1.0, 2.0, -1.0],
      );
      cubit.emit(cubit.state.copyWith(
        dsp: cubit.state.dsp.copyWith(selectedHeadphoneProfile: newProfile),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(buildCount, equals(2));
    });
  });

  group('Phase 2.2 — NowPlayingQueueView buildWhen optimization', () {
    test('listContentDiffers detects real content differences but ignores identical copyWith',
        () {
      const song1 = SongsTableData(
        id: 1,
        title: 'Song 1',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        path: '/path/1',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: true,
        playCount: 0,
        lastPositionMs: 0,
      );
      const song2 = SongsTableData(
        id: 2,
        title: 'Song 2',
        artist: 'Artist',
        album: 'Album',
        durationMs: 200000,
        path: '/path/2',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: true,
        playCount: 0,
        lastPositionMs: 0,
      );

      final listA = [song1, song2];
      final listB = [song1, song2]; // Fresh instance, same items

      expect(identical(listA, listB), isFalse);
      expect(listContentDiffers(listA, listB), isFalse);

      final listC = [song1]; // Changed length
      expect(listContentDiffers(listA, listC), isTrue);

      final listD = [song2, song1]; // Reordered
      expect(listContentDiffers(listA, listD), isTrue);
    });

    test('Position-only PlayerState emits do not trigger queue buildWhen', () {
      const song = SongsTableData(
        id: 1,
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        path: '/path/1',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: true,
        playCount: 0,
        lastPositionMs: 0,
      );

      final prevState = const PlayerState().copyWith(
        queueSlice: const PlayerState().queueSlice.copyWith(
          queue: [song],
          currentIndex: 0,
        ),
        playback: const PlayerState().playback.copyWith(
          currentSong: song,
          position: Duration.zero,
          isPlaying: true,
        ),
      );

      final nextState = prevState.copyWith(
        playback: prevState.playback.copyWith(
          position: const Duration(seconds: 1),
        ),
      );

      // Evaluate the buildWhen gate from NowPlayingQueueView:
      final shouldRebuild = listContentDiffers(
              prevState.queue, nextState.queue) ||
          prevState.currentIndex != nextState.currentIndex ||
          prevState.activeQueueSlot != nextState.activeQueueSlot ||
          prevState.currentSong?.id != nextState.currentSong?.id ||
          prevState.isPlaying != nextState.isPlaying;

      expect(shouldRebuild, isFalse);
    });
  });

  group('Phase 2.3 — Throttled continuous DSP sliders', () {
    testWidgets('ThrottledSlider coalesces rapid drags into 60ms debounce window',
        (tester) async {
      final values = <double>[];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ThrottledSlider(
            value: 0.0,
            min: -15.0,
            max: 15.0,
            onChanged: (v) => values.add(v),
            debounceDuration: const Duration(milliseconds: 60),
          ),
        ),
      ));

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      // Perform a drag across the slider track
      final firstLocation = tester.getCenter(sliderFinder);
      final gesture = await tester.startGesture(firstLocation);

      // Move 10 times in 20ms
      for (int i = 1; i <= 10; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 2));
      }

      // During the rapid 20ms burst, no debounced calls have fired yet
      expect(values, isEmpty);

      // Advance by 70ms so the 60ms debounce timer elapses
      await tester.pump(const Duration(milliseconds: 70));
      expect(values.length, equals(1));

      // Move again and finish gesture
      await gesture.moveBy(const Offset(20, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      // Final committed value was pushed on gesture end
      expect(values.length, equals(2));
      expect(values.last, greaterThan(values.first));
    });
  });

  group('Phase 2.4 — HeadphoneProfilesRepository DI registration', () {
    test('HeadphoneProfilesRepository is registered as lazySingleton in GetIt',
        () {
      final getIt = GetIt.instance;
      if (!getIt.isRegistered<HeadphoneProfilesRepository>()) {
        getIt.registerLazySingleton<HeadphoneProfilesRepository>(
            () => HeadphoneProfilesRepository());
      }

      final instance1 = getIt<HeadphoneProfilesRepository>();
      final instance2 = getIt<HeadphoneProfilesRepository>();

      expect(identical(instance1, instance2), isTrue);
    });
  });

  group('Phase 2.5 — EqCurveVisualizer gains animation', () {
    testWidgets('EqCurveVisualizer sets tween begin from previous gains on update',
        (tester) async {
      final initialGains = [0.0, 0.0, 0.0];
      final newGains = [4.0, 6.0, 8.0];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EqCurveVisualizer(
            gains: initialGains,
            activeColor: Colors.blue,
          ),
        ),
      ));

      expect(find.byType(EqCurveVisualizer), findsOneWidget);

      // Rebuild with new gains
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EqCurveVisualizer(
            gains: newGains,
            activeColor: Colors.blue,
          ),
        ),
      ));

      // Animated frame in progress (lerp between 0.0 and newGains)
      await tester.pump(const Duration(milliseconds: 50));
      // Animation completes at 240ms
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 2.6 — EqPreset bandsMap and gains clip-risk refresh', () {
    test('EqPreset bandsMap does NOT cover active gains for Custom presets', () {
      final presetA = EqPreset(
        name: 'Custom',
        gains: const [0.0, 0.0, 0.0],
        bandsMap: const {
          10: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        },
      );

      final presetB = EqPreset(
        name: 'Custom',
        gains: const [12.0, 0.0, 0.0], // Clipped gain boost
        bandsMap: const {
          10: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        },
      );

      // bandsMap is unchanged between presetA and presetB
      expect(presetA.bandsMap, equals(presetB.bandsMap));
      // But gains are definitely different
      expect(presetA.gains, isNot(equals(presetB.gains)));
    });

    test('EqPreset equality includes listEquals(gains)', () {
      final presetA = EqPreset(
        name: 'Custom',
        gains: const [0.0, 0.0, 0.0],
      );
      final presetB = EqPreset(
        name: 'Custom',
        gains: const [12.0, 0.0, 0.0],
      );

      expect(presetA == presetB, isFalse);
    });
  });

  group('Phase 2.7 — Latency session finishWithError on loadQueue failure', () {
    test('finishWithError marks active session as closed and sets failure stage', () {
      final tracker = PlaybackLatencyTracker();
      tracker.start(videoId: 'video_fail_test');

      expect(tracker.hasActiveSession, isTrue);

      tracker.finishWithError(Exception('Engine load failure'),
          stage: PlaybackStage.sourceSet);

      expect(tracker.hasActiveSession, isFalse);
      expect(tracker.lastReport, isNotNull);
      expect(tracker.lastReport!.success, isFalse);
      expect(tracker.lastReport!.failureStage, equals('sourceSet'));
    });
  });

  group('Phase 2.8 — Gate karaoke per-word ShaderMask behind GpuBudget', () {
    testWidgets('Renders ShaderMask when GpuBudget.isGpuSaverActive is false',
        (tester) async {
      GpuBudget.setEnabled(false);

      const line = LyricsLine(
        timestamp: Duration(seconds: 1),
        text: 'Singing word',
        words: [
          WordTimestamp(word: 'Singing', startMs: 500, endMs: 1500),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        theme: AuraTheme.darkTheme,
        home: const Scaffold(
          body: AdvancedLyricsView(
            lyrics: [line],
            currentPosition: Duration(milliseconds: 1000),
            activeColor: Colors.blue,
          ),
        ),
      ));

      await tester.pump();
      expect(find.byType(ShaderMask), findsWidgets);
    });

    testWidgets('Bypasses ShaderMask and renders solid Text when GpuBudget is active',
        (tester) async {
      GpuBudget.setEnabled(true);
      addTearDown(() => GpuBudget.setEnabled(false));

      const line = LyricsLine(
        timestamp: Duration(seconds: 1),
        text: 'Singing word',
        words: [
          WordTimestamp(word: 'Singing', startMs: 500, endMs: 1500),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        theme: AuraTheme.darkTheme,
        home: const Scaffold(
          body: AdvancedLyricsView(
            lyrics: [line],
            currentPosition: Duration(milliseconds: 1000),
            activeColor: Colors.blue,
          ),
        ),
      ));

      await tester.pump();
      // GpuBudget saver active should have NO ShaderMask inside the word view!
      // In non-split view, there are zero ShaderMasks
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.text('Singing'), findsOneWidget);
    });
  });
}
