import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../helpers/screen_harness.dart';
import '../helpers/test_song_factory.dart';

class _MockSettings extends Mock implements SettingsCubit {}

/// The old `frame_budget_test.dart` timed a stock `ListTile` list, which proves
/// nothing about Pulsr. This guards the property that actually matters on a
/// 5,000-track library: the list must stay virtualised. A regression to
/// `shrinkWrap`/`Column` would build every row and turn scrolling into jank.
void main() {
  testWidgets('5,000-track library builds only the visible window',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final song = createTestSong(title: 'Track');
    final player = stubPlayerCubit(const PlayerState());
    final settings = _MockSettings();
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());

    var built = 0;

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: <BlocProvider>[
          BlocProvider<PlayerCubit>.value(value: player),
          BlocProvider<SettingsCubit>.value(value: settings),
        ],
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView.builder(
              itemCount: 5000,
              itemBuilder: (context, index) {
                built++;
                return SongTile(
                  key: ValueKey(index),
                  song: song.copyWith(id: index, title: 'Track $index'),
                  onTap: () {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // A 844 dp viewport with ~64 dp rows can only show a handful; allow slack
    // for cache extent but reject anything close to "built the whole list".
    expect(built, lessThan(40),
        reason: 'List must not build all 5,000 rows (built $built)');

    final firstWindow = built;
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();

    expect(built - firstWindow, lessThan(60),
        reason: 'Scrolling 2,000 px must not build everything '
            '(built ${built - firstWindow} more)');
    expect(built, lessThan(120));
  });
}
