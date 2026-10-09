// Covers lib/features/settings/presentation/widgets/device_profiles_section.dart
//
// Exercises the load/empty/populated states, the auto-switch toggle, per-device
// link assignment + apply + forget, custom profile creation/deletion, and the
// reload error path.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/hires_audio_service.dart';
import 'package:pulsr/core/services/settings_profiles_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/device_profiles_section.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_hi_res_audio_service.dart';
import 'support/settings_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockPlayerCubit player;
  late FakeHiResAudioService hires;

  setUpAll(() {
    registerFallbackValue(const SettingsProfile(
      id: 'fallback',
      name: 'Fallback',
      type: ProfileType.custom,
    ));
  });

  setUp(() async {
    stubSettingsChannels();
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => player.applyProfile(any(), manual: any(named: 'manual')))
        .thenAnswer((_) async => true);
    hires = FakeHiResAudioService();
    getIt.registerSingleton<SettingsProfilesService>(SettingsProfilesService());
    getIt.registerSingleton<HiResAudioService>(hires);
  });

  tearDown(() async {
    clearSettingsChannels();
    await getIt.reset();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      BlocProvider<PlayerCubit>.value(
        value: player,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: DeviceProfilesSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  }

  void seedProfilesAndDevices() {
    SharedPreferences.setMockInitialValues({
      'setting_device_registry': jsonEncode([
        {'deviceKey': 'bluetooth:kitchen', 'deviceLabel': 'Kitchen'},
        {'deviceKey': 'usb:dac', 'deviceLabel': 'USB DAC'},
      ]),
      'setting_device_profile_links': jsonEncode({
        'bluetooth:kitchen': {
          'deviceKey': 'bluetooth:kitchen',
          'profileId': 'profile_custom_1',
          'deviceLabel': 'Kitchen',
        },
      }),
      'setting_custom_profiles': jsonEncode([
        {
          'id': 'profile_home',
          'name': 'Home Audiophile',
          'type': 'home',
          'eqPresetName': 'Flat',
        },
        {
          'id': 'profile_custom_1',
          'name': 'My Custom',
          'type': 'custom',
          'eqPresetName': 'Bass Boost',
          'volumeBoost': 0.2,
        },
      ]),
    });
  }

  testWidgets('empty registry shows the auto-switch and no-devices hint',
      (tester) async {
    await pumpSection(tester);

    expect(find.text(l10n.autoDeviceSwitch), findsOneWidget);
    expect(find.text(l10n.noDevicesSeen), findsOneWidget);
    expect(find.text(l10n.profileCreateFromCurrent), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
  });

  testWidgets('renders devices, the current-device badge and profiles',
      (tester) async {
    seedProfilesAndDevices();
    hires.stubbedInfo = const AudioOutputInfo(
      deviceName: 'Kitchen',
      isUsbDac: false,
      sampleRate: 48000,
      bitDepth: 16,
      isBitPerfectActive: false,
      activeDeviceType: 'bluetooth',
      isBluetooth: true,
    );

    await pumpSection(tester);

    expect(find.text('Kitchen'), findsWidgets);
    expect(find.text('USB DAC'), findsOneWidget);
    expect(find.text(l10n.currentDeviceBadge), findsOneWidget);
    expect(find.text('My Custom'), findsWidgets);
    expect(find.text('Home Audiophile'), findsOneWidget);
    // Built-in profile has no delete affordance; the custom one does.
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('toggling auto-switch persists the preference',
      (tester) async {
    await pumpSection(tester);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('setting_auto_device_profiles_enabled'), isFalse);
  });

  testWidgets('applying a linked profile forwards to the player cubit',
      (tester) async {
    seedProfilesAndDevices();
    await pumpSection(tester);

    final applyButton = find.byIcon(Icons.play_circle_outline_rounded);
    expect(applyButton, findsWidgets);
    await tester.tap(applyButton.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    verify(() => player.applyProfile(any(), manual: true)).called(1);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('forgetting a link removes it and disables the actions',
      (tester) async {
    seedProfilesAndDevices();
    await pumpSection(tester);

    await tester.tap(find.byIcon(Icons.link_off_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final prefs = await SharedPreferences.getInstance();
    final links = jsonDecode(prefs.getString('setting_device_profile_links')!)
        as Map<String, dynamic>;
    expect(links.containsKey('bluetooth:kitchen'), isFalse);
  });

  testWidgets('assigning a profile through the dropdown stores the link',
      (tester) async {
    seedProfilesAndDevices();
    await pumpSection(tester);

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home Audiophile').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final prefs = await SharedPreferences.getInstance();
    final links = jsonDecode(prefs.getString('setting_device_profile_links')!)
        as Map<String, dynamic>;
    expect(links['bluetooth:kitchen']['profileId'], 'profile_home');
  });

  testWidgets('creating a profile from the current settings adds a row',
      (tester) async {
    await pumpSection(tester);

    await tester.tap(find.text(l10n.profileCreateFromCurrent));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Road Trip');
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    expect(find.text('Road Trip'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('setting_custom_profiles'), contains('Road Trip'));

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an empty profile name is ignored', (tester) async {
    await pumpSection(tester);

    await tester.tap(find.text(l10n.profileCreateFromCurrent));
    await tester.pumpAndSettle();

    // Save with no text does not pop / create.
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    // Still only the default profile set is returned by the service.
    expect(prefs.getString('setting_custom_profiles'), isNull);
  });

  testWidgets('deleting a custom profile confirms then removes it',
      (tester) async {
    seedProfilesAndDevices();
    await pumpSection(tester);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(Dialog),
      matching: find.text(l10n.delete),
    ));
    await tester.pumpAndSettle();

    expect(find.text('My Custom'), findsNothing);
  });

  testWidgets('a reload failure falls back to the empty-but-usable state',
      (tester) async {
    await getIt.reset();
    await pumpSection(tester);

    expect(find.text(l10n.autoDeviceSwitch), findsOneWidget);
    expect(find.text(l10n.noDevicesSeen), findsOneWidget);
  });
}
