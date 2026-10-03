// test/core/widgets/async_state_builder_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/async_state_builder.dart';
import 'package:pulsr/core/widgets/pulsr_empty_state.dart';
import 'package:pulsr/core/widgets/shimmer_skeleton.dart';

Widget _harness(Widget child) => MaterialApp(
      theme: AuraTheme.darkTheme,
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: child,
        ),
      ),
    );

void main() {
  group('AsyncStateBuilder', () {
    testWidgets('shows the default skeleton while waiting', (tester) async {
      await tester.pumpWidget(
        _harness(
          AsyncStateBuilder<List<String>>(
            snapshot: const AsyncSnapshot<List<String>>.waiting(),
            onData: (data) => Text('count ${data.length}'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonList), findsOneWidget);
    });

    testWidgets('shows the default retry card on error and invokes onRetry',
        (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _harness(
          AsyncStateBuilder<List<String>>(
            snapshot: AsyncSnapshot<List<String>>.withError(
              ConnectionState.done,
              Exception('boom'),
            ),
            onData: (data) => Text('count ${data.length}'),
            onRetry: () => retries++,
          ),
        ),
      );

      expect(find.byType(PulsrEmptyState), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('shows the empty state when data is null', (tester) async {
      await tester.pumpWidget(
        _harness(
          AsyncStateBuilder<List<String>?>(
            snapshot: const AsyncSnapshot<List<String>?>.withData(
                ConnectionState.done, null),
            onData: (data) => Text('count ${data?.length ?? 0}'),
          ),
        ),
      );

      expect(find.byType(PulsrEmptyState), findsOneWidget);
      expect(find.text('No music found'), findsOneWidget);
    });

    testWidgets('shows the empty state when isEmpty matches', (tester) async {
      await tester.pumpWidget(
        _harness(
          AsyncStateBuilder<List<String>>(
            snapshot: const AsyncSnapshot<List<String>>.withData(
                ConnectionState.done, <String>[]),
            isEmpty: (data) => data.isEmpty,
            onData: (data) => Text('count ${data.length}'),
          ),
        ),
      );

      expect(find.byType(PulsrEmptyState), findsOneWidget);
    });

    testWidgets('renders onData for successful data', (tester) async {
      await tester.pumpWidget(
        _harness(
          AsyncStateBuilder<List<String>>(
            snapshot: const AsyncSnapshot<List<String>>.withData(
                ConnectionState.done, <String>['a', 'b']),
            onData: (data) => Text('count ${data.length}'),
          ),
        ),
      );

      expect(find.text('count 2'), findsOneWidget);
      expect(find.byType(PulsrEmptyState), findsNothing);
    });

    testWidgets('honours custom loading, error and empty overrides',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          AsyncStateBuilder<List<String>>(
            snapshot: const AsyncSnapshot<List<String>>.waiting(),
            loadingWidget: const Text('custom loading'),
            onData: (data) => const Text('data'),
          ),
        ),
      );
      expect(find.text('custom loading'), findsOneWidget);

      await tester.pumpWidget(
        _harness(
          AsyncStateBuilder<List<String>>(
            snapshot: AsyncSnapshot<List<String>>.withError(
              ConnectionState.done,
              Exception('boom'),
            ),
            onError: (error) => Text('custom error: $error'),
            onData: (data) => const Text('data'),
          ),
        ),
      );
      expect(find.textContaining('custom error'), findsOneWidget);

      await tester.pumpWidget(
        _harness(
          AsyncStateBuilder<List<String>?>(
            snapshot: const AsyncSnapshot<List<String>?>.withData(
                ConnectionState.done, null),
            emptyWidget: const Text('custom empty'),
            onData: (data) => const Text('data'),
          ),
        ),
      );
      expect(find.text('custom empty'), findsOneWidget);
    });
  });
}
