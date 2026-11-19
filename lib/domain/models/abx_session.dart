// lib/domain/models/abx_session.dart
//
// Pure-Dart ABX listening-test engine.
//
// An ABX trial presents three stimuli: A (the reference), B (the comparison)
// and X (a hidden copy of exactly one of them). The listener must say whether
// X matches A or B. Guessing wins with probability 0.5 per trial, so the
// evidence is the one-sided binomial tail P(X >= correct | p = 0.5).
//
// This file owns trial order, answer bookkeeping and the statistics. It has no
// Flutter dependency, so it can be unit-tested and reused off the UI isolate.

import 'dart:math';

/// The three stimuli an ABX trial can refer to.
enum AbxStimulus { a, b, x }

/// The listener's forced choice for a trial.
enum AbxAnswer { a, b }

/// A single ABX trial: the hidden reference plus the listener's answer.
///
/// [answer] and [correct] are null until the trial is answered and are written
/// only by [AbxSession]. They are public so the UI can render a completed
/// trial list directly; do not assign them from outside the session.
class AbxTrial {
  AbxTrial({required this.index, required this.hiddenX});

  /// Zero-based position of this trial inside its session.
  final int index;

  /// The stimulus X really is. Never [AbxStimulus.x].
  final AbxStimulus hiddenX;

  /// The listener's answer, or null while the trial is unanswered.
  AbxAnswer? answer;

  /// Whether [answer] matched [hiddenX], or null while unanswered.
  bool? correct;

  /// Whether this trial already carries an answer.
  bool get isAnswered => answer != null;

  @override
  String toString() => 'AbxTrial(index: $index, hiddenX: ${hiddenX.name}, '
      'answer: ${answer?.name}, correct: $correct)';
}

/// One ABX listening session: a fixed, balanced sequence of trials plus the
/// listener's answers and the resulting binomial statistics.
///
/// Trial order is built once in the constructor (and again on [reset]):
///
/// * exactly `(trials + 1) ~/ 2` hidden values are A and `trials ~/ 2` are B,
///   so an odd trial count puts the extra trial on A;
/// * no more than [maxIdenticalRun] identical values appear in a row;
/// * the order is deterministic for a given `seed` (or injected [Random]).
///
/// ## Verdict keys and thresholds
///
/// [verdictKey] returns one of five stable machine keys, meant to be looked up
/// in the localization layer rather than shown raw:
///
/// | key            | condition                                   |
/// | :------------- | :------------------------------------------ |
/// | `insufficient` | session not complete, or fewer than [minTrialsForVerdict] (10) trials |
/// | `chance`       | p >= 0.05                                   |
/// | `suggestive`   | 0.01 <= p < 0.05                            |
/// | `significant`  | 0.001 <= p < 0.01                           |
/// | `strong`       | p < 0.001                                   |
///
/// p is the one-sided binomial tail described on [pValue].
class AbxSession {
  /// Creates a session with [trials] trials (must be at least 1).
  ///
  /// [random] wins over [seed] when both are supplied. Without either the
  /// order is unseeded, which is what a real listening test wants. A session
  /// created from [seed] alone replays the same order on every [reset]; an
  /// injected [Random] simply keeps advancing.
  AbxSession({required int trials, Random? random, int? seed})
      : _seed = seed,
        _injectedRandom = random != null,
        _random = random ?? Random(seed) {
    _build(trials);
  }

  /// Minimum number of completed trials before any verdict other than
  /// [insufficientKey] is reported.
  static const int minTrialsForVerdict = 10;

  /// Longest tolerated run of identical hidden X values.
  static const int maxIdenticalRun = 4;

  /// p >= this value is reported as [chanceKey].
  static const double chanceThreshold = 0.05;

  /// p < [chanceThreshold] and >= this value is [suggestiveKey].
  static const double suggestiveThreshold = 0.01;

  /// p < [suggestiveThreshold] and >= this value is [significantKey].
  static const double significantThreshold = 0.001;

  /// Verdict keys. Stable strings: safe to persist and to localize by lookup.
  static const String insufficientKey = 'insufficient';
  static const String chanceKey = 'chance';
  static const String suggestiveKey = 'suggestive';
  static const String significantKey = 'significant';
  static const String strongKey = 'strong';

  static const int _shuffleAttempts = 32;
  static const double _ln2 = 0.6931471805599453;

  final int? _seed;
  final bool _injectedRandom;
  final List<AbxTrial> _trials = <AbxTrial>[];
  Random _random;
  int _cursor = 0;

  /// Number of planned trials in this session.
  int get trialCount => _trials.length;

  /// Read-only view of every trial, answered or not.
  List<AbxTrial> get trials => List<AbxTrial>.unmodifiable(_trials);

  /// How many trials have been answered so far.
  int get answeredCount => _cursor;

  /// How many answers matched the hidden stimulus.
  int get correctCount {
    var count = 0;
    for (final trial in _trials) {
      if (trial.correct ?? false) count++;
    }
    return count;
  }

  /// Whether every trial has been answered.
  bool get isComplete => _cursor >= _trials.length;

  /// The trial awaiting an answer.
  ///
  /// Throws a [StateError] once the session is complete.
  AbxTrial get current {
    if (isComplete) {
      throw StateError('Session complete: no trial is awaiting an answer.');
    }
    return _trials[_cursor];
  }

  /// Records [value] for the current trial and advances to the next one.
  ///
  /// Throws a [StateError] when the session is already complete, or when the
  /// current trial already carries an answer (a stale UI callback).
  void answer(AbxAnswer value) {
    if (isComplete) {
      throw StateError('Session complete: cannot answer trial $_cursor.');
    }
    final trial = _trials[_cursor];
    if (trial.answer != null) {
      throw StateError('Trial ${trial.index} already answered.');
    }
    trial.answer = value;
    trial.correct = (value == AbxAnswer.a) == (trial.hiddenX == AbxStimulus.a);
    _cursor++;
  }

  /// Clears all answers and rebuilds the trial plan.
  ///
  /// [trials] defaults to the current trial count. A session created from a
  /// seed reproduces the identical hidden sequence.
  void reset({int? trials}) {
    final next = trials ?? _trials.length;
    if (!_injectedRandom && _seed != null) {
      _random = Random(_seed);
    }
    _build(next);
  }

  /// Share of answered trials that were correct, in `[0, 1]`.
  ///
  /// Returns 0 when nothing has been answered yet.
  double get proportionCorrect => _cursor == 0 ? 0.0 : correctCount / _cursor;

  /// One-sided binomial p-value `P(X >= correctCount)` under the null
  /// hypothesis that each answer is a fair coin flip (`p = 0.5`), using
  /// `n = answeredCount`.
  ///
  /// This is a live value while the session runs; [verdictKey] only emits a
  /// verdict for completed sessions. The smaller tail is summed exactly in log
  /// space, so `C(n, k)` cannot overflow and `2^-n` cannot underflow, which
  /// keeps 500-trial sessions finite. When the answer is near 1 the lower tail
  /// is subtracted instead, which avoids adding hundreds of near-1 terms.
  double get pValue {
    final n = _cursor;
    if (n == 0) return 1.0;
    final k = correctCount;
    if (k <= 0) return 1.0;
    if (k >= n) return k > n ? 0.0 : exp(-n * _ln2);
    if (k * 2 <= n) return 1.0 - _binomialLowerTail(n, k - 1);
    return _binomialUpperTail(n, k);
  }

  /// `1 - pValue`.
  ///
  /// This is *not* a posterior probability that the listener can hear a
  /// difference; it is only the complement of [pValue].
  double get confidence => 1.0 - pValue;

  /// Stable machine key for the outcome, see the class documentation.
  String get verdictKey => isComplete
      ? verdictKeyForPValue(pValue, trials: answeredCount)
      : insufficientKey;

  /// Maps a p-value from a completed `trials`-trial session to a verdict key.
  ///
  /// Exposed so the thresholds can be tested exactly at their boundaries and
  /// reused by any UI that stores p-values separately.
  static String verdictKeyForPValue(double pValue, {required int trials}) {
    if (trials < minTrialsForVerdict || pValue.isNaN) {
      return insufficientKey;
    }
    if (pValue >= chanceThreshold) return chanceKey;
    if (pValue >= suggestiveThreshold) return suggestiveKey;
    if (pValue >= significantThreshold) return significantKey;
    return strongKey;
  }

  void _build(int trials) {
    if (trials < 1) {
      throw ArgumentError.value(trials, 'trials', 'must be at least 1');
    }
    final sequence = _planSequence(trials);
    assert(_longestRun(sequence) <= maxIdenticalRun);
    _trials
      ..clear()
      ..addAll(<AbxTrial>[
        for (var i = 0; i < sequence.length; i++)
          AbxTrial(index: i, hiddenX: sequence[i]),
      ]);
    _cursor = 0;
  }

  /// Builds the hidden-X sequence for [trials] trials.
  ///
  /// A plain shuffle of the exact multiset is tried first, bounded to
  /// [_shuffleAttempts] attempts. Long sessions almost never survive that
  /// check by chance, so the fallback is a seeded, run-aware fill rather than
  /// a fixed AAAA/BBBB pattern (a predictable order would leak X).
  List<AbxStimulus> _planSequence(int trials) {
    final aCount = (trials + 1) ~/ 2;
    final bCount = trials ~/ 2;
    for (var attempt = 0; attempt < _shuffleAttempts; attempt++) {
      final candidate = <AbxStimulus>[
        for (var i = 0; i < aCount; i++) AbxStimulus.a,
        for (var i = 0; i < bCount; i++) AbxStimulus.b,
      ]..shuffle(_random);
      if (_longestRun(candidate) <= maxIdenticalRun) return candidate;
    }
    return _constrainedFill(aCount, bCount);
  }

  /// Seeded fill that keeps every prefix extendable to a valid arrangement.
  ///
  /// A symbol is only eligible when appending it still leaves room for all
  /// remaining copies of both symbols under the run cap, which makes the
  /// result valid by construction and keeps it unpredictable.
  List<AbxStimulus> _constrainedFill(int aCount, int bCount) {
    final result = <AbxStimulus>[];
    var remainingA = aCount;
    var remainingB = bCount;
    AbxStimulus? last;
    var run = 0;

    bool fits(AbxStimulus symbol) {
      final isA = symbol == AbxStimulus.a;
      final remaining = isA ? remainingA : remainingB;
      final other = isA ? remainingB : remainingA;
      if (remaining <= 0) return false;
      final nextRun = symbol == last ? run + 1 : 1;
      if (nextRun > maxIdenticalRun) return false;
      final left = remaining - 1;
      // Same symbol: 4 - nextRun now, then up to 4 after each separator.
      if (left > (maxIdenticalRun - nextRun) + maxIdenticalRun * other) {
        return false;
      }
      // Other symbol: each of the remaining copies needs a separator slot.
      if (other > maxIdenticalRun * (left + 1)) return false;
      return true;
    }

    while (remainingA + remainingB > 0) {
      final canA = fits(AbxStimulus.a);
      final canB = fits(AbxStimulus.b);
      if (!canA && !canB) {
        throw StateError(
          'Cannot arrange $aCount A / $bCount B with runs <= $maxIdenticalRun.',
        );
      }
      final AbxStimulus pick;
      if (canA && canB) {
        pick = _random.nextBool() ? AbxStimulus.a : AbxStimulus.b;
      } else {
        pick = canA ? AbxStimulus.a : AbxStimulus.b;
      }
      result.add(pick);
      if (pick == AbxStimulus.a) {
        remainingA--;
      } else {
        remainingB--;
      }
      run = pick == last ? run + 1 : 1;
      last = pick;
    }
    return result;
  }

  static int _longestRun(List<AbxStimulus> sequence) {
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
}

/// `P(X <= j)` for `X ~ Binomial(n, 0.5)`, summed in log space.
double _binomialLowerTail(int n, int j) {
  // log C(n, 0) = 0, stepped with
  // log C(n, i + 1) = log C(n, i) + log(n - i) - log(i + 1).
  var logCombination = 0.0;
  var logTail = double.negativeInfinity;
  for (var i = 0; i <= j; i++) {
    logTail = _logAddExp(logTail, logCombination - n * AbxSession._ln2);
    logCombination += log((n - i).toDouble()) - log((i + 1).toDouble());
  }
  return exp(logTail);
}

/// `P(X >= k)` for `X ~ Binomial(n, 0.5)`, summed in log space.
double _binomialUpperTail(int n, int k) {
  // log C(n, k) from the multiplicative formula, then stepped upward with
  // log C(n, i + 1) = log C(n, i) + log(n - i) - log(i + 1).
  var logCombination = 0.0;
  for (var j = 1; j <= k; j++) {
    logCombination += log((n - k + j) / j);
  }
  var logTail = double.negativeInfinity;
  for (var i = k; i <= n; i++) {
    logTail = _logAddExp(logTail, logCombination - n * AbxSession._ln2);
    if (i < n) {
      logCombination += log((n - i).toDouble()) - log((i + 1).toDouble());
    }
  }
  return exp(logTail);
}

/// `log(exp(a) + exp(b))` without overflowing either term.
double _logAddExp(double a, double b) {
  if (a == double.negativeInfinity) return b;
  if (b == double.negativeInfinity) return a;
  final high = a > b ? a : b;
  final low = a > b ? b : a;
  return high + log(1 + exp(low - high));
}
