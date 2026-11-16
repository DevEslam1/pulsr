// test/features/player/widgets/sync_diagnostics_sheet_test.dart
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/sync_diagnostics_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockDiagnostics({
    int frames = 0,
    double appliedRate = 48000.0,
    double usbBufferedMs = 0.0,
    Map<String, dynamic> usbDiagnostics = const {},
  }) {
    messenger.setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      (call) async {
        switch (call.method) {
          case 'getPipelineLatencyFrames':
            return frames;
          case 'getAppliedSampleRate':
            return appliedRate;
          default:
            return null;
        }
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.usbExclusive),
      (call) async {
        switch (call.method) {
          case 'getBufferedMs':
            return usbBufferedMs;
          case 'getDiagnostics':
            return usbDiagnostics;
          default:
            return null;
        }
      },
    );
  }

  setUp(() => mockDiagnostics());

  tearDown(() {
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.usbExclusive), null);
  });

  Widget host(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  group('SyncDiagnosticsSheet', () {
    testWidgets('renders the non-USB pipeline latency tile', (tester) async {
      await tester.pumpWidget(
        host(const SyncDiagnosticsSheet(sampleRate: 48000.0)),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(SyncDiagnosticsSheet), findsOneWidget);
      expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
      expect(find.text('0.00 ms'), findsWidgets);
      // No USB tile when the stream is inactive.
      expect(find.byIcon(Icons.usb_rounded), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('shows the USB buffered tile when the stream is active',
        (tester) async {
      mockDiagnostics(
        frames: 480,
        appliedRate: 96000.0,
        usbBufferedMs: 12.5,
        usbDiagnostics: const {
          'isStreamActive': true,
          'underrunCount': 3,
          'overrunCount': 1,
        },
      );

      await tester.pumpWidget(
        host(const SyncDiagnosticsSheet(sampleRate: 48000.0)),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.usb_rounded), findsOneWidget);
      expect(find.text('5.00 ms'), findsOneWidget);
      expect(find.text('17.50 ms'), findsOneWidget);
      expect(find.text('Underruns: 3 | Overruns: 1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('falls back to 48 kHz when the sample rate is invalid',
        (tester) async {
      await tester.pumpWidget(
        host(const SyncDiagnosticsSheet(sampleRate: 0)),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('frames @ 48.0 kHz'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('pauses polling while backgrounded and resumes on resume',
        (tester) async {
      await tester.pumpWidget(
        host(const SyncDiagnosticsSheet(sampleRate: 48000.0)),
      );
      await tester.pump(const Duration(milliseconds: 50));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(SyncDiagnosticsSheet), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets(
        'P2-18 serializes slow diagnostic polls with in-flight guard and timeout',
        (tester) async {
      var latencyCallCount = 0;
      Completer<int>? slowCall;
      messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects),
        (call) async {
          switch (call.method) {
            case 'getPipelineLatencyFrames':
              latencyCallCount++;
              if (latencyCallCount == 1) {
                slowCall = Completer<int>();
                return slowCall!.future;
              }
              return 256;
            case 'getAppliedSampleRate':
              return 48000.0;
            default:
              return null;
          }
        },
      );

      await tester.pumpWidget(
        host(const SyncDiagnosticsSheet(sampleRate: 48000.0)),
      );
      await tester.pump();
      expect(latencyCallCount, 1);

      // While call 1 is pending, a resume lifecycle trigger must NOT launch an
      // overlapping channel call (in-flight guard).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(latencyCallCount, 1);

      // Call 1 never completes (hung platform call); the per-call timeout must
      // release the in-flight guard so the next 1s tick recovers with call 2.
      await tester.pump(const Duration(seconds: 2));
      expect(latencyCallCount, greaterThanOrEqualTo(2));
      expect(find.textContaining('256 frames'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
