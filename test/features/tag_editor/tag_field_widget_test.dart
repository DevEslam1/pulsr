// test/features/tag_editor/tag_field_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/tag_editor/tag_field_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('adopts external model changes (undo / auto-fill)', (tester) async {
    var modelValue = 'initial';

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  TagFieldWidget(
                    label: 'Title',
                    initialValue: modelValue,
                    onChanged: (v) => modelValue = v,
                  ),
                  TextButton(
                    onPressed: () => setState(() => modelValue = 'model-updated'),
                    child: const Text('update'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(find.widgetWithText(TextFormField, 'initial'), findsOneWidget);

    await tester.tap(find.text('update'));
    await tester.pump();

    // The controller must reflect the new model value, not the stale one.
    expect(find.widgetWithText(TextFormField, 'model-updated'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'initial'), findsNothing);

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, 'model-updated');
    expect(
      editable.controller.selection.baseOffset,
      'model-updated'.length,
      reason: 'caret should be pinned to the end after an external update',
    );
  });

  testWidgets('typing emits onChanged and is not clobbered by a rebuild',
      (tester) async {
    var modelValue = '';
    final changes = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return TagFieldWidget(
                label: 'Artist',
                initialValue: modelValue,
                onChanged: (v) {
                  changes.add(v);
                  setState(() => modelValue = v);
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'Hello');
    await tester.pump();

    expect(changes, isNotEmpty);
    expect(changes.last, 'Hello');
    expect(modelValue, 'Hello');
    // The typed text survives the rebuild triggered by onChanged.
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, 'Hello');
  });
}
