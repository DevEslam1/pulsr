// test/features/player/player_controls_overflow_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/advanced_playback_bar.dart';
import 'package:pulsr/features/player/presentation/widgets/player_controls.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    mockSettingsCubit = MockSettingsCubit();

    when(() => mockPlayerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          isPlaying: true,
          abLoopEnabled: true,
          abPointA: Duration(seconds: 10),
          abPointB: Duration(seconds: 25),
          trackDelayMs: 250,
        ),
      ),
    );
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsState(
        experienceMode: ExperienceMode.professional,
      ),
    );
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream.empty());
  });

  Widget createSubject({required Widget child, required double width}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
            BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
          ],
          child: Center(
            child: SizedBox(
              width: width,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'AdvancedPlaybackBar does not overflow in 187.2px constrained column',
      (tester) async {
    await tester.pumpWidget(
      createSubject(
        width: 187.2,
        child: const AdvancedPlaybackBar(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify no RenderFlex overflow exception occurred
    expect(tester.takeException(), isNull);
    expect(find.byType(AdvancedPlaybackBar), findsOneWidget);
  });

  testWidgets('PlayerControls does not overflow in 187.2px constrained column',
      (tester) async {
    await tester.pumpWidget(
      createSubject(
        width: 187.2,
        child: PlayerControls(
          isPlaying: true,
          isShuffle: true,
          repeatMode: PlayerRepeatMode.all,
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onToggleShuffle: () {},
          onToggleRepeat: () {},
          primaryColor: Colors.blue,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify no RenderFlex overflow exception occurred
    expect(tester.takeException(), isNull);
    expect(find.byType(PlayerControls), findsOneWidget);
  });
}
