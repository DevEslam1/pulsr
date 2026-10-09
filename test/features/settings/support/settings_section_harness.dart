// Shared harness for exercising the SettingsScreen category sections.
//
// The section mixins (appearance/online/library/gestures/privacy) are private to
// the `settings_screen.dart` library, so their builders can only be reached by
// pumping a real [SettingsScreen] with the target category pre-selected. This
// file centralises the provider/palette/l10n/channel setup the existing settings
// tests use so each section test stays small.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';
import 'package:pulsr/features/auth/cubit/auth_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/settings_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockAuthCubit extends Mock implements AuthCubit {}

/// Stubs the native channels [SettingsCubit] probes while constructing
/// [HiResAudioService], so no 3s timeout timer dangles into teardown.
void stubSettingsChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel(PulsrChannels.hiresDac),
    (call) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel(PulsrChannels.audioEffects),
    (call) async {
      if (call.method == 'setSystemEffectsPolicy') {
        return <String, dynamic>{
          'status': 'unsupportedDevice',
          'detectedBundles': <String>[],
        };
      }
      return null;
    },
  );
}

void clearSettingsChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.hiresDac), null);
  messenger.setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects), null);
}

class SettingsSectionHarness {
  final SettingsCubit cubit;
  final MockMediaScannerService scanner;
  final MockPlayerCubit player;
  final MockAuthCubit auth;

  SettingsSectionHarness({
    required this.cubit,
    required this.scanner,
    required this.player,
    required this.auth,
  });
}

/// Pumps a real [SettingsScreen] forced onto [category] via the persisted
/// category preference, wired with a real [SettingsCubit] (plus mocked player
/// and auth cubits the shell reads).
///
/// Uses fixed pumps instead of `pumpAndSettle` because the search field's
/// `EditableText`/`InputDecorator` tickers stay warm and never settle (an
/// ambient framework animation, not an app bug).
Future<SettingsSectionHarness> pumpSettingsCategory(
  WidgetTester tester, {
  required String category,
  SettingsState? seedState,
  Map<String, Object> extraPrefs = const {},
  Size size = const Size(420, 3200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  SharedPreferences.setMockInitialValues({
    'settings_last_selected_category': category,
    ...extraPrefs,
  });
  SettingsScreenController.resetSessionCategory();

  final scanner = MockMediaScannerService();
  when(() => scanner.scanProgress)
      .thenAnswer((_) => const Stream<double>.empty());

  final player = MockPlayerCubit();
  when(() => player.state).thenReturn(const PlayerState());
  when(() => player.stream).thenAnswer((_) => const Stream.empty());

  final auth = MockAuthCubit();
  when(() => auth.state).thenReturn(const AuthState());
  when(() => auth.stream).thenAnswer((_) => const Stream.empty());

  final cubit = SettingsCubit(scannerService: scanner);

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: cubit),
        BlocProvider<PlayerCubit>.value(value: player),
        BlocProvider<AuthCubit>.value(value: auth),
      ],
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  if (seedState != null) {
    cubit.safeEmit(seedState);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  return SettingsSectionHarness(
    cubit: cubit,
    scanner: scanner,
    player: player,
    auth: auth,
  );
}
