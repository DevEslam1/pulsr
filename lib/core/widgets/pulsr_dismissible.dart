// lib/core/widgets/pulsr_dismissible.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../motion/pulsr_motion.dart';
import 'package:flutter/services.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';

/// Two-swipe confirmation wrapper for list tiles and cards.
///
/// Interaction model:
/// - First swipe: Slides the tile to the middle ([middleRatio], default 50%),
///   revealing and showing the action with primed confirmation and light haptic feedback.
/// - Second swipe (in the same direction) or tapping the revealed action confirms
///   and executes [onConfirm].
/// - If [onConfirm] returns `false`, the tile smoothly glides back to closed position.
/// - If [onConfirm] returns `true`, the tile collapses its height smoothly (dismisses).
/// - Tapping the shifted tile, scrolling the list, or timing out cancels and closes back to 0.
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
  final double middleRatio;

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
    this.showToast = false,
    this.middleRatio = 0.50,
  });

  /// Helper to build an action background with consistent padding, shape, and icons.
  static Widget buildActionBackground({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required Color backgroundColor,
    required bool isConfirming,
    bool isEnd = false,
    EdgeInsetsGeometry? margin,
    BorderRadiusGeometry? borderRadius,
  }) {
    final effectiveLabel = isConfirming ? 'Confirm $label' : label;
    final effectiveIcon = isConfirming ? Icons.check_circle_outline_rounded : icon;

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius ?? BorderRadius.circular(AppRadii.r16),
      ),
      alignment: isEnd ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      padding: EdgeInsetsDirectional.only(
        start: isEnd ? 0 : 20,
        end: isEnd ? 20 : 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: isEnd
            ? [
                Flexible(
                  child: Text(
                    effectiveLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: isConfirming ? FontWeight.w900 : FontWeight.w700,
                      letterSpacing: isConfirming ? 0.2 : null,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(effectiveIcon, color: color),
              ]
            : [
                Icon(effectiveIcon, color: color),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    effectiveLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: isConfirming ? FontWeight.w900 : FontWeight.w700,
                      letterSpacing: isConfirming ? 0.2 : null,
                    ),
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

class _PulsrDismissibleState extends State<PulsrDismissible>
    with TickerProviderStateMixin {
  /// Track the currently opened dismissible tile across the app so opening one closes another.
  static _PulsrDismissibleState? _activeOpenState;

  late final AnimationController _offsetController;
  late final AnimationController _resizeController;
  late final Animation<double> _resizeAnimation;

  DismissDirection? _pendingDirection;
  Timer? _pendingTimer;
  ScrollPosition? _scrollPosition;

  double _dragStartOffset = 0.0;
  double _itemWidth = 1.0;
  bool _isDismissed = false;

  bool get _canStartToEnd =>
      (widget.dismissDirection == DismissDirection.horizontal ||
          widget.dismissDirection == DismissDirection.startToEnd) &&
      (widget.backgroundBuilder != null || widget.background != null);

  bool get _canEndToStart =>
      (widget.dismissDirection == DismissDirection.horizontal ||
          widget.dismissDirection == DismissDirection.endToStart) &&
      (widget.secondaryBackgroundBuilder != null ||
          widget.secondaryBackground != null);

  @override
  void initState() {
    super.initState();
    _offsetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      lowerBound: -1.0,
      upperBound: 1.0,
      value: 0.0,
    );

    _resizeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 0.0,
    );

    _resizeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _resizeController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _offsetController.duration = context.motionMs(250);
    _resizeController.duration = context.motionMs(260);
    final newPosition = Scrollable.maybeOf(context)?.position;
    if (_scrollPosition != newPosition) {
      _scrollPosition?.removeListener(_handleScroll);
      _scrollPosition = newPosition;
      _scrollPosition?.addListener(_handleScroll);
    }
  }

  void _handleScroll() {
    if (_pendingDirection != null && mounted) {
      _close();
    }
  }

  @override
  void dispose() {
    if (_activeOpenState == this) {
      _activeOpenState = null;
    }
    _pendingTimer?.cancel();
    _scrollPosition?.removeListener(_handleScroll);
    _offsetController.dispose();
    _resizeController.dispose();
    super.dispose();
  }

  void _close() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    if (_activeOpenState == this) {
      _activeOpenState = null;
    }
    if (mounted) {
      setState(() {
        _pendingDirection = null;
      });
      _offsetController.animateTo(
        0.0,
        duration: context.motionMs(250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _snapToMiddle(DismissDirection direction) {
    final target = direction == DismissDirection.startToEnd
        ? widget.middleRatio
        : -widget.middleRatio;

    HapticFeedback.lightImpact();

    if (_activeOpenState != null && _activeOpenState != this) {
      _activeOpenState?._close();
    }
    _activeOpenState = this;

    _pendingTimer?.cancel();
    _pendingTimer = Timer(widget.confirmTimeout, _close);

    if (mounted) {
      setState(() {
        _pendingDirection = direction;
      });
      _offsetController.animateTo(
        target,
        duration: context.motionMs(260),
        curve: Curves.easeOutCubic,
      );
    }

    if (widget.showToast && mounted) {
      final label = direction == DismissDirection.startToEnd
          ? widget.startToEndLabel
          : widget.endToStartLabel;

      final message = label != null && label.isNotEmpty
          ? 'Swipe again or tap to confirm: $label'
          : 'Swipe again or tap to confirm';

      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.swipe_rounded, size: 18, color: Colors.white),
              const SizedBox(width: AppSpacing.xs),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.r10)),
        ),
      );
    }
  }

  Future<void> _executeConfirm(DismissDirection direction) async {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    if (_activeOpenState == this) {
      _activeOpenState = null;
    }

    HapticFeedback.mediumImpact();

    if (widget.showToast && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    final targetOffset = direction == DismissDirection.startToEnd ? 1.0 : -1.0;

    await _offsetController.animateTo(
      targetOffset,
      duration: context.motionMs(200),
      curve: Curves.easeOutCubic,
    );

    if (!mounted) return;

    final shouldDismiss = await widget.onConfirm(direction);

    if (!mounted) return;

    if (shouldDismiss == true) {
      await _resizeController.forward();
      if (mounted) {
        setState(() {
          _isDismissed = true;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _pendingDirection = null;
        });
        await _offsetController.animateTo(
          0.0,
          duration: context.motionMs(320),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _pendingTimer?.cancel();
    _pendingTimer = null;

    if (_activeOpenState != null && _activeOpenState != this) {
      _activeOpenState?._close();
    }

    _dragStartOffset = _offsetController.value;
    _offsetController.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final width = _itemWidth > 0
        ? _itemWidth
        : (context.size?.width ?? MediaQuery.sizeOf(context).width);

    final delta = details.primaryDelta! / width;
    double newOffset = _offsetController.value + delta;

    if (!_canStartToEnd && newOffset > 0) {
      newOffset = 0;
    }
    if (!_canEndToStart && newOffset < 0) {
      newOffset = 0;
    }

    if (_dragStartOffset == 0.0) {
      // First swipe: apply rubber-band damping beyond middleRatio
      if (newOffset > widget.middleRatio) {
        final excess = newOffset - widget.middleRatio;
        newOffset = widget.middleRatio + excess * 0.15;
        newOffset = newOffset.clamp(0.0, widget.middleRatio + 0.08);
      } else if (newOffset < -widget.middleRatio) {
        final excess = newOffset - (-widget.middleRatio);
        newOffset = -widget.middleRatio + excess * 0.15;
        newOffset = newOffset.clamp(-widget.middleRatio - 0.08, 0.0);
      }
    } else {
      // Second swipe or dragging from middle position
      newOffset = newOffset.clamp(-1.0, 1.0);
    }

    _offsetController.value = newOffset;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final width = _itemWidth > 0
        ? _itemWidth
        : (context.size?.width ?? MediaQuery.sizeOf(context).width);
    final velocity = (details.primaryVelocity ?? 0.0) / width;
    final current = _offsetController.value;

    if (_dragStartOffset == 0.0) {
      // --- First swipe (starts at 0.0) ---
      if (current > 0.15 || velocity > 0.3) {
        if (_canStartToEnd) {
          _snapToMiddle(DismissDirection.startToEnd);
          return;
        }
      } else if (current < -0.15 || velocity < -0.3) {
        if (_canEndToStart) {
          _snapToMiddle(DismissDirection.endToStart);
          return;
        }
      }
      _close();
    } else {
      // --- Second swipe (starts at middleRatio) ---
      final isAtStartMiddle = _dragStartOffset > 0;
      if (isAtStartMiddle) {
        if (current > widget.middleRatio + 0.05 || velocity > 0.2) {
          _executeConfirm(DismissDirection.startToEnd);
        } else if (current < widget.middleRatio - 0.15 || velocity < -0.3) {
          _close();
        } else {
          _snapToMiddle(DismissDirection.startToEnd);
        }
      } else {
        if (current < -widget.middleRatio - 0.05 || velocity < -0.2) {
          _executeConfirm(DismissDirection.endToStart);
        } else if (current > -widget.middleRatio + 0.15 || velocity > 0.3) {
          _close();
        } else {
          _snapToMiddle(DismissDirection.endToStart);
        }
      }
    }
  }

  void _onHorizontalDragCancel() {
    if (_dragStartOffset == 0.0) {
      _close();
    } else {
      _snapToMiddle(
        _dragStartOffset > 0
            ? DismissDirection.startToEnd
            : DismissDirection.endToStart,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDismissed) {
      return const SizedBox.shrink();
    }

    final hasGestures = _canStartToEnd || _canEndToStart;
    final isStartConfirming = _pendingDirection == DismissDirection.startToEnd;
    final isEndConfirming = _pendingDirection == DismissDirection.endToStart;

    final bg = widget.backgroundBuilder?.call(context, isStartConfirming) ??
        widget.background;
    final secBg = widget.secondaryBackgroundBuilder
            ?.call(context, isEndConfirming) ??
        widget.secondaryBackground;

    return SizeTransition(
      sizeFactor: _resizeAnimation,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _itemWidth = constraints.maxWidth;

          final content = Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Background layer (only clipped to the revealed area)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _offsetController,
                  builder: (context, _) {
                    final offset = _offsetController.value;
                    if (offset == 0.0) return const SizedBox.shrink();

                    final isStart = offset > 0;
                    final bgWidget = isStart ? bg : secBg;
                    if (bgWidget == null) return const SizedBox.shrink();

                    return ClipRRect(
                      clipper: _SwipeBackgroundClipper(offset),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_pendingDirection != null) {
                            _executeConfirm(_pendingDirection!);
                          }
                        },
                        child: bgWidget,
                      ),
                    );
                  },
                ),
              ),
              // Sliding child layer
              AnimatedBuilder(
                animation: _offsetController,
                builder: (context, _) {
                  final offset = _offsetController.value;
                  final isRevealed = _pendingDirection != null;

                  return Transform.translate(
                    offset: Offset(offset * _itemWidth, 0),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: isRevealed ? _close : null,
                      child: IgnorePointer(
                        ignoring: isRevealed,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.r16),
                          child: widget.child,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );

          if (!hasGestures) {
            return content;
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            onHorizontalDragCancel: _onHorizontalDragCancel,
            child: content,
          );
        },
      ),
    );
  }
}

class _SwipeBackgroundClipper extends CustomClipper<RRect> {
  final double offset;
  static const double radius = 16.0;

  const _SwipeBackgroundClipper(this.offset);

  @override
  RRect getClip(Size size) {
    if (offset > 0) {
      final width = (size.width * offset).clamp(0.0, size.width);
      return RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, width, size.height),
        const Radius.circular(radius),
      );
    } else if (offset < 0) {
      final width = (size.width * (-offset)).clamp(0.0, size.width);
      return RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - width, 0, width, size.height),
        const Radius.circular(radius),
      );
    }
    return RRect.zero;
  }

  @override
  bool shouldReclip(covariant _SwipeBackgroundClipper oldClipper) {
    return oldClipper.offset != offset;
  }
}
