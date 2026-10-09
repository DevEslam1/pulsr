// Covers lib/features/settings/presentation/widgets/experience_mode_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/experience_mode_section.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/settings_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    stubSettingsChannels();
  });
  tearDown(clearSettingsChannels);

  Future<SettingsCubit> pumpSection(
    WidgetTester tester, {
    ExperienceMode mode = ExperienceMode.normal,
    Size size = const Size(420, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final cubit = SettingsCubit(scannerService: MockMediaScannerService());
    await cubit.setExperienceMode(mode);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: cubit,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: ExperienceModeSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    return cubit;
  }

  testWidgets('renders normal-mode copy and tags the normal badge',
      (tester) async {
    await pumpSection(tester);

    expect(find.text(l10n.experienceModeSubtitle), findsOneWidget);
    expect(find.text(l10n.experienceModeNormal), findsWidgets);
    expect(find.text(l10n.experienceModeProfessional), findsOneWidget);
    expect(find.text(l10n.experienceModeNormalDesc), findsOneWidget);
    expect(find.text('NORMAL'), findsOneWidget);
    expect(find.text(l10n.whatChanges), findsOneWidget);
  });

  testWidgets('switching to professional updates copy, badge and cubit state',
      (tester) async {
    final cubit = await pumpSection(tester);

    await tester.tap(find.text(l10n.experienceModeProfessional).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(cubit.state.experienceMode, ExperienceMode.professional);
    expect(find.text(l10n.experienceModeProfessionalDesc), findsOneWidget);
    expect(find.text('PRO'), findsOneWidget);
    expect(find.text(l10n.settingsDspInspectorDesc), findsOneWidget);

    // Drain the professional-mode toast auto-dismiss timer.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('renders professional copy when seeded in professional mode',
      (tester) async {
    await pumpSection(tester, mode: ExperienceMode.professional);

    expect(find.text(l10n.experienceModeProfessionalDesc), findsOneWidget);
    expect(find.text('PRO'), findsOneWidget);
    expect(find.text(l10n.experienceModeNormalDesc), findsNothing);
  });

  testWidgets('what-changes expander toggles open and closed', (tester) async {
    await pumpSection(tester);

    expect(find.textContaining(l10n.expEqTitle, findRichText: true), findsNothing);

    await tester.tap(find.text(l10n.whatChanges));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining(l10n.expEqTitle, findRichText: true), findsOneWidget);
    expect(find.textContaining(l10n.expEqNormal, findRichText: true), findsOneWidget);

    await tester.tap(find.text(l10n.whatChanges));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining(l10n.expEqTitle, findRichText: true), findsNothing);
  });

  testWidgets('mode switch collapses an expanded what-changes panel',
      (tester) async {
    final cubit = await pumpSection(tester);

    await tester.tap(find.text(l10n.whatChanges));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining(l10n.expGainTitle, findRichText: true), findsOneWidget);

    cubit.safeEmit(cubit.state.copyWith(
      experienceMode: ExperienceMode.professional,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // didUpdateWidget collapsed the panel when the mode changed.
    expect(find.textContaining(l10n.expGainTitle, findRichText: true), findsNothing);
  });
}
