// lib/features/player/cubit/abx_cubit.dart
//
// UI glue for the blind ABX listening test (P2-10).
//
// The trial plan and the binomial statistics live in [AbxSession]; this cubit
// only sequences the two playback conditions, keeps the session alive across
// widget rebuilds, and restores the un-bypassed signal path when it closes.
//
// Conditions under test:
//   A = DSP bypassed (dry reference)
//   B = DSP active   (the processing chain under evaluation)
//   X = a hidden copy of exactly one of them, chosen by the trial plan.

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/services/abx_report_export.dart';
import '../../../domain/models/abx_session.dart';

/// Switches the live signal path between the two conditions under test.
///
/// `bypass == true` selects condition A, `false` selects condition B. Injected
/// so the cubit can be unit-tested without a `PlayerCubit` or a platform
/// channel; the screen wires it to
/// `PlayerCubit.setBypassCompare(bypass: ...)`.
typedef AbxConditionSwitch = Future<void> Function(bool bypass);

/// Whether a test can run right now: a track is loaded and DSP is active.
typedef AbxReadinessProbe = bool Function();

/// Immutable snapshot of one ABX run.
///
/// Deliberately plain (no freezed/code generation): the state carries only
/// counters and the current verdict, all derived from [AbxSession].
class AbxState {
  const AbxState({
    required this.canStart,
    required this.isRunning,
    required this.isComplete,
    required this.answeredCount,
    required this.total,
    required this.correctCount,
    required this.pValue,
    required this.verdictKey,
    this.lastAnswerCorrect,
    this.activeCondition,
  });

  /// Nothing started yet.
  const AbxState.idle({required int trials, required this.canStart})
      : isRunning = false,
        isComplete = false,
        answeredCount = 0,
        total = trials,
        correctCount = 0,
        pValue = 1.0,
        verdictKey = AbxSession.insufficientKey,
        lastAnswerCorrect = null,
        activeCondition = null;

  /// True when a song is loaded and DSP is on, i.e. [AbxCubit.start] may run.
  final bool canStart;

  /// True between [AbxCubit.start] and the last trial.
  final bool isRunning;

  /// True once every trial has been answered.
  final bool isComplete;

  /// Trials answered so far.
  final int answeredCount;

  /// Planned trials in this run.
  final int total;

  /// Answers that matched the hidden stimulus.
  final int correctCount;

  /// One-sided binomial p-value, see [AbxSession.pValue].
  final double pValue;

  /// Stable verdict key, see [AbxSession.verdictKey].
  final String verdictKey;

  /// Outcome of the most recent answer, or null before the first one.
  final bool? lastAnswerCorrect;

  /// The stimulus the listener last asked to hear, or null after an answer.
  final AbxStimulus? activeCondition;

  /// One-based trial number currently awaiting an answer.
  int get trialNumber => isComplete ? total : answeredCount + 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AbxState &&
          other.canStart == canStart &&
          other.isRunning == isRunning &&
          other.isComplete == isComplete &&
          other.answeredCount == answeredCount &&
          other.total == total &&
          other.correctCount == correctCount &&
          other.pValue == pValue &&
          other.verdictKey == verdictKey &&
          other.lastAnswerCorrect == lastAnswerCorrect &&
          other.activeCondition == activeCondition;

  @override
  int get hashCode => Object.hash(
        canStart,
        isRunning,
        isComplete,
        answeredCount,
        total,
        correctCount,
        pValue,
        verdictKey,
        lastAnswerCorrect,
        activeCondition,
      );

  @override
  String toString() => 'AbxState(trial: $answeredCount/$total, '
      'correct: $correctCount, p: $pValue, verdict: $verdictKey, '
      'running: $isRunning, complete: $isComplete)';
}

/// Drives one blind ABX run for the listening-test screen.
class AbxCubit extends Cubit<AbxState> {
  AbxCubit({
    required AbxConditionSwitch switchCondition,
    required AbxReadinessProbe isReady,
    int trials = defaultTrials,
    AbxSession Function(int trials)? sessionFactory,
  })  : _switchCondition = switchCondition,
        _isReady = isReady,
        _session = (sessionFactory ?? _createSession)(trials),
        super(AbxState.idle(trials: trials, canStart: isReady()));

  /// Planned trial count of a real run.
  ///
  /// Twelve trials put the all-correct p-value at 2^-12 = 0.00024, inside the
  /// `strong` band, while still finishing in a few minutes of listening.
  static const int defaultTrials = 12;

  final AbxConditionSwitch _switchCondition;
  final AbxReadinessProbe _isReady;
  final AbxSession _session;

  bool _started = false;
  AbxStimulus? _active;
  bool? _lastAnswerCorrect;

  /// The trial awaiting an answer, or null before [start] / once complete.
  AbxTrial? get current =>
      _started && !_session.isComplete ? _session.current : null;

  /// How many trials have been answered.
  int get answeredCount => _session.answeredCount;

  /// Planned trial count.
  int get total => _session.trialCount;

  /// How many answers matched the hidden stimulus.
  int get correctCount => _session.correctCount;

  /// Live one-sided binomial p-value.
  double get pValue => _session.pValue;

  /// Stable machine key for the verdict (`insufficient` while incomplete).
  String get verdictKey => _session.verdictKey;

  /// Read-only snapshot of every trial in the current session.
  List<AbxTrial> get trials => _session.trials;

  /// Builds a structured export report for the completed session.
  ///
  /// Throws [StateError] when the session is not yet complete.
  AbxReport buildReport({
    required AbxOutputDeviceInfo outputDevice,
    int? sampleRate,
    String? codec,
    String? trackTitle,
    String? trackArtist,
    int? sourceSampleRate,
    int? sourceBitDepth,
    DateTime? exportedAt,
  }) {
    return AbxReport.fromSession(
      _session,
      outputDevice: outputDevice,
      sampleRate: sampleRate,
      codec: codec,
      trackTitle: trackTitle,
      trackArtist: trackArtist,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      exportedAt: exportedAt,
    );
  }

  /// Starts the run. Returns false when there is nothing to listen to or DSP
  /// is off, in which case the screen keeps showing [AbxState.canStart] false.
  bool start() {
    if (_started && !_session.isComplete) return true;
    if (!_isReady()) {
      _publish();
      return false;
    }
    if (_session.isComplete) _session.reset();
    _started = true;
    _active = null;
    _lastAnswerCorrect = null;
    _publish();
    return true;
  }

  /// Plays one of the three stimuli by switching the live signal path.
  ///
  /// A and B are the two known conditions. X is not a third signal: it is a
  /// hidden copy of A or B, so the trial plan decides which condition X really
  /// is. Resolving it here is what keeps the test blind — mapping X straight
  /// to B would make every X audible as the DSP condition.
  Future<void> playCondition(AbxStimulus condition) async {
    if (!_started || _session.isComplete) return;
    final AbxStimulus resolved =
        condition == AbxStimulus.x ? _session.current.hiddenX : condition;
    _active = condition;
    // Drop the previous trial's verdict: it must not read as feedback on the
    // stimulus that is playing now.
    _lastAnswerCorrect = null;
    _publish();
    await _switchCondition(resolved == AbxStimulus.a);
  }

  /// Records an answer for the pending trial.
  ///
  /// Returns whether the answer was correct, or null when no trial is
  /// pending — before [start] or after the run is complete — so a completed
  /// session can never be graded a second time.
  bool? answer(AbxAnswer value) {
    if (!_started || _session.isComplete) return null;
    final AbxTrial trial = _session.current;
    _session.answer(value);
    final bool correct = trial.correct ?? false;
    _lastAnswerCorrect = correct;
    _active = null;
    _publish();
    return correct;
  }

  /// Rebuilds the plan and starts over (only while the app is still ready).
  Future<void> restart() async {
    _session.reset();
    _started = _isReady();
    _active = null;
    _lastAnswerCorrect = null;
    _publish();
    await _restore();
  }

  /// Re-evaluates [AbxState.canStart] after playback or DSP toggles.
  void refreshReadiness() {
    if (isClosed) return;
    if (_isReady() != state.canStart) _publish();
  }

  @override
  Future<void> close() async {
    // The bypass is a temporary A/B probe, never a persisted setting: leaving
    // the route must put the DSP chain back on the path.
    await _restore();
    await super.close();
  }

  Future<void> _restore() async {
    try {
      await _switchCondition(false);
    } catch (_) {
      // The bridge logs its own failures; a failed restore must not keep the
      // route from closing.
    }
  }

  void _publish() {
    if (isClosed) return;
    emit(AbxState(
      canStart: _isReady(),
      isRunning: _started && !_session.isComplete,
      isComplete: _session.isComplete,
      answeredCount: _session.answeredCount,
      total: _session.trialCount,
      correctCount: _session.correctCount,
      pValue: _session.pValue,
      verdictKey: _session.verdictKey,
      lastAnswerCorrect: _lastAnswerCorrect,
      activeCondition: _active,
    ));
  }
}

AbxSession _createSession(int trials) => AbxSession(trials: trials);
