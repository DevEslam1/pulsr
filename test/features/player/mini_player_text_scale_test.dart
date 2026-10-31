import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/mini_player.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _MockSettings extends Mock implements SettingsCubit {}

/// WCAG 1.4.4: the mini player used to clamp text at 1.3×, so a 200 % OS setting
/// left the most-used surface at 130 %. It now scales fully — this guards the
/// fixed-height chrome against overflow while it does.
void main() {
  testWidgets('mini player renders at 200% text without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = PlayerState(
      playback: PlaybackSlice(
        currentSong: createTestSong(
          title: 'A Very Long Track Title That Must Wrap Or Ellipsize',
          artist: 'An Equally Long Artist Name Collective',
        ),
        isPlaying: true,
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 4),
      ),
    );
    final player = stubPlayerCubit(state);
    final settings = _MockSettings();
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: <BlocProvider>[
          BlocProvider<PlayerCubit>.value(value: player),
          BlocProvider<SettingsCubit>.value(value: settings),
        ],
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            theme: AuraTheme.darkTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: MiniPlayer(onTap: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byType(MiniPlayer), findsOneWidget);
  });
}
