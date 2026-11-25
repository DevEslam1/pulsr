// test/features/usb_tools/usb_quirk_editor_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/usb_tools/usb_ergonomics_strings.dart';
import 'package:pulsr/features/usb_tools/usb_quirk_editor.dart';
import 'package:pulsr/features/usb_tools/usb_quirk_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpEditor(
    WidgetTester tester, {
    required UsbQuirkProfile profile,
    required ValueChanged<UsbQuirkProfile> onChanged,
    bool enabled = true,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
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
            child: UsbQuirkEditor(
              profile: profile,
              onChanged: onChanged,
              enabled: enabled,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders all fields including volumeCalibrationDb',
      (tester) async {
    await pumpEditor(
      tester,
      profile: UsbQuirkProfile.defaults,
      onChanged: (_) {},
    );

    expect(find.text(UsbErgonomicsStrings.audioSectionTitle), findsOneWidget);
    expect(find.text(UsbErgonomicsStrings.silenceLabel), findsOneWidget);
    expect(find.text(UsbErgonomicsStrings.bufferLabel), findsOneWidget);
    expect(find.text(UsbErgonomicsStrings.transferSizeLabel), findsOneWidget);
    expect(find.text(UsbErgonomicsStrings.selectorPinLabel), findsOneWidget);
    expect(
        find.text(UsbErgonomicsStrings.volumeCalibrationLabel), findsOneWidget);
  });

  testWidgets('valid volumeCalibrationDb emits updated profile',
      (tester) async {
    UsbQuirkProfile current = UsbQuirkProfile.defaults;
    await pumpEditor(
      tester,
      profile: current,
      onChanged: (p) => current = p,
    );

    final calibField = find.widgetWithText(
      TextField,
      UsbErgonomicsStrings.volumeCalibrationLabel,
    );
    expect(calibField, findsOneWidget);

    await tester.enterText(calibField, '-6.5');
    await tester.pump();

    expect(current.volumeCalibrationDb, -6.5);
    expect(find.text(UsbErgonomicsStrings.numberInvalid), findsNothing);
  });

  testWidgets('out of range volumeCalibrationDb displays error',
      (tester) async {
    UsbQuirkProfile current = UsbQuirkProfile.defaults;
    await pumpEditor(
      tester,
      profile: current,
      onChanged: (p) => current = p,
    );

    final calibField = find.widgetWithText(
      TextField,
      UsbErgonomicsStrings.volumeCalibrationLabel,
    );
    await tester.enterText(calibField, '30.0');
    await tester.pump();

    expect(find.text(UsbErgonomicsStrings.numberInvalid), findsOneWidget);
    expect(current.volumeCalibrationDb, 0.0); // Not updated
  });

  testWidgets(
      'external profile update syncs TextEditingController in didUpdateWidget',
      (tester) async {
    UsbQuirkProfile current = UsbQuirkProfile.defaults;
    await pumpEditor(
      tester,
      profile: current,
      onChanged: (p) => current = p,
    );

    final calibField = find.widgetWithText(
      TextField,
      UsbErgonomicsStrings.volumeCalibrationLabel,
    );
    expect(tester.widget<TextField>(calibField).controller!.text, '');

    // Pump with new profile
    await pumpEditor(
      tester,
      profile: current.copyWith(volumeCalibrationDb: 4.5),
      onChanged: (p) => current = p,
    );

    expect(tester.widget<TextField>(calibField).controller!.text, '4.5');
  });
}
