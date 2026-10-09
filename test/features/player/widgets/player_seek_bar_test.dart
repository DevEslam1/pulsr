// Coverage for the uncovered branches of player_seek_bar.dart.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/player_seek_bar.dart';
import 'package:pulsr/features/player/presentation/widgets/waveform_seek_bar.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../player_test_support.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  late MockPlayerCubit cubit;
  late MockSettingsCubit settings;
  late AppLocalizations l10n;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    cubit = MockPlayerCubit();
    settings = MockSettingsCubit();
    when(() => cubit.stream).thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => cubit.toggleQueueVisibility()).thenAnswer((_) {});
  });

  Widget host({
    required PlayerState playerState,
    required SettingsState settingsState,
    Duration? position,
    Duration duration = const Duration(minutes: 3),
    bool showUpNext = true,
    int? songId,
    String? filePath,
    ValueChanged<Duration>? onSeek,
  }) {
    when(() => cubit.state).thenReturn(playerState);
    when(() => settings.state).thenReturn(settingsState);
    return MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<PlayerCubit>.value(value: cubit),
            BlocProvider<SettingsCubit>.value(value: settings),
          ],
          child: SizedBox(
            width: 420,
            height: 320,
            child: PlayerSeekBar(
              position: position,
              duration: duration,
              onSeek: onSeek ?? (_) {},
              songId: songId,
              filePath: filePath,
              showUpNext: showUpNext,
            ),
          ),
        ),
      ),
    );
  }

  PlayerState stateWith({
    int? currentId,
    List<int> queueIds = const [],
    int currentIndex = 0,
  }) {
    final queue = queueIds.map(buildSong).toList();
    return PlayerState(
      playback: PlaybackSlice(
        currentSong: currentId == null ? null : buildSong(currentId),
        isPlaying: true,
        duration: const Duration(minutes: 3),
        position: const Duration(seconds: 30),
      ),
      queueSlice: QueueSlice(queue: queue, currentIndex: currentIndex),
    );
  }

  testWidgets('renders the standard slider with timestamps', (tester) async {
    await tester.pumpWidget(host(
      playerState: stateWith(currentId: 1),
      settingsState: const SettingsState(waveformSeekBarEnabled: false),
      position: const Duration(seconds: 30),
    ));
    await tester.pump();

    expect(find.byType(PulsrSlider), findsOneWidget);
    expect(find.byType(WaveformSeekBar), findsNothing);
    expect(find.text('0:30'), findsOneWidget);
    expect(find.text('3:00'), findsOneWidget);
  });

  testWidgets('tapping the slider forwards a seek to the callback',
      (tester) async {
    Duration? seeked;
    await tester.pumpWidget(host(
      playerState: stateWith(currentId: 1),
      settingsState: const SettingsState(waveformSeekBarEnabled: false),
      position: const Duration(seconds: 30),
      onSeek: (d) => seeked = d,
    ));
    await tester.pump();

    final slider = find.byType(PulsrSlider);
    await tester.tapAt(tester.getCenter(slider));
    await tester.pump();

    expect(seeked, isNotNull);
    // Tapping the middle seeks to roughly half the duration.
    expect(seeked!.inSeconds, greaterThan(60));
  });

  testWidgets('dragging the slider forwards a seek to the callback',
      (tester) async {
    Duration? seeked;
    await tester.pumpWidget(host(
      playerState: stateWith(currentId: 1),
      settingsState: const SettingsState(waveformSeekBarEnabled: false),
      position: const Duration(seconds: 30),
      onSeek: (d) => seeked = d,
    ));
    await tester.pump();

    await tester.drag(find.byType(PulsrSlider), const Offset(120, 0));
    await tester.pump();

    expect(seeked, isNotNull);
  });

  testWidgets('renders the up-next strip and toggles the queue on tap',
      (tester) async {
    await tester.pumpWidget(host(
      playerState: stateWith(currentId: 1, queueIds: [1, 2]),
      settingsState: const SettingsState(waveformSeekBarEnabled: false),
    ));
    await tester.pump();

    expect(find.text(l10n.upNext), findsOneWidget);
    expect(find.textContaining('Song 2'), findsOneWidget);

    await tester.tap(find.text(l10n.upNext));
    await tester.pump();

    verify(() => cubit.toggleQueueVisibility()).called(1);
  });

  testWidgets('hides the up-next strip when disabled', (tester) async {
    await tester.pumpWidget(host(
      playerState: stateWith(currentId: 1, queueIds: [1, 2]),
      settingsState: const SettingsState(waveformSeekBarEnabled: false),
      showUpNext: false,
    ));
    await tester.pump();

    expect(find.text(l10n.upNext), findsNothing);
  });

  testWidgets('hides the up-next strip on the last queue item',
      (tester) async {
    await tester.pumpWidget(host(
      playerState: stateWith(currentId: 2, queueIds: [1, 2], currentIndex: 1),
      settingsState: const SettingsState(waveformSeekBarEnabled: false),
    ));
    await tester.pump();

    expect(find.text(l10n.upNext), findsNothing);
  });

  testWidgets('renders the waveform seek bar when enabled with a song',
      (tester) async {
    await tester.pumpWidget(host(
      playerState: stateWith(currentId: 1),
      settingsState: const SettingsState(waveformSeekBarEnabled: true),
      position: const Duration(seconds: 30),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(WaveformSeekBar), findsOneWidget);
  });

  testWidgets('falls back to the standard slider when no song id is known',
      (tester) async {
    await tester.pumpWidget(host(
      playerState: const PlayerState(),
      settingsState: const SettingsState(waveformSeekBarEnabled: true),
      position: const Duration(seconds: 30),
    ));
    await tester.pump();

    expect(find.byType(PulsrSlider), findsOneWidget);
    expect(find.byType(WaveformSeekBar), findsNothing);
  });

  testWidgets('shows the crossfade badge when crossfade is active',
      (tester) async {
    await tester.pumpWidget(host(
      playerState: stateWith(currentId: 1),
      settingsState:
          const SettingsState(waveformSeekBarEnabled: false, crossfadeSeconds: 5),
      position: const Duration(seconds: 30),
      duration: const Duration(minutes: 3),
    ));
    await tester.pump();

    expect(find.textContaining('5s'), findsOneWidget);
  });

  testWidgets('uses the explicitly provided position over the cubit position',
      (tester) async {
    await tester.pumpWidget(host(
      playerState: stateWith(currentId: 1),
      settingsState: const SettingsState(waveformSeekBarEnabled: false),
      position: const Duration(seconds: 75),
    ));
    await tester.pump();

    // 75s formatted into the timestamp row.
    expect(find.textContaining('1:15'), findsOneWidget);
  });
}
