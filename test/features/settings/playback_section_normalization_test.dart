import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/widgets/pulsr_switch.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/playback_section.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSettingsCubit extends Mock implements SettingsCubit {}
class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSettingsCubit mockSettingsCubit;
  late MockPlayerCubit mockPlayerCubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.audioNormalizationEnabled: false,
    });
    mockSettingsCubit = MockSettingsCubit();
    mockPlayerCubit = MockPlayerCubit();

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayerCubit.state).thenReturn(const PlayerState());
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget buildWidget({required SettingsState settingsState}) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
        BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlaybackSection(state: settingsState),
          ),
        ),
      ),
    );
  }

  testWidgets('M-18: _buildNormal in PlaybackSection includes _AudioNormalizationSettingTile', (tester) async {
    // Normal mode (isProfessional == false)
    const normalState = SettingsState(experienceMode: ExperienceMode.normal);

    await tester.pumpWidget(buildWidget(settingsState: normalState));
    await tester.pumpAndSettle();

    // Verify Audio Normalization tile is rendered in _buildNormal
    final titleFinder = find.text('Audio normalization');
    final subtitleFinder = find.text('Even out loudness for tracks without ReplayGain tags');

    expect(titleFinder, findsOneWidget);
    expect(subtitleFinder, findsOneWidget);

    // Verify switch is present and initial state is off (false)
    final switchFinder = find.byType(PulsrSwitch);
    expect(switchFinder, findsWidgets);

    // Scroll until visible and tap the normalization switch
    await tester.scrollUntilVisible(titleFinder, 200);
    await tester.pumpAndSettle();
    await tester.tap(titleFinder);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.audioNormalizationEnabled), isTrue);
  });

  testWidgets('M-18: _buildProfessional also contains audio normalization tile', (tester) async {
    // Professional mode (isProfessional == true)
    const proState = SettingsState(experienceMode: ExperienceMode.professional);

    await tester.pumpWidget(buildWidget(settingsState: proState));
    await tester.pumpAndSettle();

    final titleFinder = find.text('Audio normalization');
    expect(titleFinder, findsOneWidget);
  });
}
