// test/features/quran_mode/presentation/quran_mode_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/earbud_optimization_service.dart';
import 'package:pulsr/core/widgets/pulsr_switch.dart';
import 'package:pulsr/domain/models/quran_mode_profile.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/presentation/widgets/quran_mode_sheet.dart';
import 'package:pulsr/features/quran_mode/presentation/quran_mode_screen.dart';

import '../../../helpers/screen_harness.dart';

const _caps = EarbudCapabilities(
  deviceName: 'Sony XM5',
  codec: EarbudCodec.ldac,
  isBluetooth: true,
  isLeAudio: false,
  isUsbDac: false,
  sampleRateHz: 96000,
  bitDepth: 24,
  latencyMs: 180,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(QuranReciterStyle.murattal);
  });

  testWidgets('renders the full-screen Quran Mode surface and forwards toggles',
      (tester) async {
    final cubit = stubPlayerCubit();
    when(() => cubit.detectEarbudCapabilities())
        .thenAnswer((_) async => _caps);
    when(() => cubit.setQuranModeEnabled(any())).thenAnswer((_) async {});
    when(() => cubit.setQuranReciterStyle(any())).thenAnswer((_) async {});
    when(() => cubit.setQuranAmbience(any())).thenAnswer((_) async {});
    when(() => cubit.setQuranWarmth(any())).thenAnswer((_) async {});
    when(() => cubit.setPlaybackSpeed(any())).thenAnswer((_) async {});
    when(() => cubit.reapplyQuranProfile()).thenAnswer((_) async {});

    await tester.pumpWidget(screenHarness(
      child: const QuranModeScreen(),
      providers: [BlocProvider<PlayerCubit>.value(value: cubit)],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(QuranModeScreen), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(QuranModePanel), findsOneWidget);

    await tester.tap(find.byType(PulsrSwitch).first);
    await tester.pump();
    verify(() => cubit.setQuranModeEnabled(true)).called(1);
  });
}
