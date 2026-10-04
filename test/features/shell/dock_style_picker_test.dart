// test/features/shell/dock_style_picker_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/features/shell/presentation/widgets/dock_style_controller.dart';
import 'package:pulsr/features/shell/presentation/widgets/dock_style_picker_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DockStylePickerSheet', () {
    testWidgets('lists all four dock styles and reports the chosen one',
        (tester) async {
      DockStackMode? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => DockStylePickerSheet.show(
                  context,
                  current: DockStackMode.defaultLayout,
                  onSelected: (mode) => selected = mode,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The live preview banner renders the previewed style name too, so the
      // initially previewed "Side by side" appears twice (banner + option).
      expect(find.text('Side by side'), findsNWidgets(2));
      expect(find.text('Floating pill'), findsOneWidget);
      expect(find.text('Mini player in front'), findsOneWidget);
      expect(find.text('Navigation in front'), findsOneWidget);

      await tester.tap(find.text('Floating pill'));
      await tester.pumpAndSettle();

      expect(selected, DockStackMode.system);
    });

    testWidgets('dockStyleName maps every mode to a non-empty label',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          }),
        ),
      );
      for (final mode in DockStackMode.values) {
        expect(dockStyleName(ctx, mode), isNotEmpty);
      }
    });
  });

  group('DockStyleController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DockStyleController.reset();
    });

    test('set updates the notifier and persists the preference', () async {
      await DockStyleController.set(DockStackMode.miniPlayerOnTop);
      expect(DockStyleController.mode.value, DockStackMode.miniPlayerOnTop);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(PrefsKeys.dockStackMode),
        DockStackMode.miniPlayerOnTop.name,
      );
    });

    test('load restores a persisted mode', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.dockStackMode: DockStackMode.navBarOnTop.name,
      });
      DockStyleController.reset();
      await DockStyleController.load();
      expect(DockStyleController.mode.value, DockStackMode.navBarOnTop);
    });

    test('load falls back to default for an unknown value', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.dockStackMode: 'not_a_real_mode',
      });
      DockStyleController.reset();
      await DockStyleController.load();
      expect(DockStyleController.mode.value, DockStackMode.defaultLayout);
    });
  });
}
