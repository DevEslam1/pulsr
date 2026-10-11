// test/core/widgets/entity_by_id_loader_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/widgets/entity_by_id_loader.dart';

void main() {
  testWidgets('re-subscribes and replaces the entity when callbacks change',
      (tester) async {
    final first = Completer<Result<String?>>();
    final second = Completer<Result<String?>>();
    var useSecond = false;

    Widget build() => MaterialApp(
          home: EntityByIdLoader<String>(
            fetchSingle: () => useSecond ? second.future : first.future,
            builder: (context, item) => Scaffold(body: Text('Entity: $item')),
            notFoundMessage: 'Not found',
          ),
        );

    await tester.pumpWidget(build());
    expect(find.text('Not found'), findsNothing);

    // Simulate a reused State being pointed at a different id.
    useSecond = true;
    await tester.pumpWidget(build());

    // Both futures settle: the stale first result must be discarded.
    first.complete(const Right('A'));
    second.complete(const Right('B'));
    await tester.pump();

    expect(find.text('Entity: B'), findsOneWidget);
    expect(find.text('Entity: A'), findsNothing);

    // Flush the skeleton shimmer's delayed timers before teardown.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('an unchanged callback does not restart the fetch',
      (tester) async {
    var calls = 0;
    final completer = Completer<Result<String?>>();
    Future<Result<String?>> fetch() {
      calls++;
      return completer.future;
    }

    Widget build() => MaterialApp(
          home: EntityByIdLoader<String>(
            fetchSingle: fetch,
            builder: (context, item) => Scaffold(body: Text('Entity: $item')),
            notFoundMessage: 'Not found',
          ),
        );

    await tester.pumpWidget(build());
    expect(calls, 1);

    // Rebuild with the same callback identity: no resubscribe.
    await tester.pumpWidget(build());
    expect(calls, 1);

    completer.complete(const Right('A'));
    await tester.pump();
    expect(find.text('Entity: A'), findsOneWidget);

    // Flush the skeleton shimmer's delayed timers before teardown.
    await tester.pump(const Duration(seconds: 1));
  });
}
