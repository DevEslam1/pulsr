import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/ticker_gated_branch_container.dart';

/// Regression guard: hidden navigation branches must not keep animating.
/// Bare `IndexedStack` keeps every branch mounted and ticking, which is what the
/// shell used to do before `TickerGatedBranchContainer`.
void main() {
  testWidgets('only the active branch has tickers enabled', (tester) async {
    final modes = <int, bool>{};

    Widget branch(int i) => Builder(
          builder: (context) {
            modes[i] = TickerMode.valuesOf(context).enabled;
            return const SizedBox.expand();
          },
        );

    await tester.pumpWidget(
      MaterialApp(
        home: TickerGatedBranchContainer(
          currentIndex: 0,
          children: [branch(0), branch(1), branch(2)],
        ),
      ),
    );

    expect(modes, {0: true, 1: false, 2: false});

    await tester.pumpWidget(
      MaterialApp(
        home: TickerGatedBranchContainer(
          currentIndex: 2,
          children: [branch(0), branch(1), branch(2)],
        ),
      ),
    );

    expect(modes, {0: false, 1: false, 2: true});

    // The inactive branches are still mounted (state preservation).
    expect(find.byType(SizedBox), findsWidgets);
  });
}
