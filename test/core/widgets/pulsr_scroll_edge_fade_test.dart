import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/pulsr_scroll_edge_fade.dart';

void main() {
  testWidgets('disabled fade returns the child without a shader mask',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PulsrScrollEdgeFade(
        enabled: false,
        child: Text('content'),
      ),
    ));
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('enabled fade masks the trailing edge', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 200,
        child: PulsrScrollEdgeFade(
          child: Text('a long horizontal strip of content'),
        ),
      ),
    ));
    expect(find.byType(ShaderMask), findsOneWidget);
  });
}
