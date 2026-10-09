// test/features/player/widgets/dsp_inspector_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/dsp_inspector_sheet.dart';

import 'player_sheet_test_support.dart';

Map<String, dynamic> debugStatus({
  int audioSessionId = 101,
  bool attached = true,
  bool bitPerfect = false,
  bool nativeLoaded = true,
  int stagesMask = 1,
  bool hasOem = false,
  List<String> activeEffects = const ['EQ'],
  List<Map<String, dynamic>>? stages,
}) {
  return {
    'audioSessionId': audioSessionId,
    'isSessionAttached': attached,
    'dspPreference': 'native',
    'isBitPerfectBypassActive': bitPerfect,
    'isNativeDspLoaded': nativeLoaded,
    'activeDspStagesMask': stagesMask,
    'autoDegradedStagesMask': 0,
    'hasOemAudio': hasOem,
    'detectedOemEngines': const ['Dolby'],
    'activeEffectNames': activeEffects,
    'detectedEngines': const ['Dolby'],
    'stages': stages ??
        [
          {
            'name': 'Parametric EQ',
            'category': 'C++ Native',
            'isSupported': true,
            'isEnabled': true,
            'isBypassed': false,
            'isDegraded': false,
            'parameters': const <String, dynamic>{},
            'statusDescription': 'Applying 5 bands',
          },
          {
            'name': 'Limiter',
            'category': 'C++ Native',
            'isSupported': true,
            'isEnabled': true,
            'isBypassed': true,
            'isDegraded': false,
            'parameters': const <String, dynamic>{},
            'statusDescription': 'Bypassed',
          },
          {
            'name': 'Reverb',
            'category': 'C++ Native',
            'isSupported': true,
            'isEnabled': true,
            'isBypassed': false,
            'isDegraded': true,
            'parameters': const <String, dynamic>{},
            'statusDescription': 'Degraded',
          },
          {
            'name': 'Dynamics',
            'category': 'Android HAL',
            'isSupported': false,
            'isEnabled': false,
            'isBypassed': false,
            'isDegraded': false,
            'parameters': const <String, dynamic>{},
            'statusDescription': 'Unavailable',
          },
        ],
    'timestamp': DateTime(2026).toIso8601String(),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockChannel({
    Map<String, dynamic>? status,
    List<dynamic>? telemetry,
  }) {
    messenger.setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      (call) async {
        switch (call.method) {
          case 'getDspDebugStatus':
            return status;
          case 'getTelemetry':
            return telemetry;
          default:
            return null;
        }
      },
    );
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects), null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  PlayerState attachedState() => const PlayerState().copyWith(
        dsp: const DspSlice(
          isEqEnabled: true,
          isSaturationEnabled: true,
          isReverbEnabled: true,
          isCrossfeedEnabled: false,
        ),
        playback: const PlaybackSlice(audioSessionId: 101),
      );

  // The sheet runs a 1.5s refresh timer, so `pumpAndSettle` would never
  // settle. Advance a bounded number of frames instead.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  group('DspInspectorSheet.sanitizeReport', () {
    test('redacts app, storage and local absolute paths', () {
      const raw = 'a /data/user/0/com.pulsr/cache b '
          '/storage/emulated/0/Music c C:\\Users\\me\\file.flac d';
      final sanitized = DspInspectorSheet.sanitizeReport(raw);
      expect(sanitized, contains('[REDACTED_APP_PATH]'));
      expect(sanitized, contains('[REDACTED_STORAGE_PATH]'));
      expect(sanitized, contains('[REDACTED_LOCAL_PATH]'));
      expect(sanitized, isNot(contains('/data/user/')));
      expect(sanitized, isNot(contains('C:\\Users')));
    });
  });

  group('DspInspectorSheet', () {
    testWidgets('renders the master engine card and stage list',
        (tester) async {
      mockChannel(
        status: debugStatus(),
        telemetry: List<dynamic>.generate(17, (_) => 0.0),
      );
      final player = stubPlayerCubit(state: attachedState());
      final settings = stubSettingsCubit();

      await tester.pumpWidget(sheetHost(
        playerCubit: player,
        settingsCubit: settings,
        child: const DspInspectorSheet(),
      ));
      await settle(tester);

      expect(find.byType(DspInspectorSheet), findsOneWidget);
      expect(find.text('Parametric EQ'), findsOneWidget);
      expect(find.text('Limiter'), findsOneWidget);
      expect(find.text('Reverb'), findsOneWidget);

      // Copy to clipboard triggers a snackbar.
      await tester.tap(find.byIcon(Icons.copy_rounded));
      await settle(tester);
      expect(find.byType(SnackBar), findsOneWidget);

      // Refresh re-fetches the report.
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await settle(tester);

      // Let the snackbar's auto-dismiss timer elapse before disposal.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('shows the OEM-hijack remediation and switches preference',
        (tester) async {
      mockChannel(
        status: debugStatus(
          attached: false,
          hasOem: true,
          activeEffects: const [],
        ),
        telemetry: List<dynamic>.generate(17, (_) => 0.0),
      );
      final player = stubPlayerCubit(state: attachedState());
      final settings = stubSettingsCubit();
      when(() => settings.setDspPreference(any())).thenAnswer((_) async {});

      await tester.pumpWidget(sheetHost(
        playerCubit: player,
        settingsCubit: settings,
        child: const DspInspectorSheet(),
      ));
      await settle(tester);

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await settle(tester);
      verify(() => settings.setDspPreference('oem')).called(1);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('shows the pending-session retry when no session is attached',
        (tester) async {
      mockChannel(
        status: debugStatus(
          audioSessionId: 0,
          attached: false,
          activeEffects: const ['EQ'],
        ),
        telemetry: List<dynamic>.generate(17, (_) => 0.0),
      );
      final player = stubPlayerCubit(state: attachedState());
      final settings = stubSettingsCubit();

      await tester.pumpWidget(sheetHost(
        playerCubit: player,
        settingsCubit: settings,
        child: const DspInspectorSheet(),
      ));
      await settle(tester);

      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      await tester.tap(find.byType(OutlinedButton));
      await settle(tester);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}