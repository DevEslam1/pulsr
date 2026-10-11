// test/core/responsive/nav_mode_alignment_test.dart
//
// PulsrViewport.navMode and PulsrLayoutDelegate.resolveMode must agree on the
// same geometry. An 844x390 landscape phone used to yield sideRailExtended
// from the viewport token while the shell rendered a wide bottom bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/breakpoints.dart';
import 'package:pulsr/core/responsive/layout_delegate.dart';
import 'package:pulsr/core/responsive/pulsr_responsive_tokens.dart';

void main() {
  testWidgets('844x390 landscape phone agrees on bottom navigation',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late PulsrViewport viewport;
    late PulsrLayoutDelegate delegate;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          viewport = PulsrViewport.fromContext(context);
          delegate = PulsrLayoutDelegate.of(context);
          return const SizedBox.shrink();
        },
      ),
    ));

    expect(viewport.width, 844);
    expect(viewport.height, 390);
    expect(viewport.sizeClass, PulsrBreakpoint.expanded);
    expect(viewport.isShortHeight, isTrue);

    expect(delegate.layoutMode, ShellLayoutMode.bottomNavWide);
    expect(viewport.navMode, PulsrNavMode.bottomBar);
    // Agreement: neither token claims a side rail for this geometry.
    expect(delegate.showRail, isFalse);
    expect(viewport.navMode, isNot(PulsrNavMode.sideRail));
    expect(viewport.navMode, isNot(PulsrNavMode.sideRailExtended));
  });

  testWidgets('tall landscape tablet still gets an extended side rail',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late PulsrViewport viewport;
    late PulsrLayoutDelegate delegate;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          viewport = PulsrViewport.fromContext(context);
          delegate = PulsrLayoutDelegate.of(context);
          return const SizedBox.shrink();
        },
      ),
    ));

    expect(viewport.isShortHeight, isFalse);
    expect(delegate.showRail, isTrue);
    expect(delegate.railExpanded, isTrue);
    expect(viewport.navMode, PulsrNavMode.sideRailExtended);
  });
}
