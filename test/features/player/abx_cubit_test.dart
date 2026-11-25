// test/features/player/abx_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/abx_session.dart';
import 'package:pulsr/features/player/cubit/abx_cubit.dart';

/// Records the bypass flags the cubit pushes at the signal path.
///
/// Stands in for `PlayerCubit.setBypassCompare`, so these tests need neither a
/// player cubit nor a platform channel.
class _SwitchRecorder {
  final List<bool> calls = <bool>[];

  Future<void> call(bool bypass) async {
    calls.add(bypass);
  }

  bool? get last => calls.isEmpty ? null : calls.last;
}

/// Mutable stand-in for "a song is loaded and DSP is on".
class _Readiness {
  _Readiness(this.value);

  bool value;

  bool call() => value;
}

AbxCubit _buildCubit({
  required _SwitchRecorder recorder,
  required _Readiness readiness,
  int trials = AbxCubit.defaultTrials,
  int seed = 7,
}) {
  return AbxCubit(
    switchCondition: recorder.call,
    isReady: readiness.call,
    trials: trials,
    sessionFactory: (int count) => AbxSession(trials: count, seed: seed),
  );
}

/// Answers the pending trial correctly.
bool? _answerCorrectly(AbxCubit cubit) {
  final AbxTrial trial = cubit.current!;
  return cubit.answer(
    trial.hiddenX == AbxStimulus.a ? AbxAnswer.a : AbxAnswer.b,
  );
}

/// Answers the pending trial incorrectly.
bool? _answerWrongly(AbxCubit cubit) {
  final AbxTrial trial = cubit.current!;
  return cubit.answer(
    trial.hiddenX == AbxStimulus.a ? AbxAnswer.b : AbxAnswer.a,
  );
}

void main() {
  test('start() needs a loaded track and active DSP', () async {
    final recorder = _SwitchRecorder();
    final readiness = _Readiness(false);
    final cubit = _buildCubit(recorder: recorder, readiness: readiness);

    expect(cubit.state.canStart, isFalse);
    expect(cubit.start(), isFalse);
    expect(cubit.state.isRunning, isFalse);

    // An unusable session must not be gradeable at all.
    expect(cubit.answer(AbxAnswer.a), isNull);
    expect(cubit.answeredCount, 0);
    expect(cubit.current, isNull);

    readiness.value = true;
    cubit.refreshReadiness();
    expect(cubit.state.canStart, isTrue);

    expect(cubit.start(), isTrue);
    expect(cubit.state.isRunning, isTrue);
    expect(cubit.answeredCount, 0);
    expect(cubit.total, AbxCubit.defaultTrials);

    await cubit.close();
  });

  test('A/B/X switch the bypass and X follows the hidden trial plan', () async {
    final recorder = _SwitchRecorder();
    final cubit = _buildCubit(recorder: recorder, readiness: _Readiness(true));
    expect(cubit.start(), isTrue);

    await cubit.playCondition(AbxStimulus.a);
    expect(recorder.last, isTrue, reason: 'A is the dry, bypassed condition');
    expect(cubit.state.activeCondition, AbxStimulus.a);

    await cubit.playCondition(AbxStimulus.b);
    expect(recorder.last, isFalse, reason: 'B is the DSP-active condition');
    expect(cubit.state.activeCondition, AbxStimulus.b);

    for (int i = 0; i < AbxCubit.defaultTrials; i++) {
      final AbxStimulus hidden = cubit.current!.hiddenX;
      await cubit.playCondition(AbxStimulus.x);
      expect(recorder.last, hidden == AbxStimulus.a,
          reason: 'trial $i: X must play the hidden condition');
      _answerCorrectly(cubit);
    }

    expect(cubit.state.isComplete, isTrue);
    expect(cubit.correctCount, AbxCubit.defaultTrials);

    await cubit.close();
  });

  test('grading advances the score and the binomial p-value', () async {
    final recorder = _SwitchRecorder();
    final cubit = _buildCubit(recorder: recorder, readiness: _Readiness(true));
    expect(cubit.start(), isTrue);

    expect(_answerCorrectly(cubit), isTrue);
    expect(cubit.correctCount, 1);
    expect(cubit.answeredCount, 1);
    expect(cubit.state.correctCount, 1);
    expect(cubit.state.answeredCount, 1);

    expect(_answerWrongly(cubit), isFalse);
    expect(cubit.correctCount, 1);
    expect(cubit.answeredCount, 2);
    // One hit out of two is 1 - P(X <= 0) = 0.75 under the fair-coin null.
    expect(cubit.pValue, closeTo(0.75, 1e-12));
    expect(cubit.verdictKey, AbxSession.insufficientKey);

    await cubit.close();
  });

  test('a completed session cannot be graded a second time', () async {
    final recorder = _SwitchRecorder();
    final cubit = _buildCubit(recorder: recorder, readiness: _Readiness(true));
    expect(cubit.start(), isTrue);

    for (int i = 0; i < AbxCubit.defaultTrials; i++) {
      expect(_answerCorrectly(cubit), isTrue);
    }
    expect(cubit.state.isComplete, isTrue);
    expect(cubit.current, isNull);
    expect(cubit.verdictKey, AbxSession.strongKey);
    expect(cubit.pValue, closeTo(0.000244140625, 1e-12));

    expect(cubit.answer(AbxAnswer.a), isNull);
    expect(cubit.answer(AbxAnswer.b), isNull);
    expect(cubit.answeredCount, AbxCubit.defaultTrials);
    expect(cubit.correctCount, AbxCubit.defaultTrials);

    // No trial is pending, so asking for a stimulus must not touch the path.
    final int callsBefore = recorder.calls.length;
    await cubit.playCondition(AbxStimulus.x);
    expect(recorder.calls.length, callsBefore);

    await cubit.close();
  });

  test('playing a new stimulus clears the previous verdict', () async {
    final recorder = _SwitchRecorder();
    final cubit = _buildCubit(recorder: recorder, readiness: _Readiness(true));
    expect(cubit.start(), isTrue);

    expect(_answerCorrectly(cubit), isTrue);
    expect(cubit.state.lastAnswerCorrect, isTrue);

    await cubit.playCondition(AbxStimulus.x);
    expect(cubit.state.lastAnswerCorrect, isNull);
    expect(cubit.state.activeCondition, AbxStimulus.x);

    await cubit.close();
  });

  test('restart clears the run and restores the DSP condition', () async {
    final recorder = _SwitchRecorder();
    final cubit = _buildCubit(recorder: recorder, readiness: _Readiness(true));
    expect(cubit.start(), isTrue);

    await cubit.playCondition(AbxStimulus.a);
    _answerCorrectly(cubit);
    _answerWrongly(cubit);
    expect(cubit.answeredCount, 2);

    await cubit.restart();

    expect(cubit.answeredCount, 0);
    expect(cubit.correctCount, 0);
    expect(cubit.state.isComplete, isFalse);
    expect(cubit.state.isRunning, isTrue);
    expect(cubit.state.lastAnswerCorrect, isNull);
    expect(cubit.state.activeCondition, isNull);
    expect(cubit.pValue, 1.0);
    expect(cubit.verdictKey, AbxSession.insufficientKey);
    expect(cubit.total, AbxCubit.defaultTrials);
    expect(recorder.last, isFalse, reason: 'restart returns to DSP active');

    await cubit.close();
  });

  test('close restores the DSP condition', () async {
    final recorder = _SwitchRecorder();
    final cubit = _buildCubit(recorder: recorder, readiness: _Readiness(true));
    expect(cubit.start(), isTrue);

    await cubit.playCondition(AbxStimulus.a);
    expect(recorder.last, isTrue);

    await cubit.close();
    expect(recorder.last, isFalse);
  });

  test('stopping playback mid-run gates start without losing the score',
      () async {
    final recorder = _SwitchRecorder();
    final readiness = _Readiness(true);
    final cubit = _buildCubit(recorder: recorder, readiness: readiness);
    expect(cubit.start(), isTrue);
    _answerCorrectly(cubit);

    readiness.value = false;
    cubit.refreshReadiness();

    expect(cubit.state.canStart, isFalse);
    expect(cubit.state.isRunning, isTrue);
    expect(cubit.answeredCount, 1);
    expect(cubit.correctCount, 1);

    await cubit.close();
  });

  test(
      'playCondition handles switch failure without unhandled exception and rolls back active condition',
      () async {
    var shouldThrow = false;
    final cubit = AbxCubit(
      switchCondition: (bypass) async {
        if (shouldThrow) throw StateError('switch error');
      },
      isReady: () => true,
    );
    expect(cubit.start(), isTrue);

    await cubit.playCondition(AbxStimulus.a);
    expect(cubit.state.activeCondition, AbxStimulus.a);

    shouldThrow = true;
    await cubit.playCondition(AbxStimulus.b);
    expect(cubit.state.activeCondition, AbxStimulus.a);

    await cubit.close();
  });
}
