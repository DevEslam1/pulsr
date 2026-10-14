// test/core/router/safe_navigation_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pulsr/core/router/safe_navigation.dart';

void main() {
  tearDown(PulsrSafePush.resetForTesting);

  testWidgets('pushDebounced collapses duplicate pushes within its window',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('home'))),
        GoRoute(
            path: '/a', builder: (_, __) => const Scaffold(body: Text('a'))),
        GoRoute(
            path: '/b', builder: (_, __) => const Scaffold(body: Text('b'))),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    final home = tester.element(find.text('home'));
    expect(home.pushDebounced('/a'), isTrue, reason: 'first push proceeds');
    await tester.pumpAndSettle();

    final a = tester.element(find.text('a'));
    expect(a.pushDebounced('/a'), isFalse,
        reason: 'identical destination inside the window is collapsed');
    expect(a.pushDebounced('/b'), isTrue,
        reason: 'a different destination is never blocked');
    await tester.pumpAndSettle();

    final b = tester.element(find.text('b'));
    // The debounce window is wall-clock based, not fake-async based, so the
    // delay must run in the real async zone.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)));
    expect(b.pushDebounced('/b'), isTrue,
        reason: 'the same destination is allowed once the window elapses');
    await tester.pumpAndSettle();

    // Pump past the 600ms debounce timer so no fakeAsync timers remain
    await tester.pump(const Duration(milliseconds: 700));

    router.dispose();
  });

  testWidgets('pushDebounced debounces distinct Map instances with identical contents and clears extra after window',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('home'))),
        GoRoute(
            path: '/detail',
            builder: (_, state) =>
                Scaffold(body: Text('detail: ${(state.extra as Map?)?['id']}'))),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    final home = tester.element(find.text('home'));
    // First push with Map extra
    expect(
        home.pushDebounced('/detail',
            extra: {'id': 123, 'tags': ['audiophile', 'flac']}),
        isTrue);
    await tester.pumpAndSettle();

    final detail = tester.element(find.text('detail: 123'));
    // Distinct Map instance with identical contents within the debounce window
    expect(
        detail.pushDebounced('/detail',
            extra: {'id': 123, 'tags': ['audiophile', 'flac']}),
        isFalse,
        reason: 'Map with equal deep content must be debounced');

    // Wait for the window to elapse (clearing _lastExtra and timer)
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)));

    // After debounce window, the push is allowed again
    expect(
        detail.pushDebounced('/detail',
            extra: {'id': 123, 'tags': ['audiophile', 'flac']}),
        isTrue,
        reason: 'Push is allowed once debounce window expires and clears extra');
    await tester.pumpAndSettle();

    // Pump past the 600ms debounce timer so no fakeAsync timers remain
    await tester.pump(const Duration(milliseconds: 700));

    router.dispose();
  });
}
