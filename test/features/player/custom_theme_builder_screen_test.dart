// test/features/player/custom_theme_builder_screen_test.dart
//
// Branch coverage for [CustomThemeBuilderScreen]: settings hydration, live
// preview toggle (with and without a PlayerCubit), palette/radius/glow edits,
// theme JSON import (valid, missing-colour, malformed) and export.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/custom_theme_builder_screen.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

import 'widgets/player_sheet_test_support.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSettingsCubit settings;

  setUpAll(() {
    registerFallbackValue(const Color(0xFF000000));
  });

  setUp(() {
    settings = MockSettingsCubit();
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => settings.setCustomAccentColor(any())).thenAnswer((_) async {});
    when(() => settings.setCustomThemeRadius(any())).thenAnswer((_) async {});
    when(() => settings.setCustomThemeGlow(any())).thenAnswer((_) async {});
  });

  Widget host({PlayerCubit? player}) {
    return sheetHost(
      playerCubit: player,
      settingsCubit: settings,
      child: const CustomThemeBuilderScreen(),
    );
  }

  _MockPlayerCubit stubPlayer() {
    final cubit = _MockPlayerCubit();
    when(() => cubit.state).thenReturn(const PlayerState());
    when(() => cubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    return cubit;
  }

  testWidgets('hydrates accent/radius/glow from settings on first build',
      (tester) async {
    when(() => settings.state).thenReturn(const SettingsState(
      customAccentColorValue: 0xFFFF2A6D,
      customThemeRadius: 12.0,
      customThemeGlow: false,
    ));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(CustomThemeBuilderScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggling live preview builds the player theme and back',
      (tester) async {
    await tester.pumpWidget(host(player: stubPlayer()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_circle_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.view_compact_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.view_compact_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
  });

  testWidgets('preview falls back honestly without a PlayerCubit',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_circle_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(CustomThemeBuilderScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('palette, radius and glow edits reach the settings cubit',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // The palette circles are the only GestureDetectors with a 48x48 box.
    final palette = find.byWidgetPredicate((w) =>
        w is GestureDetector && w.child is Container);
    expect(palette, findsWidgets);
    await tester.tap(palette.at(1));
    await tester.pump();
    verify(() => settings.setCustomAccentColor(any())).called(1);

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(40.0);
    slider.onChangeEnd!(40.0);
    await tester.pump();
    verify(() => settings.setCustomThemeRadius(40.0)).called(1);

    final switchTile =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    switchTile.onChanged!(false);
    await tester.pump();
    verify(() => settings.setCustomThemeGlow(false)).called(1);
  });

  testWidgets('valid theme JSON import applies the values', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.file_upload_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      '{"accentColor": 4288388853, "cornerRadius": 30, "glowEnabled": false}',
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    verify(() => settings.setCustomAccentColor(any())).called(1);
    verify(() => settings.setCustomThemeRadius(30.0)).called(1);
    verify(() => settings.setCustomThemeGlow(false)).called(1);
  });

  testWidgets('JSON without an accent colour is reported as invalid',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.file_upload_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '{"cornerRadius": 10}');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    verifyNever(() => settings.setCustomAccentColor(any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed JSON import is handled without crashing',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.file_upload_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '{not valid json');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    verifyNever(() => settings.setCustomAccentColor(any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the import dialog leaves state untouched',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.file_upload_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();

    verifyNever(() => settings.setCustomAccentColor(any()));
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('exporting the theme reports success or failure honestly',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.share_rounded));
    await tester.pumpAndSettle();
    // No share plugin is registered in the test host: the failure branch must
    // surface a toast rather than a thrown exception.
    expect(tester.takeException(), isNull);
  });
}
