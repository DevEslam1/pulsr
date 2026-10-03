// test/core/widgets/pulsr_dismissible_gestures_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/pulsr_dismissible.dart';

Widget _tile(String label, {double width = double.infinity}) => SizedBox(
      width: width,
      height: 64,
      child: Center(child: Text(label)),
    );

Widget _background(String label, {bool isEnd = false}) => Container(
      alignment: isEnd ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.red,
      child: Text(label),
    );

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

Future<void> _openStartToEnd(WidgetTester tester, {double by = 220}) async {
  await tester.drag(find.byType(PulsrDismissible), Offset(by, 0));
  await tester.pumpAndSettle();
}

Future<void> _openEndToStart(WidgetTester tester, {double by = 220}) async {
  await tester.drag(find.byType(PulsrDismissible), Offset(-by, 0));
  await tester.pumpAndSettle();
}

Future<void> _flushConfirmTimer(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 4000));
  await tester.pumpAndSettle();
}

void main() {
  group('static configuration', () {
    test('thresholds and defaults match the two-swipe contract', () {
      expect(PulsrDismissible.defaultThreshold, 0.60);
      expect(PulsrDismissible.thresholds[DismissDirection.startToEnd], 0.60);
      expect(PulsrDismissible.thresholds[DismissDirection.endToStart], 0.60);
      expect(PulsrDismissible.direction, DismissDirection.horizontal);
    });

    testWidgets('wrap wires labels and confirm through', (tester) async {
      DismissDirection? confirmed;
      final widget = PulsrDismissible.wrap(
        key: const ValueKey('wrapped'),
        child: _tile('Wrapped tile'),
        background: _background('Archive'),
        secondaryBackground: _background('Delete', isEnd: true),
        startToEndLabel: 'Archive',
        endToStartLabel: 'Delete',
        confirm: (direction) async {
          confirmed = direction;
          return false;
        },
      );

      await tester.pumpWidget(_app(widget));
      expect(find.text('Wrapped tile'), findsOneWidget);

      await _openStartToEnd(tester);
      await tester.drag(find.byType(PulsrDismissible), const Offset(100, 0));
      await tester.pumpAndSettle();

      expect(confirmed, DismissDirection.startToEnd);
      await _flushConfirmTimer(tester);
    });

    testWidgets('buildActionBackground changes label and icon when confirming',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                PulsrDismissible.buildActionBackground(
                  context: context,
                  icon: Icons.archive_rounded,
                  label: 'Archive',
                  color: Colors.white,
                  backgroundColor: Colors.red,
                  isConfirming: false,
                ),
                PulsrDismissible.buildActionBackground(
                  context: context,
                  icon: Icons.archive_rounded,
                  label: 'Archive',
                  color: Colors.white,
                  backgroundColor: Colors.red,
                  isConfirming: true,
                ),
                PulsrDismissible.buildActionBackground(
                  context: context,
                  icon: Icons.delete_rounded,
                  label: 'Delete',
                  color: Colors.white,
                  backgroundColor: Colors.red,
                  isConfirming: false,
                  isEnd: true,
                  margin: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ),
      ));

      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Confirm Archive'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.byIcon(Icons.delete_rounded), findsOneWidget);
    });
  });

  group('disabled / missing backgrounds', () {
    testWidgets('no gesture detector is installed without backgrounds',
        (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(_app(PulsrDismissible(
        onConfirm: (_) {
          confirmed++;
          return true;
        },
        child: _tile('Plain'),
      )));

      await tester.drag(find.byType(PulsrDismissible), const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(confirmed, 0);
      expect(find.text('Plain'), findsOneWidget);
    });

    testWidgets('start-to-end only ignores negative drags', (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(_app(PulsrDismissible(
        dismissDirection: DismissDirection.startToEnd,
        background: _background('Archive'),
        onConfirm: (_) {
          confirmed++;
          return true;
        },
        child: _tile('One way'),
      )));

      await tester.drag(find.byType(PulsrDismissible), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(confirmed, 0);
      expect(find.text('Archive'), findsNothing);

      await _openStartToEnd(tester);
      expect(find.text('Archive'), findsOneWidget);
      await _flushConfirmTimer(tester);
    });

    testWidgets('end-to-start only ignores positive drags', (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        dismissDirection: DismissDirection.endToStart,
        secondaryBackground: _background('Delete', isEnd: true),
        onConfirm: (_) => true,
        child: _tile('Other way'),
      )));

      await tester.drag(find.byType(PulsrDismissible), const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);

      await _openEndToStart(tester);
      expect(find.text('Delete'), findsOneWidget);
      await _flushConfirmTimer(tester);
    });
  });

  group('first swipe reveal', () {
    testWidgets('dragging past the threshold reveals the action',
        (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        backgroundBuilder: (context, isConfirming) =>
            _background(isConfirming ? 'Confirm Archive' : 'Archive'),
        onConfirm: (_) => true,
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester);

      expect(find.text('Confirm Archive'), findsOneWidget);
      final transform = tester.widget<Transform>(find
          .ancestor(
            of: find.text('Swipe me'),
            matching: find.byType(Transform),
          )
          .first);
      // Snapped to the 50% middle position, not fully dismissed.
      expect(transform.transform.getTranslation().x, closeTo(400, 1));
      await _flushConfirmTimer(tester);
    });

    testWidgets('a tiny drag snaps back and does not open', (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        background: _background('Archive'),
        onConfirm: (_) => true,
        child: _tile('Swipe me'),
      )));

      await tester.drag(find.byType(PulsrDismissible), const Offset(20, 0));
      await tester.pumpAndSettle();

      expect(find.text('Archive'), findsNothing);
    });

    testWidgets('a fast fling opens the tile even with a small offset',
        (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        background: _background('Archive'),
        onConfirm: (_) => true,
        child: _tile('Swipe me'),
      )));

      await tester.fling(
          find.byType(PulsrDismissible), const Offset(60, 0), 2000);
      await tester.pumpAndSettle();

      expect(find.text('Archive'), findsOneWidget);
      await _flushConfirmTimer(tester);
    });

    testWidgets('dragging far past the middle is rubber-band clamped',
        (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        background: _background('Archive'),
        onConfirm: (_) => true,
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester, by: 600);

      final transform = tester.widget<Transform>(find
          .ancestor(
            of: find.text('Swipe me'),
            matching: find.byType(Transform),
          )
          .first);
      expect(transform.transform.getTranslation().x, closeTo(400, 1));
      await _flushConfirmTimer(tester);
    });

    testWidgets('dragging out and back to zero closes instead of opening',
        (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        background: _background('Archive'),
        onConfirm: (_) => true,
        child: _tile('Swipe me'),
      )));

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(PulsrDismissible)));
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(find.text('Archive'), findsOneWidget);

      await gesture.moveBy(const Offset(-260, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Archive'), findsNothing);
    });
  });

  group('confirm and dismiss', () {
    testWidgets('a second swipe in the same direction confirms and collapses',
        (tester) async {
      DismissDirection? confirmed;
      await tester.pumpWidget(_app(PulsrDismissible(
        backgroundBuilder: (context, isConfirming) =>
            _background(isConfirming ? 'Confirm Archive' : 'Archive'),
        onConfirm: (direction) async {
          confirmed = direction;
          return true;
        },
        swipeSound: () {},
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester);
      expect(find.text('Confirm Archive'), findsOneWidget);

      await tester.drag(find.byType(PulsrDismissible), const Offset(120, 0));
      await tester.pumpAndSettle();

      expect(confirmed, DismissDirection.startToEnd);
      expect(find.text('Swipe me'), findsNothing);
      expect(find.byType(PulsrDismissible), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PulsrDismissible),
          matching: find.byType(SizedBox),
        ),
        findsWidgets,
      );
    });

    testWidgets('confirm returning false glides back to closed',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(PulsrDismissible(
        background: _background('Archive'),
        onConfirm: (_) {
          calls++;
          return false;
        },
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester);
      await tester.drag(find.byType(PulsrDismissible), const Offset(120, 0));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Swipe me'), findsOneWidget);
    });

    testWidgets('a synchronous FutureOr<bool> result is awaited correctly',
        (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        secondaryBackground: _background('Delete', isEnd: true),
        onConfirm: (_) => true,
        child: _tile('Swipe me'),
      )));

      await _openEndToStart(tester);
      await tester.drag(find.byType(PulsrDismissible), const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(find.text('Swipe me'), findsNothing);
    });

    testWidgets('tapping the shifted child cancels instead of confirming',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(PulsrDismissible(
        background: _background('Archive'),
        onConfirm: (_) {
          calls++;
          return true;
        },
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester);
      await tester.tapAt(tester.getTopLeft(find.byType(PulsrDismissible)) +
          const Offset(120, 32));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Swipe me'), findsOneWidget);
    });

    testWidgets('the confirm timeout closes the tile on its own',
        (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        confirmTimeout: const Duration(milliseconds: 600),
        background: _background('Archive'),
        onConfirm: (_) => true,
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester);
      expect(find.text('Archive'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text('Archive'), findsNothing);
    });

    testWidgets('showToast surfaces the swipe-again snackbar with the label',
        (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        showToast: true,
        startToEndLabel: 'Archive',
        background: _background('Archive'),
        onConfirm: (_) => false,
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester);

      expect(
          find.text('Swipe again or tap to confirm: Archive'), findsOneWidget);

      await _flushConfirmTimer(tester);
    });

    testWidgets('showToast without a label uses the generic message',
        (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        showToast: true,
        secondaryBackground: _background('Delete', isEnd: true),
        onConfirm: (_) => false,
        child: _tile('Swipe me'),
      )));

      await _openEndToStart(tester);

      expect(find.text('Swipe again or tap to confirm'), findsOneWidget);
      await _flushConfirmTimer(tester);
    });
  });

  group('second-swipe cancellation paths', () {
    testWidgets('dragging from the middle back past the threshold closes',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(PulsrDismissible(
        background: _background('Archive'),
        onConfirm: (_) {
          calls++;
          return true;
        },
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester);
      await tester.drag(find.byType(PulsrDismissible), const Offset(-180, 0));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.text('Archive'), findsNothing);
    });

    testWidgets('a small second swipe snaps back to the middle',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(PulsrDismissible(
        background: _background('Archive'),
        onConfirm: (_) {
          calls++;
          return true;
        },
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester);
      await tester.drag(find.byType(PulsrDismissible), const Offset(30, 0));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.text('Archive'), findsOneWidget);
      await _flushConfirmTimer(tester);
    });

    testWidgets('an interrupted second swipe snaps back to the middle',
        (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        background: _background('Archive'),
        onConfirm: (_) => true,
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester);
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(PulsrDismissible)));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(find.text('Archive'), findsOneWidget);
      await _flushConfirmTimer(tester);
    });

    testWidgets('a fast negative fling from the middle closes the tile',
        (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        background: _background('Archive'),
        onConfirm: (_) => true,
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester);
      await tester.fling(
          find.byType(PulsrDismissible), const Offset(-200, 0), 2000);
      await tester.pumpAndSettle();

      expect(find.text('Archive'), findsNothing);
    });

    testWidgets('dragging from end-middle back toward centre closes',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(PulsrDismissible(
        secondaryBackground: _background('Delete', isEnd: true),
        onConfirm: (_) {
          calls++;
          return true;
        },
        child: _tile('Swipe me'),
      )));

      await _openEndToStart(tester);
      await tester.drag(find.byType(PulsrDismissible), const Offset(180, 0));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('a small second swipe on the end side snaps back',
        (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        secondaryBackground: _background('Delete', isEnd: true),
        onConfirm: (_) => true,
        child: _tile('Swipe me'),
      )));

      await _openEndToStart(tester);
      await tester.drag(find.byType(PulsrDismissible), const Offset(30, 0));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      await _flushConfirmTimer(tester);
    });
  });

  group('cross-tile coordination', () {
    testWidgets('opening a second tile closes the first one', (tester) async {
      await tester.pumpWidget(_app(Column(
        children: [
          PulsrDismissible(
            key: const ValueKey('first'),
            background: _background('First action'),
            onConfirm: (_) => false,
            child: _tile('First'),
          ),
          PulsrDismissible(
            key: const ValueKey('second'),
            background: _background('Second action'),
            onConfirm: (_) => false,
            child: _tile('Second'),
          ),
        ],
      )));

      await tester.drag(
          find.byKey(const ValueKey('first')), const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(find.text('First action'), findsOneWidget);

      await tester.drag(
          find.byKey(const ValueKey('second')), const Offset(220, 0));
      await tester.pumpAndSettle();

      expect(find.text('Second action'), findsOneWidget);
      expect(find.text('First action'), findsNothing);
      await _flushConfirmTimer(tester);

      // Close the second one too so no timer is left pending.
      await tester.tapAt(
          tester.getTopLeft(find.byKey(const ValueKey('second'))) +
              const Offset(60, 20));
      await tester.pumpAndSettle();
    });

    testWidgets('scrolling the parent list closes an open tile',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              PulsrDismissible(
                key: const ValueKey('scrollable-tile'),
                background: _background('Archive'),
                onConfirm: (_) => false,
                child: _tile('Scroll me'),
              ),
              SizedBox(height: 800, child: _tile('Filler')),
            ],
          ),
        ),
      ));

      await tester.drag(
          find.byKey(const ValueKey('scrollable-tile')), const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(find.text('Archive'), findsNothing);
    });
  });

  group('custom geometry', () {
    testWidgets('a custom middleRatio is honoured', (tester) async {
      await tester.pumpWidget(_app(PulsrDismissible(
        middleRatio: 0.25,
        background: _background('Archive'),
        onConfirm: (_) => true,
        child: _tile('Swipe me'),
      )));

      await _openStartToEnd(tester);

      final transform = tester.widget<Transform>(find
          .ancestor(
            of: find.text('Swipe me'),
            matching: find.byType(Transform),
          )
          .first);
      expect(transform.transform.getTranslation().x, closeTo(200, 1));
      await _flushConfirmTimer(tester);
    });

    testWidgets('an unbounded-width parent falls back to the screen width',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: PulsrDismissible(
                  background: _background('Archive'),
                  onConfirm: (_) => false,
                  child: _tile('Swipe me', width: double.infinity),
                ),
              ),
            ],
          ),
        ),
      ));

      await tester.drag(find.byType(PulsrDismissible), const Offset(200, 0));
      await tester.pumpAndSettle();

      expect(find.text('Archive'), findsOneWidget);
      await _flushConfirmTimer(tester);
    });
  });
}
