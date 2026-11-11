// test/features/player/cubit/phase_4_truthfulness_test.dart
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/player/cubit/controllers/playback_volume_mute.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/player_volume_bar.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/player_sheet_test_support.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}

class _TestAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements PulsrAudioHandler {
  double _vol = 1.0;
  final BehaviorSubject<double> _volumeSubject =
      BehaviorSubject<double>.seeded(1.0);
  final Completer<void> _effectsReadyCompleter = Completer<void>();

  _TestAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: const [],
        systemActions: const {},
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    queue.add(const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  double get volume => _vol;

  @override
  Stream<double> get volumeStream => _volumeSubject.stream;

  @override
  Future<void> setVolume(double volume) async {
    _vol = volume.clamp(0.0, 1.0);
    _volumeSubject.add(_vol);
  }

  void emitHardwareVolume(double vol) {
    _vol = vol.clamp(0.0, 1.0);
    _volumeSubject.add(_vol);
  }

  @override
  Stream<SongsTableData> get onTrackChanged => const Stream.empty();

  @override
  Future<void> get effectsReady => _effectsReadyCompleter.future;

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration> get compensatedPositionStream => const Stream.empty();

  @override
  Stream<int?> get audioSessionIdStream => const Stream.empty();

  @override
  Stream<String> get errorStream => const Stream.empty();

  @override
  Stream<Duration> get sleepTimerRemainingStream => const Stream.empty();

  @override
  Stream<int?> get sleepTimerRemainingTracksStream => const Stream.empty();

  @override
  Future<void> stop() async {
    await _volumeSubject.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 4 — Reactive Volume & PlaybackVolumeMute', () {
    late _TestAudioHandler handler;

    setUp(() {
      handler = _TestAudioHandler();
    });

    tearDown(() async {
      await handler.stop();
    });

    test('PlaybackVolumeMute updates volume and isMuted on state without clobbering',
        () async {
      PlayerState state = const PlayerState();
      final controller = PlaybackVolumeMute(
        audioHandler: handler,
        getState: () => state,
        emit: (s) => state = s,
      );

      // 1. Initial state
      expect(state.volume, equals(1.0));
      expect(state.isMuted, isFalse);

      // 2. Set volume to 0.65
      await controller.setVolume(0.65);
      expect(state.volume, closeTo(0.65, 0.001));
      expect(state.isMuted, isFalse);
      expect(handler.volume, closeTo(0.65, 0.001));

      // 3. Adjust volume by -0.15 -> 0.50
      await controller.adjustVolume(-0.15);
      expect(state.volume, closeTo(0.50, 0.001));
      expect(state.isMuted, isFalse);

      // 4. Toggle mute -> volume 0, isMuted true
      await controller.toggleMute();
      expect(state.volume, closeTo(0.0, 0.001));
      expect(state.isMuted, isTrue);

      // 5. Toggle mute again -> restores pre-mute volume (0.50)
      await controller.toggleMute();
      expect(state.volume, closeTo(0.50, 0.001));
      expect(state.isMuted, isFalse);
    });

    test('PlayerCubit reacts to hardware-key volume stream updates', () async {
      final mockRepo = MockMusicRepository();
      final mockFav = MockToggleFavoriteUseCase();

      final cubit = PlayerCubit(
        audioHandler: handler,
        repository: mockRepo,
        toggleFavoriteUseCase: mockFav,
      );

      expect(cubit.state.volume, equals(1.0));

      // Simulate Android hardware volume button click (e.g. volume set to 0.40)
      handler.emitHardwareVolume(0.40);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // PlayerState.volume updated
      expect(cubit.state.volume, closeTo(0.40, 0.001));
      expect(cubit.state.isMuted, isFalse);

      // Hardware volume turned all the way down (0.0) -> isMuted = true
      handler.emitHardwareVolume(0.0);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cubit.state.volume, closeTo(0.0, 0.001));
      expect(cubit.state.isMuted, isTrue);

      // Hardware volume restored
      handler.emitHardwareVolume(0.85);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cubit.state.volume, closeTo(0.85, 0.001));
      expect(cubit.state.isMuted, isFalse);

      await cubit.close();
    });
  });

  group('PlayerVolumeBar Widget', () {
    testWidgets('renders volume controls and responds to PlayerCubit volume state',
        (tester) async {
      final cubit = stubPlayerCubit(
        state: const PlayerState().copyWith(
          playback: const PlaybackSlice(volume: 0.75, isMuted: false),
        ),
      );
      when(() => cubit.toggleMute()).thenAnswer((_) async {});
      when(() => cubit.setVolume(any())).thenAnswer((_) async {});

      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: PlayerVolumeBar(
          cubit: cubit,
          activeColor: Colors.deepPurple,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerVolumeBar), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsWidgets);

      // Tap mute button
      await tester.tap(find.byIcon(Icons.volume_up_rounded).first);
      await tester.pump();
      verify(() => cubit.toggleMute()).called(1);

      // Tap max volume button
      await tester.tap(find.byIcon(Icons.volume_up_rounded).last);
      await tester.pump();
      verify(() => cubit.setVolume(1.0)).called(1);
    });
  });
}
