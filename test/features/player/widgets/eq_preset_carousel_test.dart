// test/features/player/widgets/eq_preset_carousel_test.dart
//
// `eq_preset_carousel.dart` is a `part of equalizer_sheet.dart`; its preset
// carousel / dialog helpers are reachable on the host when
// `EqualizerSheet.debugForceAndroidSurface = true`. This file covers both the
// sheet's `show` entry point and `_resetAllDspDefaults`.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(DynamicsPreset.off);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('EqualizerSheet.show opens and dismisses a sheet route',
      (tester) async {
    await tester.pumpWidget(sheetHost(
      playerCubit: stubPlayerCubit(),
      child: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => EqualizerSheet.show(ctx),
          child: const Text('open-eq'),
        ),
      ),
    ));

    await tester.tap(find.text('open-eq'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(EqualizerSheet), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '_resetAllDspDefaults disables HRTF, multiband compressor, and dither',
      (tester) async {
    EqualizerSheet.debugForceAndroidSurface = true;
    addTearDown(() => EqualizerSheet.debugForceAndroidSurface = null);

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = stubPlayerCubit();
    when(() => cubit.resetToFlat()).thenAnswer((_) async {});
    when(() => cubit.setBassBoost(any())).thenAnswer((_) async {});
    when(() => cubit.setVolumeBoost(any())).thenAnswer((_) async {});
    when(() => cubit.setVirtualizerEnabled(any())).thenAnswer((_) async {});
    when(() => cubit.setVirtualizerStrength(any())).thenAnswer((_) async {});
    when(() => cubit.setDynamicsPreset(any())).thenAnswer((_) async {});
    when(() => cubit.setCrossfeed(any(),
        delayUs: any(named: 'delayUs'),
        feedDb: any(named: 'feedDb'))).thenAnswer((_) async {});
    when(() => cubit.setStereoBalance(any())).thenAnswer((_) async {});
    when(() => cubit.setMonoMix(any())).thenAnswer((_) async {});
    when(() => cubit.setReverb(any(),
        preset: any(named: 'preset'),
        wetDry: any(named: 'wetDry'))).thenAnswer((_) async {});
    when(() => cubit.setSaturation(any(),
        drive: any(named: 'drive'),
        mix: any(named: 'mix'),
        tilt: any(named: 'tilt'))).thenAnswer((_) async {});
    when(() => cubit.setStereoWidth(any(), width: any(named: 'width')))
        .thenAnswer((_) async {});
    when(() => cubit.setSubCrossover(any(),
        cornerHz: any(named: 'cornerHz'),
        gain: any(named: 'gain'))).thenAnswer((_) async {});
    when(() => cubit.setDynamicEq(any())).thenAnswer((_) async {});
    when(() => cubit.setLoudnessContour(any(),
        intensity: any(named: 'intensity'))).thenAnswer((_) async {});
    when(() => cubit.setDynamicBass(any(),
        strength: any(named: 'strength'),
        preset: any(named: 'preset'))).thenAnswer((_) async {});
    when(() => cubit.setViperDdcEnabled(any())).thenAnswer((_) async {});
    when(() => cubit.setArbitraryEqEnabled(any())).thenAnswer((_) async {});
    when(() => cubit.setLiveProgEnabled(any())).thenAnswer((_) async {});
    when(() => cubit.setHrtfBinaural(any(),
        azimuth: any(named: 'azimuth'),
        elevation: any(named: 'elevation'),
        sofaPath: any(named: 'sofaPath'))).thenAnswer((_) async {});
    when(() => cubit.setDither(any())).thenAnswer((_) async {});

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: const EqualizerSheet(),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.restart_alt_rounded));
    await tester.pumpAndSettle();

    verify(() => cubit.setHrtfBinaural(
          false,
          azimuth: 30.0,
          elevation: 0.0,
          sofaPath: '',
        )).called(1);
    verify(() => cubit.setMultibandCompressor(false)).called(1);
    verify(() => cubit.setDither(false)).called(1);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
