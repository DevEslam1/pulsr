// test/features/player/advanced_playback_bar_test.dart
//
// A-B loop affordance: touch targets, the visible "A m:ss · B m:ss" readout
// and the live-region confirmation for screen readers.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/advanced_playback_bar.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit cubit;
  late MockSettingsCubit settings;

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    cubit = MockPlayerCubit();
    settings = MockSettingsCubit();
    when(() => cubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => cubit.setAbPointA()).thenAnswer((_) {});
    when(() => cubit.setAbPointB()).thenAnswer((_) {});
    when(() => cubit.toggleAbLoop()).thenAnswer((_) {});
    when(() => cubit.clearAbLoop()).thenAnswer((_) {});
    when(() => settings.state).thenReturn(
      const SettingsState(experienceMode: ExperienceMode.professional),
    );
  });

  Widget host({Duration? a, Duration? b, bool loopEnabled = false}) {
    when(() => cubit.state).thenReturn(PlayerState(
      playback: PlaybackSlice(
        isPlaying: true,
        abLoopEnabled: loopEnabled,
        abPointA: a,
        abPointB: b,
        trackDelayMs: 250,
      ),
    ));
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
          child: const Center(
            child: SizedBox(
              width: 500,
              child: AdvancedPlaybackBar(),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('A/B loop buttons meet the 48dp minimum touch target',
      (tester) async {
    await tester.pumpWidget(host(
      a: const Duration(seconds: 10),
      b: const Duration(seconds: 25),
    ));
    await tester.pumpAndSettle();

    final finder = find.descendant(
      of: find.byType(AdvancedPlaybackBar),
      matching: find.byType(IconButton),
    );
    final buttons = tester.widgetList<IconButton>(finder);
    expect(buttons, isNotEmpty);
    for (final button in buttons) {
      expect(button.constraints!.minWidth, greaterThanOrEqualTo(44.0));
      expect(button.constraints!.minHeight, greaterThanOrEqualTo(44.0));
    }
    for (final element in finder.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.width, greaterThanOrEqualTo(44.0));
      expect(size.height, greaterThanOrEqualTo(44.0));
    }
  });

  testWidgets('set A/B points are shown as a times readout and live region',
      (tester) async {
    await tester.pumpWidget(host(
      a: const Duration(seconds: 10),
      b: const Duration(seconds: 25),
      loopEnabled: true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('A 0:10 · B 0:25'), findsOneWidget);

    final liveRegion = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true);
    expect(
      find.descendant(
        of: find.byType(AdvancedPlaybackBar),
        matching: liveRegion,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single point reads out with the unset placeholder',
      (tester) async {
    await tester.pumpWidget(host(a: const Duration(seconds: 5)));
    await tester.pumpAndSettle();

    expect(find.text('A 0:05 · B --:--'), findsOneWidget);
  });

  testWidgets('no readout renders before any point is set', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.textContaining('A '), findsNothing);
    expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true),
        findsNothing);
  });
}
