// lib/features/player/presentation/themes/painters/platter_scrub.dart
//
// Shared platter-scrub behaviour for the two analog decks (vinyl turntable and
// CD jewel stage). Both decks previously carried byte-identical copies of this
// state machine: the angular delta maths, the 12-detent haptic ladder and the
// tonearm sway are physical platter properties, so they live here once and are
// parameterised only by how much programme material one revolution carries.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import '../../../../../core/theme/aura_theme.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/l10n_extensions.dart';
import '../../../../../core/utils/pulsr_haptics.dart';
import '../../../cubit/player_cubit.dart';
import '../../../cubit/player_state.dart';

/// Circular drag-to-scrub state for a spinning platter.
///
/// A drag is accumulated as fractional revolutions so the deck can rotate the
/// disc with the finger, then converted to a seek delta when the finger lifts.
/// The controller is a [ChangeNotifier] rather than a widget's setState so the
/// deck can rebuild only the transform, the sway and the delta pill instead of
/// the whole stage on every drag frame.
class PlatterScrubController extends ChangeNotifier {
  PlatterScrubController({required this.secondsPerTurn});

  /// One revolution of a 33⅓ rpm record carries 1.8 s of programme material,
  /// so dragging the platter matches the speed the disc actually spins at.
  static const double vinylSecondsPerTurn = 1.8;

  /// The CD deck scrubs coarser: one revolution ≈ 4 s, which is what the
  /// booklet-sized disc feels like when dragged by hand without a spindle.
  static const double cdSecondsPerTurn = 4.0;

  /// A haptic detent every twelfth of a revolution, matching the twelve
  /// strobe/print marks the decks already draw around the platter.
  static const int _detentsPerTurn = 12;

  /// Programmme material carried by one full revolution of this platter.
  final double secondsPerTurn;

  double _turns = 0.0;
  double? _lastAngle;
  double _sway = 0.0;
  bool _isScrubbing = false;

  bool get isScrubbing => _isScrubbing;

  /// Fractional revolutions dragged so far; the deck adds this to the rotation
  /// animation's phase so the disc follows the finger.
  double get turnOffset => _turns;

  /// Radians the tonearm kicks against the groove while the platter is dragged.
  double get tonearmSway => _sway;

  /// Signed distance the current drag will seek by when it is committed.
  Duration get scrubDelta =>
      Duration(milliseconds: (_turns * secondsPerTurn * 1000).round());

  /// Begins a drag at [localPosition] inside a platter [diameter] wide.
  void start(Offset localPosition, double diameter) {
    _lastAngle = _angleAt(localPosition, diameter);
    _turns = 0.0;
    _sway = 0.0;
    _isScrubbing = true;
    notifyListeners();
  }

  /// Accumulates the angular delta between two drag samples.
  void update(Offset localPosition, double diameter) {
    if (!_isScrubbing) return;
    final angle = _angleAt(localPosition, diameter);
    final previousAngle = _lastAngle;
    _lastAngle = angle;
    if (previousAngle == null) return;

    var delta = angle - previousAngle;
    // Wrap the delta at ±π so a drag across the 3 o'clock seam keeps counting
    // in the direction the finger actually travelled instead of jumping a turn.
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;

    final previousDetent = (_turns * _detentsPerTurn).floor();
    _turns += delta / (2 * math.pi);
    if ((_turns * _detentsPerTurn).floor() != previousDetent) {
      PulsrHaptics.selection();
    }
    // The arm is dragged by the groove, so it swings against the drag rather
    // than snapping to a fixed angle.
    _sway = (delta * 0.15).clamp(-0.06, 0.06);
    notifyListeners();
  }

  /// Commits the drag as a seek clamped to the track, then parks the platter.
  ///
  /// [position] and [duration] are read at commit time (not at drag start) so a
  /// drag that spans a track change still seeks relative to what is playing.
  void end({
    required Duration position,
    required Duration duration,
    required ValueChanged<Duration> onSeek,
  }) {
    if (_isScrubbing && duration > Duration.zero) {
      final target = position + scrubDelta;
      onSeek(
        Duration(
            milliseconds:
                target.inMilliseconds.clamp(0, duration.inMilliseconds)),
      );
    }
    cancel();
  }

  /// Abandons the drag without seeking (pointer cancel, track change).
  void cancel() {
    if (!_isScrubbing && _turns == 0.0 && _sway == 0.0) return;
    _isScrubbing = false;
    _lastAngle = null;
    _turns = 0.0;
    _sway = 0.0;
    notifyListeners();
  }

  static double _angleAt(Offset localPosition, double diameter) {
    final radius = diameter / 2;
    return math.atan2(localPosition.dy - radius, localPosition.dx - radius);
  }
}

/// Publishes a platter hit area as an accessible seek slider.
///
/// Dragging a record in circles is not something a screen reader can perform,
/// so the same surface also answers discrete increase/decrease actions of
/// ±10 s. The announced value is quantised to whole seconds — the same idea as
/// the 120-step selectors the decks use for progress — so this wrapper rebuilds
/// at most once per second, and [child] is passed through as a stable widget
/// instance so the platter itself is never rebuilt by a position tick.
class PlatterScrubSemantics extends StatelessWidget {
  final PlayerCubit cubit;
  final Widget child;

  const PlatterScrubSemantics({
    super.key,
    required this.cubit,
    required this.child,
  });

  static const Duration _seekStep = Duration(seconds: 10);

  @override
  Widget build(BuildContext context) {
    return BlocSelector<PlayerCubit, PlayerState, ({int elapsed, int total})>(
      selector: (state) => (
        elapsed: state.position.inSeconds,
        total: state.duration.inSeconds,
      ),
      builder: (context, span) {
        final total = math.max(span.total, 0);
        String readout(int seconds) =>
            '${Formatters.formatDuration(Duration(seconds: seconds))} / '
            '${Formatters.formatDuration(Duration(seconds: total))}';

        return Semantics(
          // A merge boundary, not decoration: without `container` the deck's
          // stage node absorbs the slider flags, so assistive tech is handed one
          // node that is a slider, an image and a tap target at once.
          container: true,
          slider: true,
          label: context.l10n.seekLabel,
          value: readout(span.elapsed.clamp(0, total)),
          increasedValue:
              readout((span.elapsed + _seekStep.inSeconds).clamp(0, total)),
          decreasedValue:
              readout((span.elapsed - _seekStep.inSeconds).clamp(0, total)),
          onIncrease: () => _seekBy(cubit, _seekStep),
          onDecrease: () => _seekBy(cubit, -_seekStep),
          // The disc's own artwork node is described by the deck's image node,
          // and the drag handlers publish nothing useful to assistive tech.
          excludeSemantics: true,
          child: child,
        );
      },
    );
  }

  static void _seekBy(PlayerCubit cubit, Duration delta) {
    final state = cubit.state;
    final target = state.position + delta;
    if (target <= Duration.zero) {
      cubit.seek(Duration.zero);
      return;
    }
    final duration = state.duration;
    cubit.seek(
      duration > Duration.zero && target > duration ? duration : target,
    );
  }
}

/// Floating "+1.2s" readout shown while a platter is being dragged.
///
/// Purely decorative: the platter's slider node already announces the seek
/// position, so the pill is excluded from semantics, and it is removed from the
/// tree rather than merely hidden once the drag ends.
class PlatterScrubPill extends StatelessWidget {
  final PlatterScrubController controller;
  final Color activeColor;

  const PlatterScrubPill({
    super.key,
    required this.controller,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final surface = context.playerSurfacePalette;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (!controller.isScrubbing) return const SizedBox.shrink();
          final seconds = controller.scrubDelta.inMilliseconds / 1000;
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.s6,
            ),
            decoration: BoxDecoration(
              color: surface.tapeWindow.withValues(alpha: 0.90),
              borderRadius: AppRadii.full,
              border: Border.all(
                color: activeColor.withValues(alpha: 0.65),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.40),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  seconds >= 0
                      ? Icons.rotate_right_rounded
                      : Icons.rotate_left_rounded,
                  size: 15,
                  color: activeColor,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  '${seconds >= 0 ? '+' : ''}${seconds.toStringAsFixed(1)}s',
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w800,
                    color: surface.highContrastInk,
                    letterSpacing: AppTracking.label,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
