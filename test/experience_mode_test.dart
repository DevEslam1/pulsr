// test/experience_mode_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/audio_sound_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMediaScannerService mockScanner;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // SettingsCubit eagerly constructs HiResAudioService which probes the
    // hires_dac channel; stub it so no timer dangles past teardown.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.hiresDac),
      (call) async => null,
    );
    mockScanner = MockMediaScannerService();
  });

  group('Experience mode persistence', () {
    test('defaults to Normal', () async {
      final cubit = SettingsCubit(scannerService: mockScanner);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.experienceMode, ExperienceMode.normal);
      expect(cubit.state.isProfessional, isFalse);
    });

    test('setExperienceMode professional persists and reloads', () async {
      final cubit = SettingsCubit(scannerService: mockScanner);
      addTearDown(cubit.close);

      await cubit.setExperienceMode(ExperienceMode.professional);
      expect(cubit.state.isProfessional, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PrefsKeys.experienceMode), 'professional');

      // A fresh cubit (as after a restart) reads the persisted value.
      final reloaded = SettingsCubit(scannerService: mockScanner);
      addTearDown(reloaded.close);
      await reloaded.reloadSettings();
      expect(reloaded.state.experienceMode, ExperienceMode.professional);
    });
  });

  group('AudioSoundSection respects experience mode', () {
    Widget harness(SettingsState state) {
      final cubit = SettingsCubit(scannerService: mockScanner);
      addTearDown(cubit.close);
      final playerCubit = MockPlayerCubit();
      when(() => playerCubit.state).thenReturn(const PlayerState());
      when(() => playerCubit.stream).thenAnswer((_) => const Stream.empty());
      return BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: BlocProvider<PlayerCubit>.value(
          value: playerCubit,
          child: MaterialApp(
            theme: AuraTheme.darkTheme,
            home: Scaffold(
              body: ListView(children: [AudioSoundSection(state: state)]),
            ),
          ),
        ),
      );
    }

    testWidgets('Normal mode hides advanced output controls', (tester) async {
      await tester.pumpWidget(harness(const SettingsState()));
      await tester.pump();

      expect(find.text('Output & Audio Quality'), findsOneWidget);
      expect(find.text('Room Correction'), findsNothing);
      expect(find.text('Bit-Perfect USB Pass-Through'), findsNothing);
      expect(find.text('DSP Signal Inspector & Debug'), findsNothing);
    });

    testWidgets('Professional mode reveals advanced output controls',
        (tester) async {
      await tester.pumpWidget(harness(
          const SettingsState(experienceMode: ExperienceMode.professional)));
      await tester.pump();

      expect(find.text('Room Correction'), findsOneWidget);
      expect(find.text('Bit-Perfect USB Pass-Through'), findsOneWidget);
    });
  });
}
