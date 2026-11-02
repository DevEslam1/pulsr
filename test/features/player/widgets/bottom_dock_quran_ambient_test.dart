import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_chrome.dart';
import 'package:pulsr/features/player/presentation/widgets/quran_mode_badge.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'player_sheet_test_support.dart';

class _FakePlayerCubit extends Fake implements PlayerCubit {
  @override
  PlayerState get state => const PlayerState(
        dsp: DspSlice(isQuranModeEnabled: true),
      );

  @override
  Stream<PlayerState> get stream => const Stream.empty();
}

class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState();

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fakePlayerCubit = _FakePlayerCubit();
  final fakeSettingsCubit = _FakeSettingsCubit();

  final dummyProps = PlayerThemeProps(
    state: const PlayerState(
      dsp: DspSlice(isQuranModeEnabled: true),
    ),
    cubit: fakePlayerCubit,
    activeColor: const Color(0xFF6750A4),
    bgColor: const Color(0xFF1C1B1F),
  );

  Widget buildSubject(Widget child) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<PlayerCubit>.value(value: fakePlayerCubit),
        BlocProvider<SettingsCubit>.value(value: fakeSettingsCubit),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: child),
        ),
      ),
    );
  }

  group('Bottom dock Quran & Ambient Sound buttons', () {
    testWidgets('renders Quran mode and Ambient sound (rain) in dock',
        (tester) async {
      await tester.pumpWidget(
        buildSubject(
          PlayerBottomActionDock(
            props: dummyProps,
            isTablet: false,
            barWidth: 350.0,
            barHeight: 54.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Quran Mode button with book icon
      expect(find.byIcon(Icons.auto_stories_rounded), findsOneWidget);

      // Ambient Sounds button with rain water drop icon
      expect(find.byIcon(Icons.water_drop_rounded), findsOneWidget);

      // Equalizer, output, speed, timer, more buttons
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.byIcon(Icons.apps_rounded), findsOneWidget);
    });

    testWidgets(
        'PlayerTrackHeader does NOT render QuranModeBadge in header chips',
        (tester) async {
      final quranProps = PlayerThemeProps(
        state: const PlayerState(
          dsp: DspSlice(isQuranModeEnabled: true),
          playback: PlaybackSlice(currentSong: testSong),
        ),
        cubit: fakePlayerCubit,
        activeColor: const Color(0xFF6750A4),
        bgColor: const Color(0xFF1C1B1F),
      );

      await tester.pumpWidget(
        buildSubject(
          PlayerTrackHeader(
            props: quranProps,
            isTablet: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // QuranModeBadge chip must NOT be present in track header
      expect(find.byType(QuranModeBadge), findsNothing);
    });
  });
}
