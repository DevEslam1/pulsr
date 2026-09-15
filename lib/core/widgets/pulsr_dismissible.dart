// lib/core/widgets/pulsr_dismissible.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Two-swipe confirmation wrapper around [Dismissible].
///
/// Prevents accidental swipes during vertical scrolling or fast browsing.
/// - The first swipe primes confirmation, triggers subtle haptic feedback,
///   and displays a floating hint.
/// - A second swipe in the same direction within [confirmTimeout] confirms
///   and executes [onConfirm].
class PulsrDismissible extends StatefulWidget {
  /// Deliberate threshold to prevent micro-drags from triggering.
  static const double defaultThreshold = 0.60;

  static Map<DismissDirection, double> get thresholds => const {
        DismissDirection.startToEnd: defaultThreshold,
        DismissDirection.endToStart: defaultThreshold,
      };

  /// Default horizontal swipe gestures.
  static const DismissDirection direction = DismissDirection.horizontal;

  final Widget child;
  final DismissDirection dismissDirection;
  final Map<DismissDirection, double>? dismissThresholds;
  final Widget? background;
  final Widget? secondaryBackground;
  final Widget Function(BuildContext context, bool isConfirming)? backgroundBuilder;
  final Widget Function(BuildContext context, bool isConfirming)? secondaryBackgroundBuilder;
  final String? startToEndLabel;
  final String? endToStartLabel;
  final FutureOr<bool> Function(DismissDirection direction) onConfirm;
  final Duration confirmTimeout;
  final bool showToast;

  const PulsrDismissible({
    super.key,
    required this.child,
    required this.onConfirm,
    this.dismissDirection = DismissDirection.horizontal,
    this.dismissThresholds,
    this.background,
    this.secondaryBackground,
    this.backgroundBuilder,
    this.secondaryBackgroundBuilder,
    this.startToEndLabel,
    this.endToStartLabel,
    this.confirmTimeout = const Duration(milliseconds: 3500),
    this.showToast = true,
  });

  /// Helper to build an action background with consistent padding and icons.
  static Widget buildActionBackground({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required Color backgroundColor,
    required bool isConfirming,
    bool isEnd = false,
  }) {
    final effectiveLabel = isConfirming ? 'Confirm $label' : label;
    final effectiveIcon = isConfirming ? Icons.check_circle_outline_rounded : icon;

    return Container(
      color: backgroundColor,
      alignment: isEnd ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      padding: EdgeInsetsDirectional.only(
        start: isEnd ? 0 : 24,
        end: isEnd ? 24 : 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: isEnd
            ? [
                Text(
                  effectiveLabel,
                  style: TextStyle(
                    color: color,
                    fontWeight: isConfirming ? FontWeight.w900 : FontWeight.w700,
                    letterSpacing: isConfirming ? 0.2 : null,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(effectiveIcon, color: color),
              ]
            : [
                Icon(effectiveIcon, color: color),
                const SizedBox(width: 8),
                Text(
                  effectiveLabel,
                  style: TextStyle(
                    color: color,
                    fontWeight: isConfirming ? FontWeight.w900 : FontWeight.w700,
                    letterSpacing: isConfirming ? 0.2 : null,
                  ),
                ),
              ],
      ),
    );
  }

  /// Wraps a child with the safe two-swipe configuration.
  static Widget wrap({
    required Key key,
    required Widget child,
    required Widget background,
    required Widget secondaryBackground,
    required Future<bool> Function(DismissDirection) confirm,
    String? startToEndLabel,
    String? endToStartLabel,
  }) {
    return PulsrDismissible(
      key: key,
      background: background,
      secondaryBackground: secondaryBackground,
      onConfirm: confirm,
      startToEndLabel: startToEndLabel,
      endToStartLabel: endToStartLabel,
      child: child,
    );
  }

  @override
  State<PulsrDismissible> createState() => _PulsrDismissibleState();
}

class _PulsrDismissibleState extends State<PulsrDismissible> {
  DismissDirection? _pendingDirection;
  Timer? _pendingTimer;

  @override
  void dispose() {
    _pendingTimer?.cancel();
    super.dispose();
  }

  void _clearPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    if (mounted) {
      setState(() {
        _pendingDirection = null;
      });
    }
  }

  Future<bool> _handleConfirmDismiss(DismissDirection direction) async {
    if (_pendingDirection == direction) {
      // Confirmed on second swipe
      _pendingTimer?.cancel();
      _pendingTimer = null;
      HapticFeedback.mediumImpact();
      if (widget.showToast && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      final result = await widget.onConfirm(direction);
      if (mounted) {
        setState(() {
          _pendingDirection = null;
        });
      }
      return result;
    } else {
      // First swipe primes confirmation
      HapticFeedback.lightImpact();
      _pendingTimer?.cancel();
      _pendingTimer = Timer(widget.confirmTimeout, _clearPending);
      if (mounted) {
        setState(() {
          _pendingDirection = direction;
        });
      }

      if (widget.showToast && mounted) {
        final label = direction == DismissDirection.startToEnd
            ? widget.startToEndLabel
            : widget.endToStartLabel;

        final message = label != null && label.isNotEmpty
            ? 'Swipe again to confirm: $label'
            : 'Swipe again to confirm';

        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.swipe_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            duration: widget.confirmTimeout,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStartConfirming = _pendingDirection == DismissDirection.startToEnd;
    final isEndConfirming = _pendingDirection == DismissDirection.endToStart;

    final bg = widget.backgroundBuilder?.call(context, isStartConfirming) ?? widget.background;
    final secBg = widget.secondaryBackgroundBuilder?.call(context, isEndConfirming) ?? widget.secondaryBackground;

    return Dismissible(
      key: ValueKey('__pulsr_dismissible_${widget.key ?? identityHashCode(this)}'),
      direction: widget.dismissDirection,
      dismissThresholds: widget.dismissThresholds ?? PulsrDismissible.thresholds,
      confirmDismiss: _handleConfirmDismiss,
      background: bg,
      secondaryBackground: secBg,
      child: widget.child,
    );
  }
}
