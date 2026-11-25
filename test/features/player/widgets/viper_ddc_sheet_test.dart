// test/features/player/widgets/viper_ddc_sheet_test.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/viper_ddc_sheet.dart';

import 'player_sheet_test_support.dart';

class _FailingPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() =>
      Future<String?>.error(StateError('temp dir unavailable'));
}

class _StubAudioPlayerPlatform extends AudioPlayerPlatform {
  _StubAudioPlayerPlatform(super.id);

  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => const Stream.empty();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
          SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    if (!_events.isClosed) await _events.close();
    return DisposeResponse();
  }
}

class _StubJustAudioPlatform extends JustAudioPlatform {
  final Map<String, _StubAudioPlayerPlatform> _players = {};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = _StubAudioPlayerPlatform(request.id);
    _players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    await _players.remove(request.id)?.dispose(DisposeRequest());
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
      DisposeAllPlayersRequest request) async {
    for (final player in _players.values) {
      await player.dispose(DisposeRequest());
    }
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}

Uint8List _float32(List<double> values) {
  final bd = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    bd.setFloat32(i * 4, values[i], Endian.little);
  }
  return bd.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViperDdcParser', () {
    test('validateFilterStability uses the Jury criterion', () {
      expect(ViperDdcParser.validateFilterStability(0.5, 0.4), isTrue);
      expect(ViperDdcParser.validateFilterStability(0.0, 1.5), isFalse);
      expect(ViperDdcParser.validateFilterStability(3.0, 0.4), isFalse);
    });

    test('rejects files that are too short', () {
      expect(
        () => ViperDdcParser.parseBytes(Uint8List.fromList([1, 2])),
        throwsA(isA<String>()),
      );
    });

    test('parses comma-separated text biquad stages', () {
      final bytes = Uint8List.fromList(
        '1, 2, 3, -0.5, 0.1\r\n'.codeUnits,
      );
      final coeffs = ViperDdcParser.parseBytes(bytes);
      expect(coeffs, [1.0, 1.0, 2.0, 3.0, -0.5, 0.1]);
    });

    test('parses ###-delimited text blocks and skips comments', () {
      const text = '# a comment\n'
          '###\n'
          '1 2 3 -0.5 0.1\n'
          '###\n'
          '1 2 3 -0.4 0.2\n';
      final coeffs = ViperDdcParser.parseText(text);
      expect(coeffs.first, 1.0);
      expect(coeffs.length, 12);
    });

    test('rejects an unstable text stage', () {
      expect(
        () => ViperDdcParser.parseText('1 2 3 0 1.5\n'),
        throwsA(isA<String>()),
      );
    });

    test('rejects text with no valid coefficients', () {
      expect(
        () => ViperDdcParser.parseText('# only comments\n'),
        throwsA(isA<String>()),
      );
    });

    test('parses a valid binary coefficient block', () {
      final coeffs = ViperDdcParser.parseBytes(
        _float32([1.0, -0.5, 0.2, -0.5, 0.1]),
      );
      expect(coeffs, hasLength(5));
      expect(coeffs[0], closeTo(1.0, 0.0001));
    });

    test('rejects corrupt binary coefficients', () {
      expect(
        () => ViperDdcParser.parseBytes(
          _float32([20000.0, 1.0, 1.0, -0.5, 0.1]),
        ),
        throwsA(isA<String>()),
      );
    });

    test('rejects unstable binary coefficients', () {
      expect(
        () => ViperDdcParser.parseBytes(
          _float32([1.0, 1.0, 1.0, 0.0, 1.5]),
        ),
        throwsA(isA<String>()),
      );
    });

    test('rejects an invalid binary coefficient structure', () {
      expect(
        () => ViperDdcParser.parseBytes(
          _float32([1.0, 1.0, 1.0, -0.5, 0.1, 0.1, 0.2]),
        ),
        throwsA(isA<String>()),
      );
    });
  });

  group('ViperDdcSheet widget', () {
    MockPlayerCubit buildCubit({
      bool enabled = false,
      String profileName = '',
    }) {
      final cubit = stubPlayerCubit(
        state: PlayerState(
          dsp: DspSlice(
            isViperDdcEnabled: enabled,
            viperDdcProfileName: profileName,
          ),
        ),
      );
      when(() => cubit.setViperDdcEnabled(
            any(),
            profileName: any(named: 'profileName'),
            coeffs: any(named: 'coeffs'),
          )).thenAnswer((_) async {});
      when(() => cubit.setViperDdcEnabled(any())).thenAnswer((_) async {});
      return cubit;
    }

    testWidgets('renders profiles, toggles and selects a profile',
        (tester) async {
      tester.view.physicalSize = const Size(900, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cubit = buildCubit();

      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const ViperDdcSheet(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ViPER-DDC'), findsOneWidget);
      expect(find.text('Sennheiser HD650 Flat Neutral'), findsOneWidget);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));

      // Enable switch.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      verify(() => cubit.setViperDdcEnabled(any())).called(1);

      // Select a built-in profile.
      await tester.tap(find.text('Sony WH-1000XM4 Clarity Lift'));
      await tester.pump();
      verify(() => cubit.setViperDdcEnabled(
            true,
            profileName: any(named: 'profileName'),
            coeffs: any(named: 'coeffs'),
          )).called(1);

      // A/B compare toggles and shows a snackbar.
      await tester.tap(find.text('A/B Compare'));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('renders the active profile name when set', (tester) async {
      final cubit = buildCubit(
        enabled: true,
        profileName: 'Sennheiser HD650 Flat Neutral',
      );
      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const ViperDdcSheet(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Active Profile'), findsOneWidget);
      // Name appears in the header card and in the profile list.
      expect(
        find.text('Sennheiser HD650 Flat Neutral'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('Active'), findsAtLeastNWidgets(1));
    });

    testWidgets('opening a VDC file reports failure when no picker exists',
        (tester) async {
      final cubit = buildCubit();
      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const ViperDdcSheet(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open .vdc'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
        'enabling A/B bypass and closing sheet restores DDC enabled state',
        (tester) async {
      final cubit = buildCubit(enabled: true);
      when(() => cubit.setViperDdcEnabled(any())).thenAnswer((_) async {});

      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const ViperDdcSheet(),
      ));
      await tester.pumpAndSettle();

      // Tap A/B Compare -> toggles bypass (disables DDC)
      await tester.tap(find.text('A/B Compare'));
      await tester.pump();
      verify(() => cubit.setViperDdcEnabled(false)).called(1);

      // Close / unmount the sheet (triggers dispose)
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      // DDC must be re-enabled via the captured PlayerCubit reference
      verify(() => cubit.setViperDdcEnabled(true)).called(1);
    });

    testWidgets(
        'P2-19 does not re-enable DDC on dispose if user explicitly disabled it or if it started disabled',
        (tester) async {
      // Case 1: DDC started enabled -> bypassed via A/B -> user explicitly turns
      // master Switch OFF -> dispose must NOT re-enable DDC.
      final controller = StreamController<PlayerState>.broadcast();
      addTearDown(controller.close);
      var current = const PlayerState(
        dsp: DspSlice(isViperDdcEnabled: true),
      );
      final cubit = stubPlayerCubit(state: current);
      when(() => cubit.state).thenAnswer((_) => current);
      when(() => cubit.stream).thenAnswer((_) => controller.stream);
      when(() => cubit.setViperDdcEnabled(any())).thenAnswer((inv) async {
        final v = inv.positionalArguments.single as bool;
        current = current.copyWith(
          dsp: current.dsp.copyWith(isViperDdcEnabled: v),
        );
        controller.add(current);
      });

      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const ViperDdcSheet(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A/B Compare'));
      await tester.pump();
      verify(() => cubit.setViperDdcEnabled(false)).called(1);

      // User explicitly flips Switch ON then OFF, taking manual ownership.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      clearInteractions(cubit);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      verifyNever(() => cubit.setViperDdcEnabled(any()));

      // Case 2: DDC started disabled -> A/B tapped -> dispose must NOT turn it on.
      final cubitOff = buildCubit(enabled: false);
      when(() => cubitOff.setViperDdcEnabled(any())).thenAnswer((_) async {});

      await tester.pumpWidget(sheetHost(
        playerCubit: cubitOff,
        child: const ViperDdcSheet(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A/B Compare'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      verifyNever(() => cubitOff.setViperDdcEnabled(true));
    });

    testWidgets(
        'P2-19 _DdcFrequencyResponsePainter.shouldRepaint returns false when biquad content is unchanged across rebuilds',
        (tester) async {
      final controller = StreamController<PlayerState>.broadcast();
      addTearDown(controller.close);
      var current = const PlayerState(
        dsp: DspSlice(
          isViperDdcEnabled: true,
          viperDdcProfileName: 'Sennheiser HD650 Flat Neutral',
        ),
      );
      final cubit = stubPlayerCubit(state: current);
      when(() => cubit.state).thenAnswer((_) => current);
      when(() => cubit.stream).thenAnswer((_) => controller.stream);

      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const ViperDdcSheet(),
      ));
      await tester.pumpAndSettle();

      final curvePaintFinder = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            '${w.painter?.runtimeType}' == '_DdcFrequencyResponsePainter',
      );
      final firstPainter =
          tester.widget<CustomPaint>(curvePaintFinder).painter!;

      // Rebuild the widget with the same profile (simulating external unrelated state / theme rebuild).
      current = current.copyWith(
        dsp: current.dsp.copyWith(isViperDdcEnabled: false),
      );
      controller.add(current);
      await tester.pump();
      await tester.pump();

      final secondPainter =
          tester.widget<CustomPaint>(curvePaintFinder).painter!;

      expect(identical(firstPainter, secondPainter), isFalse);
      expect((secondPainter as dynamic).shouldRepaint(firstPainter), isFalse);
    });

    testWidgets(
        'failed test-tone sweep start resumes main playback paused for sweep',
        (tester) async {
      final originalPathProvider = PathProviderPlatform.instance;
      final originalJustAudio = JustAudioPlatform.instance;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const audioSessionChannel = MethodChannel('com.ryanheise.audio_session');
      messenger.setMockMethodCallHandler(
          audioSessionChannel, (_) async => null);
      PathProviderPlatform.instance = _FailingPathProvider();
      JustAudioPlatform.instance = _StubJustAudioPlatform();
      addTearDown(() {
        PathProviderPlatform.instance = originalPathProvider;
        JustAudioPlatform.instance = originalJustAudio;
        messenger.setMockMethodCallHandler(audioSessionChannel, null);
      });

      final controller = StreamController<PlayerState>.broadcast();
      addTearDown(controller.close);
      var current = const PlayerState(
        playback: PlaybackSlice(isPlaying: true),
      );
      final cubit = stubPlayerCubit(state: current);
      when(() => cubit.state).thenAnswer((_) => current);
      when(() => cubit.stream).thenAnswer((_) => controller.stream);
      when(() => cubit.pause()).thenAnswer((_) async {
        current = current.copyWith(
          playback: current.playback.copyWith(isPlaying: false),
        );
        controller.add(current);
      });
      when(() => cubit.play()).thenAnswer((_) async {
        current = current.copyWith(
          playback: current.playback.copyWith(isPlaying: true),
        );
        controller.add(current);
      });

      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        child: const ViperDdcSheet(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Tone (1k+Sweep)'));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      verify(() => cubit.pause()).called(1);
      verify(() => cubit.play()).called(1);
      expect(find.text('Test Tone (1k+Sweep)'), findsOneWidget);
      expect(find.text('Stop Sweep'), findsNothing);

      // Closing the sheet after recovery must not double-call play().
      clearInteractions(cubit);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      verifyNever(() => cubit.play());
    });
  });
}
