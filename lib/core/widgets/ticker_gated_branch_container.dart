// lib/core/widgets/ticker_gated_branch_container.dart
import 'package:flutter/material.dart';

/// Keeps every navigation branch mounted (so scroll position and state survive
/// tab switches) while muting tickers and focus traversal in the branches that
/// are not visible.
///
/// `StatefulShellRoute.indexedStack` builds a bare [IndexedStack]: it paints one
/// child but leaves every animation in the hidden branches running. Wrapping
/// each child in a [TickerMode], [ExcludeFocus], and [RepaintBoundary] keyed on
/// the active index stops those tickers and isolates layer repaints without
/// disposing the branch.
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
    if (children.isEmpty) return const SizedBox.shrink();
    final safeIndex = currentIndex.clamp(0, children.length - 1);

    return IndexedStack(
      index: safeIndex,
      children: [
        for (var i = 0; i < children.length; i++)
          TickerMode(
            enabled: i == safeIndex,
            child: ExcludeFocus(
              excluding: i != safeIndex,
              child: RepaintBoundary(
                child: children[i],
              ),
            ),
          ),
      ],
    );
  }
}
