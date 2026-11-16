import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_error_boundary.dart';

class _ThrowOnceChild extends StatelessWidget {
  final bool Function() shouldThrow;

  const _ThrowOnceChild({required this.shouldThrow});

  @override
  Widget build(BuildContext context) {
    if (shouldThrow()) {
      throw StateError('descendant boom');
    }
    return const Text('Recovered Child');
  }
}

void main() {
  testWidgets(
      'descendant child build error renders fallback, retries cleanly, and restores ErrorWidget.builder on dispose',
      (tester) async {
    final originalBuilder = ErrorWidget.builder;
    var shouldThrow = true;
    var showBoundary = true;
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            if (!showBoundary) {
              return const SizedBox.shrink();
            }
            return PulsrErrorBoundary(
              onRetry: () => shouldThrow = false,
              child: _ThrowOnceChild(shouldThrow: () => shouldThrow),
            );
          },
        ),
      ),
    );

    expect(tester.takeException(), isA<StateError>());
    await tester.pump();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Recovered Child'), findsNothing);

    await tester.tap(find.text('Try Again'));
    await tester.pump();

    expect(find.text('Recovered Child'), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);

    setHostState(() => showBoundary = false);
    await tester.pump();

    expect(identical(ErrorWidget.builder, originalBuilder), isTrue);
  });
}
