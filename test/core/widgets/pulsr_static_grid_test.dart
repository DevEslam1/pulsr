import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/pulsr_static_grid.dart';

void main() {
  group('PulsrStaticGrid Tests', () {
    testWidgets('renders inside an unbounded vertical scrollable without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                const Text('Header'),
                PulsrStaticGrid(
                  itemCount: 6,
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.0,
                  itemBuilder: (context, index) {
                    return Container(
                      key: ValueKey('item_$index'),
                      color: Colors.blue,
                      child: Text('Item $index'),
                    );
                  },
                ),
                const Text('Footer'),
              ],
            ),
          ),
        ),
      );

      // Verify no exceptions were thrown during layout/pump
      expect(tester.takeException(), isNull);

      // Verify all items are rendered
      for (int i = 0; i < 6; i++) {
        expect(find.byKey(ValueKey('item_$i')), findsOneWidget);
      }
    });

    testWidgets('renders correctly when itemCount is 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulsrStaticGrid(
              itemCount: 0,
              crossAxisCount: 2,
              itemBuilder: (context, index) => const Text('Item'),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Item'), findsNothing);
    });

    testWidgets('respects mainAxisExtent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulsrStaticGrid(
              itemCount: 4,
              crossAxisCount: 2,
              mainAxisExtent: 80,
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Item 0'), findsOneWidget);
    });
  });
}
