// Presentational clock-architecture selector: domain labelling, disabled
// options, streaming lock and the callback contract.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';
import 'package:pulsr/features/usb_tools/usb_stream_mode.dart';
import 'package:pulsr/features/usb_tools/usb_stream_mode_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  UsbExclusiveStatus status({
    bool streaming = true,
    bool feedback = true,
    UsbClockDomain domain = UsbClockDomain.bitPerfectLocked,
    int underruns = 0,
  }) =>
      UsbExclusiveStatus(
        attached: true,
        permitted: true,
        vendorId: 0x1234,
        productId: 0x5678,
        streamingActive: streaming,
        streamingSampleRate: 96000,
        streamingBitDepth: 24,
        streamingChannels: 2,
        clockDomain: domain,
        clockDriftPpm: -12,
        ringFillMs: 2400,
        feedbackPresent: feedback,
        underrunCount: underruns,
        overrunCount: 0,
      );

  Future<void> pump(
    WidgetTester tester, {
    required UsbExclusiveStatus usb,
    required UsbStreamMode selected,
    bool pull = true,
    bool asrc = true,
    bool streamingActive = true,
    ValueChanged<UsbStreamMode>? onChanged,
  }) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: UsbStreamModeSelector(
              status: usb,
              selected: selected,
              pullFlagEnabled: pull,
              asrcFlagEnabled: asrc,
              streamingActive: streamingActive,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the verified domain and measured evidence', (tester) async {
    await pump(
      tester,
      usb: status(),
      selected: UsbStreamMode.bitPerfectPull,
    );
    expect(find.text(UsbStreamModeStrings.title), findsOneWidget);
    expect(find.text('Bit-perfect'), findsOneWidget);
    expect(find.textContaining('Drift -12 ppm'), findsOneWidget);
    expect(find.textContaining('Buffer 2400 ms'), findsOneWidget);
    expect(find.textContaining('Underruns 0'), findsOneWidget);
  });

  testWidgets('ASRC option is disabled without a feedback endpoint',
      (tester) async {
    await pump(
      tester,
      usb: status(feedback: false),
      selected: UsbStreamMode.bestEffort,
      streamingActive: false,
      onChanged: (_) {},
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('usb-stream-mode-dropdown')),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(UsbStreamModeStrings.feedbackRequired),
      findsOneWidget,
    );
  });

  testWidgets('streaming locks the selector and explains why', (tester) async {
    await pump(
      tester,
      usb: status(),
      selected: UsbStreamMode.bitPerfectPull,
      streamingActive: true,
      onChanged: (_) {},
    );
    expect(find.text(UsbStreamModeStrings.streamingLocked), findsOneWidget);
    final dropdown = tester.widget<DropdownButtonFormField<UsbStreamMode>>(
      find.byKey(const ValueKey<String>('usb-stream-mode-dropdown')),
    );
    expect(dropdown.onChanged, isNull);
  });

  testWidgets('idle selection emits the new mode', (tester) async {
    UsbStreamMode? selected;
    await pump(
      tester,
      usb: status(streaming: false, domain: UsbClockDomain.unknown),
      selected: UsbStreamMode.bitPerfectPull,
      streamingActive: false,
      onChanged: (mode) => selected = mode,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('usb-stream-mode-dropdown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(UsbStreamModeStrings.bestEffort).last);
    await tester.pumpAndSettle();
    expect(selected, UsbStreamMode.bestEffort);
  });
}
