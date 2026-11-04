// test/data/party/party_sync_controller_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/party/party_sync_controller.dart';

void main() {
  group('audible timeline conversion', () {
    test('the host anchor carries its own output latency', () {
      expect(
          PartySyncController.audibleAnchorPositionMs(
              hostRenderPositionMs: 5000, hostOutputLatencyMs: 180),
          5180);
    });

    test('a zero-latency host anchors at its render position', () {
      expect(
          PartySyncController.audibleAnchorPositionMs(
              hostRenderPositionMs: 5000, hostOutputLatencyMs: 0),
          5000);
    });

    // A negative calibration must not drag the room timeline backwards in time.
    test('negative latencies are clamped rather than trusted', () {
      expect(
          PartySyncController.audibleAnchorPositionMs(
              hostRenderPositionMs: 5000, hostOutputLatencyMs: -400),
          5000);
      expect(
          PartySyncController.targetRenderPositionMs(
              roomPositionMs: 5000, outputLatencyMs: -400),
          5000);
    });
  });

  group('target render position', () {
    test('a delayed device renders in the past so sound lands on the room', () {
      expect(
          PartySyncController.targetRenderPositionMs(
              roomPositionMs: 10000, outputLatencyMs: 180),
          9820);
    });

    test('never schedules a negative position', () {
      expect(
          PartySyncController.targetRenderPositionMs(
              roomPositionMs: 100, outputLatencyMs: 400),
          0);
    });

    test('signed error measures audible disagreement, not position equality', () {
      // The device renders exactly the room position, so a naive comparison
      // calls this in sync. That audio reaches the listener 180 ms before the
      // room time it stands for, so it is 180 ms AHEAD.
      final error = PartySyncController.signedErrorMs(
          localRenderMs: 10000, roomPositionMs: 10000, outputLatencyMs: 180);
      expect(error, 180);

      // Correctly compensated: rendering 180 ms in the past is spot on.
      expect(
          PartySyncController.signedErrorMs(
              localRenderMs: 9820, roomPositionMs: 10000, outputLatencyMs: 180),
          0);

      // Rendering behind the compensated target is heard late.
      expect(
          PartySyncController.signedErrorMs(
              localRenderMs: 9700, roomPositionMs: 10000, outputLatencyMs: 180),
          -120);
    });
  });

  group('decision tiers', () {
    test('errors inside the deadband do nothing and clear strikes', () {
      final controller = PartySyncController();
      controller.evaluatePosition(
          localRenderMs: 5040, roomPositionMs: 5000, outputLatencyMs: 0);
      expect(controller.strikes, greaterThan(0));

      final inside = controller.evaluatePosition(
          localRenderMs: 5008, roomPositionMs: 5000, outputLatencyMs: 0);
      expect(inside.action, SyncAction.none);
      expect(controller.strikes, 0);
    });

    test('a grey-band error waits one tick, then seeks', () {
      final controller = PartySyncController();
      final first = controller.evaluatePosition(
          localRenderMs: 4940, roomPositionMs: 5000, outputLatencyMs: 0);
      expect(first.action, SyncAction.watch);
      expect(first.errorMs, -60);

      final second = controller.evaluatePosition(
          localRenderMs: 4940, roomPositionMs: 5000, outputLatencyMs: 0);
      expect(second.action, SyncAction.seek);
      expect(second.seekToMs, 5000);
    });

    test('a single transient tick is enough past the seek threshold', () {
      final controller = PartySyncController();
      final decision = controller.evaluatePosition(
          localRenderMs: 5131, roomPositionMs: 5000, outputLatencyMs: 0);
      expect(decision.action, SyncAction.seek);
      expect(decision.errorMs, greaterThan(PartySyncController.seekThresholdMs));
      expect(decision.strikes, 0);
    });

    test('ahead and behind are treated symmetrically', () {
      final controller = PartySyncController();
      final ahead = controller.evaluatePosition(
          localRenderMs: 5250, roomPositionMs: 5000, outputLatencyMs: 0);
      controller.reset();
      final behind = controller.evaluatePosition(
          localRenderMs: 4750, roomPositionMs: 5000, outputLatencyMs: 0);
      expect(ahead.action, behind.action);
      expect(ahead.errorMs, -behind.errorMs);
      expect(ahead.seekToMs, behind.seekToMs);
    });

    test('the seek target is latency-compensated, not the raw room position',
        () {
      final controller = PartySyncController();
      final decision = controller.evaluatePosition(
          localRenderMs: 3000, roomPositionMs: 12000, outputLatencyMs: 200);
      expect(decision.action, SyncAction.seek);
      expect(decision.seekToMs, 11800);
    });

    test('a compensated target beyond the track end clamps to the duration',
        () {
      final controller = PartySyncController();
      final decision = controller.evaluatePosition(
        localRenderMs: 1000,
        roomPositionMs: 200000,
        outputLatencyMs: 0,
        durationMs: 184000,
      );
      expect(decision.seekToMs, 184000);
    });

    test('reset clears accumulated strikes', () {
      final controller = PartySyncController();
      controller.evaluatePosition(
          localRenderMs: 4940, roomPositionMs: 5000, outputLatencyMs: 0);
      expect(controller.strikes, 1);
      controller.reset();
      expect(controller.strikes, 0);
    });
  });

  group('scheduled starts', () {
    test('a future anchor arms a timer for exactly the lead', () {
      final plan = PartySyncController.planStart(
          anchorServerMs: 10000, nowServerMs: 9600);
      expect(plan.startImmediately, isFalse);
      expect(plan.applied, const Duration(milliseconds: 400));
    });

    test('an anchor already in the past starts immediately', () {
      final plan = PartySyncController.planStart(
          anchorServerMs: 9000, nowServerMs: 9600);
      expect(plan.startImmediately, isTrue);
      expect(plan.applied, Duration.zero);
    });

    // A 5 s lead means a clock that is badly wrong, not a scheduled start; going
    // silent for it is worse than being slightly early.
    test('an implausible lead is reported but not waited on', () {
      final plan = PartySyncController.planStart(
          anchorServerMs: 20000, nowServerMs: 9600);
      expect(plan.wait, const Duration(milliseconds: 10400));
      expect(plan.startImmediately, isTrue);
    });

    test('a sub-timer-resolution lead is taken as-is', () {
      final plan = PartySyncController.planStart(
          anchorServerMs: 9605, nowServerMs: 9600);
      expect(plan.applied, const Duration(milliseconds: 5));
    });
  });

  group('steady-state behaviour', () {
    // The point of the whole exercise: output latency is a PHASE offset, not a
    // rate difference. A member that starts at (room - latency) and advances at
    // its own clock stays aligned to the room's audible time, and only its ppm
    // error accumulates - which the deadband absorbs.
    test('a compensated Bluetooth member holds inside the deadband', () {
      final controller = PartySyncController();
      const outputLatency = 220;
      const clockPpm = 50; // generous for a phone audio clock

      var room = 60000.0;
      var localRender = room - outputLatency;
      var worstError = 0;

      // 400 ticks at the reconciliation cadence = 100 s of listening.
      for (var tick = 0; tick < 400; tick++) {
        final advance =
            PartySyncController.reconcileTickMs * (1 + clockPpm / 1e6);
        localRender += advance;
        room += PartySyncController.reconcileTickMs;

        final decision = controller.evaluatePosition(
          localRenderMs: localRender.round(),
          roomPositionMs: room.round(),
          outputLatencyMs: outputLatency,
        );
        worstError = math.max(worstError, decision.errorMs.abs());
        expect(decision.action, isNot(SyncAction.seek),
            reason: 'tick $tick drifted ${decision.errorMs} ms');
      }

      // ~5 ms of accumulated ppm error across 100 s, as predicted.
      expect(worstError, lessThan(PartySyncController.audibleDeadbandMs));
    });

    test('ignoring latency misreads a correct member as 220 ms behind', () {
      // Pre-Phase-3 behaviour: the same correctly compensated device, evaluated
      // without the latency term, looks far out of sync and gets seeked
      // repeatedly - which is how the old loop dragged members out of alignment.
      final controller = PartySyncController();
      const outputLatency = 220;

      final decision = controller.evaluatePosition(
        localRenderMs: 60000 - outputLatency,
        roomPositionMs: 60000,
        outputLatencyMs: 0,
      );
      expect(decision.errorMs, -outputLatency);
      expect(decision.action, SyncAction.seek);
      expect(decision.seekToMs, 60000);
    });
  });
}
