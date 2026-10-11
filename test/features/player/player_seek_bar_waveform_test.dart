// test/features/player/player_seek_bar_waveform_test.dart
//
// Covers the debounced waveform decode: rapid song changes must not start a
// decode per track, and a decode that completes after its song was replaced
// must never be applied to the new song.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/player_seek_bar.dart';
import 'package:pulsr/features/player/presentation/widgets/waveform_seek_bar.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'player_test_support.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit cubit;
  late MockSettingsCubit settings;
  final completers = <int, Completer<List<double>>>{};
  final loaderCalls = <int>[];

  setUp(() {
    loaderCalls.clear();
    completers.clear();
    PlayerSeekBar.waveformLoaderOverride = (songId, filePath) {
      loaderCalls.add(songId);
      return (completers[songId] ??= Completer<List<double>>()).future;
    };

    cubit = MockPlayerCubit();
    settings = MockSettingsCubit();
    when(() => cubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => cubit.state).thenReturn(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: buildSong(42),
          isPlaying: true,
          duration: const Duration(minutes: 3),
          position: const Duration(seconds: 30),
        ),
      ),
    );
    when(() => settings.state)
        .thenReturn(const SettingsState(waveformSeekBarEnabled: true));
  });

  tearDown(() {
    PlayerSeekBar.waveformLoaderOverride = null;
  });

  Widget host({required int songId, required String filePath}) {
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
              duration: const Duration(minutes: 3),
              songId: songId,
              filePath: filePath,
              onSeek: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('rapid song changes debounce the decode to the settled song',
      (tester) async {
    await tester.pumpWidget(host(songId: 42, filePath: '/music/a.flac'));
    await tester.pump();

    // Switch before the debounce window elapses: song 42 must never decode.
    await tester.pumpWidget(host(songId: 43, filePath: '/music/b.flac'));
    await tester.pump(const Duration(milliseconds: 20));
    expect(loaderCalls, isNot(contains(42)));

    await tester.pump(const Duration(milliseconds: 200));
    expect(loaderCalls, contains(43));

    completers[43]!.complete(List<double>.filled(8, 0.77));
    await tester.pumpAndSettle();

    final waveform =
        tester.widget<WaveformSeekBar>(find.byType(WaveformSeekBar));
    expect(waveform.samples.length, 8);
    expect(waveform.samples, everyElement(0.77));
  });

  testWidgets(
      'a late decode from the previous song cannot apply to the new one',
      (tester) async {
    await tester.pumpWidget(host(songId: 42, filePath: '/music/a.flac'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(completers[42], isNotNull);

    await tester.pumpWidget(host(songId: 43, filePath: '/music/b.flac'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(completers[43], isNotNull);
    // The old decode lands late: it must be dropped, not painted.
    completers[42]!.complete(List<double>.filled(8, 0.11));
    await tester.pumpAndSettle();
    var waveform = tester.widget<WaveformSeekBar>(find.byType(WaveformSeekBar));
    expect(waveform.samples.length, isNot(8));

    // Only the settled song's decode is applied.
    completers[43]!.complete(List<double>.filled(8, 0.88));
    await tester.pumpAndSettle();
    waveform = tester.widget<WaveformSeekBar>(find.byType(WaveformSeekBar));
    expect(waveform.samples.length, 8);
    expect(waveform.samples, everyElement(0.88));
  });
}
