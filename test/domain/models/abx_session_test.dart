import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/abx_session.dart';

/// Runs every balance/run-length check over this many seeds.
const int seedSweep = 200;

List<AbxStimulus> sequenceOf(AbxSession session) =>
    <AbxStimulus>[for (final trial in session.trials) trial.hiddenX];

int countOf(List<AbxStimulus> sequence, AbxStimulus value) =>
    sequence.where((AbxStimulus item) => item == value).length;

int longestRunOf(List<AbxStimulus> sequence) {
  var longest = 0;
  var run = 0;
  AbxStimulus? previous;
  for (final value in sequence) {
    run = value == previous ? run + 1 : 1;
    previous = value;
    if (run > longest) longest = run;
  }
  return longest;
}

void answerCorrectly(AbxSession session) {
  final trial = session.current;
  session.answer(trial.hiddenX == AbxStimulus.a ? AbxAnswer.a : AbxAnswer.b);
}

void answerIncorrectly(AbxSession session) {
  final trial = session.current;
  session.answer(trial.hiddenX == AbxStimulus.a ? AbxAnswer.b : AbxAnswer.a);
}

AbxSession completed({
  required int trials,
  required int correct,
  int seed = 7,
}) {
  final session = AbxSession(trials: trials, seed: seed);
  for (var i = 0; i < trials; i++) {
    if (i < correct) {
      answerCorrectly(session);
    } else {
      answerIncorrectly(session);
    }
  }
  return session;
}

void main() {
  group('trial plan', () {
    test('balances A and B for even trial counts across 200 seeds', () {
      for (final trials in <int>[2, 10, 50, 100]) {
        for (var seed = 0; seed < seedSweep; seed++) {
          final sequence = sequenceOf(AbxSession(trials: trials, seed: seed));
          final reason = 'trials=$trials seed=$seed';
          expect(sequence.length, trials, reason: reason);
          expect(countOf(sequence, AbxStimulus.a), trials ~/ 2, reason: reason);
          expect(countOf(sequence, AbxStimulus.b), trials ~/ 2, reason: reason);
          expect(sequence, isNot(contains(AbxStimulus.x)), reason: reason);
        }
      }
    });

    test('puts the odd extra trial on A', () {
      for (final trials in <int>[1, 3, 9, 51, 101]) {
        for (var seed = 0; seed < seedSweep; seed++) {
          final sequence = sequenceOf(AbxSession(trials: trials, seed: seed));
          final reason = 'trials=$trials seed=$seed';
          expect(countOf(sequence, AbxStimulus.a), (trials + 1) ~/ 2,
              reason: reason);
          expect(countOf(sequence, AbxStimulus.b), trials ~/ 2, reason: reason);
        }
      }
    });

    test('never runs more than four identical X values in a row', () {
      for (final trials in <int>[10, 37, 100, 499]) {
        for (var seed = 0; seed < seedSweep; seed++) {
          final sequence = sequenceOf(AbxSession(trials: trials, seed: seed));
          expect(longestRunOf(sequence), lessThanOrEqualTo(4),
              reason: 'trials=$trials seed=$seed');
        }
      }
    });

    test('reproduces the same hidden sequence for the same seed', () {
      final first = sequenceOf(AbxSession(trials: 40, seed: 1234));
      final second = sequenceOf(AbxSession(trials: 40, seed: 1234));
      final other = sequenceOf(AbxSession(trials: 40, seed: 1235));
      expect(second, equals(first));
      expect(other, isNot(equals(first)));

      final injectedA = sequenceOf(AbxSession(trials: 30, random: Random(9)));
      final injectedB = sequenceOf(AbxSession(trials: 30, random: Random(9)));
      expect(injectedB, equals(injectedA));
    });
  });

  group('answers', () {
    test('walks trials in order and grades each answer', () {
      final session = AbxSession(trials: 4, seed: 3);
      expect(session.trialCount, 4);
      expect(session.answeredCount, 0);
      expect(session.isComplete, isFalse);
      expect(session.current.index, 0);

      answerCorrectly(session);
      expect(session.answeredCount, 1);
      expect(session.current.index, 1);
      expect(session.trials[0].isAnswered, isTrue);
      expect(session.trials[0].correct, isTrue);
      expect(session.correctCount, 1);

      answerIncorrectly(session);
      expect(session.answeredCount, 2);
      expect(session.trials[1].correct, isFalse);
      expect(session.correctCount, 1);
      expect(session.proportionCorrect, closeTo(0.5, 1e-12));

      expect(() => session.trials.add(session.trials.first),
          throwsUnsupportedError);
    });

    test('rejects a second answer for the same trial', () {
      final session = AbxSession(trials: 5, seed: 8);
      // A stale UI callback can stamp the trial object it rendered; the
      // session must refuse to grade that trial twice.
      session.current.answer = AbxAnswer.a;
      expect(() => session.answer(AbxAnswer.b), throwsStateError);
      expect(session.answeredCount, 0);
    });

    test('rejects answers and current access after completion', () {
      final session = completed(trials: 6, correct: 3);
      expect(session.isComplete, isTrue);
      expect(() => session.answer(AbxAnswer.a), throwsStateError);
      expect(() => session.current, throwsStateError);
    });

    test('reset clears answers but keeps the trial count and seeded order', () {
      final session = AbxSession(trials: 12, seed: 21);
      final before = sequenceOf(session);
      answerCorrectly(session);
      answerIncorrectly(session);

      session.reset();
      expect(session.trialCount, 12);
      expect(session.answeredCount, 0);
      expect(session.correctCount, 0);
      expect(session.isComplete, isFalse);
      expect(session.trials.every((trial) => !trial.isAnswered), isTrue);
      expect(sequenceOf(session), equals(before));
      expect(session.current.index, 0);

      session.reset(trials: 21);
      expect(session.trialCount, 21);
      expect(countOf(sequenceOf(session), AbxStimulus.a), 11);
    });

    test('rejects a non-positive trial count', () {
      expect(() => AbxSession(trials: 0), throwsArgumentError);
      final session = AbxSession(trials: 4, seed: 1);
      expect(() => session.reset(trials: 0), throwsArgumentError);
      expect(session.trialCount, 4);
    });
  });

  group('statistics', () {
    test('matches hand-computed p-values', () {
      // 1/32.
      expect(completed(trials: 5, correct: 5).pValue, closeTo(0.03125, 1e-12));
      // 1/1024.
      expect(completed(trials: 10, correct: 10).pValue,
          closeTo(0.0009765625, 1e-12));
      // The whole distribution.
      expect(completed(trials: 10, correct: 0).pValue, 1.0);
      // (120 + 45 + 10 + 1) / 1024.
      expect(
          completed(trials: 10, correct: 7).pValue, closeTo(0.171875, 1e-12));
      // 1 - 1/1024.
      expect(completed(trials: 10, correct: 1).pValue,
          closeTo(0.9990234375, 1e-12));
      // (252 + 210 + 120 + 45 + 10 + 1) / 1024, the dyadic mid-tail.
      expect(completed(trials: 10, correct: 5).pValue,
          closeTo(0.623046875, 1e-15));
    });

    test('p-value never increases as correctCount grows', () {
      final values = <double>[
        for (var correct = 0; correct <= 20; correct++)
          completed(trials: 20, correct: correct).pValue,
      ];
      expect(values.first, 1.0);
      // 2^-20.
      expect(values.last, closeTo(1 / 1048576, 1e-18));
      for (var i = 1; i < values.length; i++) {
        expect(values[i], lessThanOrEqualTo(values[i - 1] + 1e-15),
            reason: 'correctCount=$i');
      }
    });

    test('reports proportionCorrect, confidence and empty-session defaults',
        () {
      final empty = AbxSession(trials: 10, seed: 2);
      expect(empty.pValue, 1.0);
      expect(empty.confidence, 0.0);
      expect(empty.proportionCorrect, 0.0);
      expect(empty.verdictKey, AbxSession.insufficientKey);

      final session = completed(trials: 10, correct: 8);
      expect(session.proportionCorrect, closeTo(0.8, 1e-12));
      expect(session.confidence, closeTo(1.0 - session.pValue, 1e-15));
    });
  });

  group('verdict', () {
    test('maps documented thresholds at their exact boundaries', () {
      expect(AbxSession.verdictKeyForPValue(0.05, trials: 10),
          AbxSession.chanceKey);
      expect(AbxSession.verdictKeyForPValue(0.05 - 1e-12, trials: 10),
          AbxSession.suggestiveKey);
      expect(AbxSession.verdictKeyForPValue(0.01, trials: 10),
          AbxSession.suggestiveKey);
      expect(AbxSession.verdictKeyForPValue(0.01 - 1e-12, trials: 10),
          AbxSession.significantKey);
      expect(AbxSession.verdictKeyForPValue(0.001, trials: 10),
          AbxSession.significantKey);
      expect(AbxSession.verdictKeyForPValue(0.001 - 1e-12, trials: 10),
          AbxSession.strongKey);
      expect(AbxSession.verdictKeyForPValue(1.0, trials: 10),
          AbxSession.chanceKey);
      expect(AbxSession.verdictKeyForPValue(0.0, trials: 10),
          AbxSession.strongKey);
      expect(AbxSession.verdictKeyForPValue(0.0001, trials: 9),
          AbxSession.insufficientKey);
      expect(AbxSession.verdictKeyForPValue(double.nan, trials: 50),
          AbxSession.insufficientKey);
    });

    test('assigns verdict keys from real sessions', () {
      // 176/1024 and 56/1024 both stay above 0.05.
      expect(completed(trials: 10, correct: 7).verdictKey, 'chance');
      expect(completed(trials: 10, correct: 8).verdictKey, 'chance');
      // 11/1024 = 0.0107421875.
      expect(completed(trials: 10, correct: 9).verdictKey, 'suggestive');
      // 14/8192 = 0.001708984375.
      expect(completed(trials: 13, correct: 12).verdictKey, 'significant');
      // 1/1024.
      expect(completed(trials: 10, correct: 10).verdictKey, 'strong');
      expect(completed(trials: 9, correct: 9).verdictKey, 'insufficient');
    });

    test('withholds a verdict until the session is complete', () {
      final session = AbxSession(trials: 12, seed: 4);
      for (var i = 0; i < 11; i++) {
        answerCorrectly(session);
      }
      expect(session.isComplete, isFalse);
      expect(session.pValue, closeTo(1 / 2048, 1e-15));
      expect(session.verdictKey, AbxSession.insufficientKey);

      answerCorrectly(session);
      expect(session.isComplete, isTrue);
      expect(session.verdictKey, AbxSession.strongKey);
    });
  });

  group('large sessions', () {
    test('500 correct answers stay finite and strong', () {
      final session = AbxSession(trials: 500, seed: 77);
      for (var i = 0; i < 500; i++) {
        answerCorrectly(session);
      }
      final p = session.pValue;
      expect(p.isNaN, isFalse);
      expect(p.isFinite, isTrue);
      expect(p, greaterThan(0.0));
      expect(p, lessThan(1e-100));
      expect(session.proportionCorrect, 1.0);
      expect(session.confidence, closeTo(1.0, 1e-12));
      expect(session.verdictKey, AbxSession.strongKey);
    });

    test('500 mixed answers stay finite and inside [0, 1]', () {
      final session = AbxSession(trials: 500, seed: 78);
      for (var i = 0; i < 500; i++) {
        if (i.isEven) {
          answerCorrectly(session);
        } else {
          answerIncorrectly(session);
        }
      }
      final p = session.pValue;
      expect(p.isNaN, isFalse);
      expect(p.isInfinite, isFalse);
      expect(p, inInclusiveRange(0.0, 1.0));
      expect(session.correctCount, 250);
      expect(session.proportionCorrect, closeTo(0.5, 1e-12));
      expect(session.verdictKey, AbxSession.chanceKey);
    });

    test('500 trials with a single correct answer stay at p ~ 1', () {
      final session = AbxSession(trials: 500, seed: 80);
      answerCorrectly(session);
      for (var i = 1; i < 500; i++) {
        answerIncorrectly(session);
      }
      expect(session.correctCount, 1);
      expect(session.pValue, closeTo(1.0, 1e-15));
    });

    test('499-trial plan is balanced and stable', () {
      final session = AbxSession(trials: 499, seed: 79);
      final sequence = sequenceOf(session);
      expect(countOf(sequence, AbxStimulus.a), 250);
      expect(countOf(sequence, AbxStimulus.b), 249);
      expect(longestRunOf(sequence), lessThanOrEqualTo(4));

      for (var i = 0; i < 498; i++) {
        answerCorrectly(session);
      }
      expect(session.pValue.isFinite, isTrue);
      answerIncorrectly(session);
      expect(session.pValue.isFinite, isTrue);
      expect(session.isComplete, isTrue);
    });
  });
}
