// lib/core/widgets/ticker_gated_branch_container.dart
import 'package:flutter/material.dart';

/// Keeps every navigation branch mounted (so scroll position and state survive
/// tab switches) while muting tickers in the branches that are not visible.
///
/// `StatefulShellRoute.indexedStack` builds a bare [IndexedStack]: it paints one
/// child but leaves every animation in the hidden branches running. Wrapping
/// each child in a [TickerMode] keyed on the active index stops those tickers
/// without disposing the branch.
class TickerGatedBranchContainer extends StatelessWidget {
  const TickerGatedBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: currentIndex,
      children: [
        for (var i = 0; i < children.length; i++)
          TickerMode(enabled: i == currentIndex, child: children[i]),
      ],
    );
  }
}
