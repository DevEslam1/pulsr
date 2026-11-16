// test/features/player/widgets/eq_band_slider_column_test.dart
//
// `eq_band_slider_column.dart` is a `part of equalizer_sheet.dart` and its
// controls are only reachable from the Android-only branch of
// `EqualizerSheet.build` (guarded by `dart:io`'s `Platform.isAndroid`). On the
// test host that branch is never taken, so this file pins the reachable
// contract: the sheet renders without throwing and shows the platform
// fallback. See the task report for why the extension body cannot be exercised
// in a host widget test.
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('EqualizerSheet renders without throwing on the host platform',
      (tester) async {
    await tester.pumpWidget(sheetHost(
      playerCubit: stubPlayerCubit(),
      child: const EqualizerSheet(),
    ));
    await tester.pump();

    expect(find.byType(EqualizerSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'P2-21 exposes a single slider Semantics node per EQ band with working increase/decrease actions',
      (tester) async {
    EqualizerSheet.debugForceAndroidSurface = true;
    addTearDown(() => EqualizerSheet.debugForceAndroidSurface = null);

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final handle = tester.ensureSemantics();
    try {
      final cubit = stubPlayerCubit(
        state: PlayerState(
          dsp: DspSlice(
            isEqEnabled: true,
            eqPreset: EqPreset(
              name: 'Custom',
              gains: List<double>.filled(10, 0.0),
            ),
          ),
        ),
      );
      when(() => cubit.setBandGain(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(sheetHost(
        playerCubit: cubit,
        settingsCubit: stubSettingsCubit(
          state:
              const SettingsState(experienceMode: ExperienceMode.professional),
        ),
        child: const EqualizerSheet(),
      ));
      await tester.pump();

      // Count slider semantics nodes inside Band 1's control column (ancestor of
      // ValueKey('eq_band_0')'s Semantics wrapper).
      final outerSemanticsFinder = find.ancestor(
        of: find.byKey(const ValueKey('eq_band_0')),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.slider == true,
        ),
      );
      expect(outerSemanticsFinder, findsOneWidget);
      final band0Node = tester.getSemantics(outerSemanticsFinder.first);

      var sliderDescendantCount = 0;
      void countSliders(SemanticsNode node) {
        if (node.getSemanticsData().flagsCollection.isSlider) {
          sliderDescendantCount++;
        }
        node.visitChildren((child) {
          countSliders(child);
          return true;
        });
      }

      countSliders(band0Node);
      expect(
        sliderDescendantCount,
        1,
        reason: 'Band control must publish exactly one slider semantics node',
      );

      expect(
        band0Node.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      expect(
        band0Node.getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue,
      );

      // Invoke semantic increase and decrease and confirm Band 0 gain updates.
      tester.semantics.increase(find.semantics.byLabel(band0Node.label));
      await tester.pump();
      verify(() => cubit.setBandGain(0, 1.0)).called(1);

      tester.semantics.decrease(find.semantics.byLabel(band0Node.label));
      await tester.pump();
      verify(() => cubit.setBandGain(0, -1.0)).called(1);
    } finally {
      handle.dispose();
    }
  });
}
