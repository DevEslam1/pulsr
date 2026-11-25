import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';
import 'package:pulsr/features/player/presentation/widgets/exclusive_usb_chip.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';

class _MockUsbExclusiveService extends Mock implements UsbExclusiveService {}

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  group('ExclusiveUsbChip P2-18', () {
    testWidgets(
        'guards slow polls against overlapping calls, times out hung channel, and disposes safely mid-flight',
        (tester) async {
      final service = _MockUsbExclusiveService();
      final statusController = StreamController<UsbExclusiveStatus>.broadcast();
      addTearDown(statusController.close);

      const activeStatus = UsbExclusiveStatus(
        attached: true,
        permitted: true,
        streamingActive: true,
      );
      when(() => service.lastStatus).thenReturn(activeStatus);
      when(() => service.statusStream)
          .thenAnswer((_) => statusController.stream);

      var diagCalls = 0;
      final stuckCompleter = Completer<Map<String, dynamic>>();
      when(() => service.getDiagnostics()).thenAnswer((_) {
        diagCalls++;
        if (diagCalls == 1) {
          // Simulates a permanently hung platform call on the first poll.
          return stuckCompleter.future;
        }
        return Future<Map<String, dynamic>>.value(const {
          'isStreamActive': true,
          'underrunCount': 4,
        });
      });

      await tester.pumpWidget(host(ExclusiveUsbChip(service: service)));
      await tester.pump();
      expect(diagCalls, 1);

      // Duplicate status emission while poll 1 is pending must NOT stack a
      // second overlapping platform call.
      statusController.add(const UsbExclusiveStatus(
        attached: true,
        permitted: true,
        streamingActive: true,
      ));
      await tester.pump();
      expect(diagCalls, 1);

      // Wait past per-call timeout (900ms) + first 1s timer tick so polling recovers.
      await tester.pump(const Duration(seconds: 1));
      expect(diagCalls, 2);
      expect(find.textContaining('4'), findsOneWidget);

      stuckCompleter
          .complete(const {'isStreamActive': true, 'underrunCount': 0});
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
