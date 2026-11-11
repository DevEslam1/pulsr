import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/ambient_sound_service.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/player_more_sheet.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}
class MockSettingsCubit extends Mock implements SettingsCubit {}
class MockAmbientSoundService extends Mock implements AmbientSoundService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockPlayerCubit playerCubit;
  late MockSettingsCubit settingsCubit;
  late MockAmbientSoundService ambientService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    playerCubit = MockPlayerCubit();
    settingsCubit = MockSettingsCubit();
    ambientService = MockAmbientSoundService();

    when(() => playerCubit.state).thenReturn(const PlayerState());
    when(() => playerCubit.stream).thenAnswer((_) => const Stream.empty());

    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());

    when(() => ambientService.isEnabled).thenReturn(true);
    when(() => ambientService.activeEffects).thenReturn(<AmbientSoundEffect>{});
    when(() => ambientService.isAudioPlaying).thenReturn(true);
    AmbientSoundService.testInstance = ambientService;
  });

  tearDown(() {
    AmbientSoundService.testInstance = null;
  });

  testWidgets('0.1 PlayerMoreSheet does not throw when ambient is enabled with zero active effects', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: playerCubit),
              BlocProvider<SettingsCubit>.value(value: settingsCubit),
            ],
            child: const PlayerMoreSheet(
              song: null,
              activeColor: Colors.cyan,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(PlayerMoreSheet), findsOneWidget);
    // Should render fallback waves icon instead of throwing
    expect(find.byIcon(Icons.waves_rounded), findsOneWidget);
  });
}
