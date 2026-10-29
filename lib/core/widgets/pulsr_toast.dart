import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../constants/app_radii.dart';
import '../constants/app_typography.dart';
import '../di/injection.dart';
import '../motion/pulsr_motion.dart';
import '../services/sound_feedback_service.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';
import 'pulsr_dock_tracker.dart';
import 'pulsr_modal_tracker.dart';

/// {@category DesignSystem}
enum PulsrToastPosition {
  aboveDock,
  center,
  top,
}

class PulsrToastAction {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  const PulsrToastAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });
}

/// Modern, floating SnackBar notification styled in Pulsr's signature glass aesthetic,
/// matching the mini player and bottom dock layout.
///
/// Dynamically floats directly above the mini player (or bottom nav bar), adapting
/// automatically to track presence, dock modes, modal states, and software keyboards.
class PulsrToast {
  static OverlayEntry? _activeEntry;
  static _ToastWidgetState? _activeWidgetState;

  /// Hides any currently visible toast / snackbar immediately with animation.
  static void hide() {
    final state = _activeWidgetState;
    if (state != null && state.mounted) {
      state.dismiss();
      return;
    }
    // The entry can already be detached (its overlay disposed, or a concurrent
    // dismiss completed); remove() throws in that state, so never call it
    // unguarded — and always clear both statics.
    try {
      _activeEntry?.remove();
    } catch (_) {
      // Already detached: nothing to remove.
    }
    _activeEntry = null;
    _activeWidgetState = null;
  }

  /// Displays a floating SnackBar positioned above the mini player or top/center.
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 3200),
    bool isError = false,
    bool isSuccess = false,
    String? actionLabel,
    VoidCallback? onActionPressed,
    PulsrToastAction? action,
    PulsrToastPosition position = PulsrToastPosition.aboveDock,
    VoidCallback? onDismiss,
    double? bottomOffset,
  }) {
    // A failure cascade (network drop, bot block) fires the *same* message
    // once per retry/skip, and each event used to tear the banner down and
    // re-insert it — one visible "banner show" plus a heavy haptic and error
    // cue per event. An identical message that is still on screen is the same
    // banner: keep it mounted and extend its auto-dismiss window so it stays
    // up while the errors keep flowing and lingers a full duration after the
    // last one.
    final activeState = _activeWidgetState;
    if (_activeEntry != null &&
        activeState != null &&
        activeState.mounted &&
        !activeState.isDismissing &&
        activeState.widget.message == message) {
      activeState.refresh();
      return;
    }

    if (_activeEntry != null) {
      try {
        _activeEntry?.remove();
      } catch (_) {}
      _activeEntry = null;
      _activeWidgetState = null;
    }

    try {
      if (isError) {
        HapticFeedback.heavyImpact();
        SoundFeedbackService.playError();
      } else if (isSuccess) {
        HapticFeedback.mediumImpact();
        SoundFeedbackService.playSuccess();
      } else {
        HapticFeedback.lightImpact();
      }
    } catch (_) {}

    // `Overlay.of` throws when `context` has no Overlay ancestor — e.g. the
    // root Navigator's own context, whose Overlay is a *child* of that
    // context, not an ancestor. Prefer a nullable lookup and fall back to
    // the root navigator's overlay state.
    final OverlayState? overlayState =
        Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;
    final p = context.palette;

    final effectiveAction = action ??
        ((actionLabel != null && onActionPressed != null)
            ? PulsrToastAction(label: actionLabel, onPressed: onActionPressed)
            : (actionLabel != null
                ? PulsrToastAction(label: actionLabel, onPressed: () {})
                : null));

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        key: UniqueKey(),
        message: message,
        title: title,
        icon: icon,
        isError: isError,
        isSuccess: isSuccess,
        action: effectiveAction,
        position: position,
        palette: p,
        customBottomOffset: bottomOffset,
        duration: duration,
        onDismiss: () {
          try {
            entry.remove();
          } catch (_) {}
          if (_activeEntry == entry) {
            _activeEntry = null;
            _activeWidgetState = null;
          }
          onDismiss?.call();
        },
        onStateCreated: (state) {
          _activeWidgetState = state;
        },
      ),
    );

    _activeEntry = entry;
    try {
      overlayState.insert(entry);
    } catch (_) {
      _activeEntry = null;
      _activeWidgetState = null;
      return;
    }
  }
}

/// Alias for [PulsrToast] representing its SnackBar architecture.
typedef PulsrSnackBar = PulsrToast;

class _ToastWidget extends StatefulWidget {
  final String message;
  final String? title;
  final IconData? icon;
  final bool isError;
  final bool isSuccess;
  final PulsrToastAction? action;
  final PulsrToastPosition position;
  final PulsrPalette palette;
  final double? customBottomOffset;
  final Duration duration;
  final VoidCallback onDismiss;
  final ValueChanged<_ToastWidgetState>? onStateCreated;

  const _ToastWidget({
    super.key,
    required this.message,
    this.title,
    this.icon,
    required this.isError,
    required this.isSuccess,
    this.action,
    this.position = PulsrToastPosition.aboveDock,
    required this.palette,
    this.customBottomOffset,
    required this.duration,
    required this.onDismiss,
    this.onStateCreated,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  Timer? _autoDismissTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated?.call(this);

    _animController = AnimationController(
      vsync: this,
      duration: PulsrMotion.layout,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    final initialOffset = widget.position == PulsrToastPosition.top
        ? const Offset(0.0, -0.40)
        : (widget.position == PulsrToastPosition.center
            ? const Offset(0.0, 0.15)
            : const Offset(0.0, 0.40));

    _slideAnimation = Tween<Offset>(
      begin: initialOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();
    _startAutoDismissTimer();
  }

  void _startAutoDismissTimer() {
    var effective = widget.duration;
    if (widget.action != null) {
      effective += const Duration(seconds: 2);
    }
    if (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
        .accessibleNavigation) {
      effective += const Duration(seconds: 4);
    }
    _autoDismissTimer = Timer(effective, () {
      if (mounted) dismiss();
    });
  }

  /// True once [dismiss] has started the exit animation, so [PulsrToast.show]
  /// never "extends" a toast that is already animating away.
  bool get isDismissing => _isDismissing;

  /// Restarts the auto-dismiss countdown without re-animating or replaying the
  /// haptic/sound cue. Called when an identical message arrives while this
  /// toast is still visible.
  void refresh() {
    if (_isDismissing) return;
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    _startAutoDismissTimer();
  }

  void dismiss() {
    if (_isDismissing) return;
    _isDismissing = true;
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;

    if (!mounted) {
      widget.onDismiss();
      return;
    }

    _animController.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    }).catchError((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animController.duration = context.motionMs(260);
    if (!context.motionEnabled) _animController.value = 1.0;
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    _animController.dispose();
    super.dispose();
  }

  double _calculateBottomOffset(BuildContext context) {
    if (widget.customBottomOffset != null) {
      return widget.customBottomOffset!;
    }

    final bottomSafeArea = MediaQuery.maybePaddingOf(context)?.bottom ?? 0.0;
    final keyboardInset = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0.0;
    final isLandscape =
        MediaQuery.maybeOrientationOf(context) == Orientation.landscape;
    final isTablet = Adaptive.isTablet(context);

    // 1. If software keyboard is active, position above it
    if (keyboardInset > 0) {
      return keyboardInset + 14.0;
    }

    // 2. If a dialog or bottom sheet modal is open, bottom dock is slid away
    if (PulsrModalTracker.isModalOpen.value) {
      return bottomSafeArea + 14.0;
    }

    // 3. If Now Playing full-screen route is active, bottom dock is not visible
    if (PulsrDockTracker.isNowPlayingOpen.value) {
      return bottomSafeArea + 14.0;
    }

    // 4. In landscape phone mode, the dock is always a single compact bar (or hidden)
    if (isLandscape && !isTablet) {
      final liveDockHeight = PulsrDockTracker.dockHeight.value;
      // In phone landscape, dock height is at most ~64dp. Cap it so stale portrait metrics can't shoot it up
      final effectiveDock =
          liveDockHeight > 0 ? math.min(liveDockHeight, 68.0) : 64.0;
      return effectiveDock + bottomSafeArea + 8.0;
    }

    // 5. Use live height reported by PulsrDockTracker
    final liveDockHeight = PulsrDockTracker.dockHeight.value;
    if (liveDockHeight > 0) {
      return liveDockHeight + bottomSafeArea + 12.0;
    }

    // 6. Fallback inspection if dock has not reported yet
    bool hasSong = false;
    try {
      if (getIt.isRegistered<PlayerCubit>()) {
        hasSong = getIt<PlayerCubit>().state.currentSong != null;
      }
    } catch (_) {}

    final fallbackHeight =
        hasSong ? (isTablet ? 166.0 : 158.0) : (isTablet ? 82.0 : 74.0);
    return fallbackHeight + bottomSafeArea + 12.0;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final statusColor =
        widget.isError ? p.error : (widget.isSuccess ? p.success : p.accent);

    final effectiveIcon = widget.icon ??
        (widget.isError
            ? Icons.error_outline_rounded
            : (widget.isSuccess
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded));

    final isTablet = Adaptive.isTablet(context);
    final isLandscape =
        MediaQuery.maybeOrientationOf(context) == Orientation.landscape;
    final isCompactLandscape = isLandscape && !isTablet;

    final double maxDockWidth =
        isTablet ? 480.0 : (isCompactLandscape ? 380.0 : 420.0);
    final snackbarRadius = isTablet
        ? AppRadii.r24All
        : (isCompactLandscape ? AppRadii.r16All : AppRadii.r20All);

    return AnimatedBuilder(
      animation: Listenable.merge([
        PulsrDockTracker.changeNotifier,
        PulsrModalTracker.isModalOpen,
      ]),
      builder: (context, _) {
        final bottomOffset = _calculateBottomOffset(context);
        final Alignment alignment;
        final EdgeInsetsDirectional padding;

        switch (widget.position) {
          case PulsrToastPosition.top:
            alignment = Alignment.topCenter;
            padding = EdgeInsetsDirectional.only(
              top: (MediaQuery.maybePaddingOf(context)?.top ?? 24.0) + 16.0,
              start: isTablet ? 24.0 : 14.0,
              end: isTablet ? 24.0 : 14.0,
            );
            break;
          case PulsrToastPosition.center:
            alignment = Alignment.center;
            padding = EdgeInsetsDirectional.only(
              start: isTablet ? 24.0 : 14.0,
              end: isTablet ? 24.0 : 14.0,
            );
            break;
          case PulsrToastPosition.aboveDock:
            alignment = Alignment.bottomCenter;
            padding = EdgeInsetsDirectional.only(
              bottom: bottomOffset,
              start: isTablet ? 24.0 : 14.0,
              end: isTablet ? 24.0 : 14.0,
            );
            break;
        }

        return Align(
          alignment: alignment,
          child: AnimatedPadding(
            duration: context.motionMs(260),
            curve: Curves.easeOutCubic,
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxDockWidth),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Material(
                    color: Colors.transparent,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragEnd: (details) {
                        if ((details.primaryVelocity ?? 0) > 80) {
                          HapticFeedback.lightImpact();
                          dismiss();
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        if ((details.primaryVelocity ?? 0).abs() > 80) {
                          HapticFeedback.lightImpact();
                          dismiss();
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: snackbarRadius,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: p.isDark ? 0.30 : 0.08),
                              blurRadius: 10,
                              spreadRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: snackbarRadius,
                          child: Semantics(
                            liveRegion: true,
                            container: true,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: snackbarRadius,
                                color: p.surfaceContainerHigh,
                                border: Border.all(
                                  color: widget.isError
                                      ? p.error
                                      : (widget.isSuccess
                                          ? p.success
                                          : p.hairline),
                                  width: 1.0,
                                ),
                              ),
                                  padding: EdgeInsetsDirectional.fromSTEB(
                                    isCompactLandscape ? 10 : 12,
                                    isCompactLandscape ? 7 : 9,
                                    isCompactLandscape ? 8 : 10,
                                    isCompactLandscape ? 7 : 9,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Leading Status Badge
                                      Container(
                                        width: isCompactLandscape ? 30 : 32,
                                        height: isCompactLandscape ? 30 : 32,
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(
                                              alpha: p.isDark ? 0.18 : 0.12),
                                          borderRadius: BorderRadius.circular(
                                              isCompactLandscape ? 9 : 10),
                                          border: Border.all(
                                            color: statusColor.withValues(
                                                alpha: 0.24),
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            effectiveIcon,
                                            color: statusColor,
                                            size: isCompactLandscape ? 16 : 18,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),

                                      // Text Content
                                      Flexible(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (widget.title != null) ...[
                                              Text(
                                                widget.title!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: p.textPrimary,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: isCompactLandscape
                                                      ? 12.0
                                                      : AppFontSize.bodySmall,
                                                ),
                                              ),
                                              const SizedBox(height: 1),
                                            ],
                                            Text(
                                              widget.message,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: widget.title != null
                                                    ? p.textSecondary
                                                    : p.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: isCompactLandscape
                                                    ? 12.0
                                                    : AppFontSize.bodySmall,
                                                height: 1.22,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Optional Action Button
                                      if (widget.action != null) ...[
                                        const SizedBox(width: 8),
                                        Semantics(
                                          button: true,
                                          label: widget.action!.label,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                minWidth: 48, minHeight: 48),
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                HapticFeedback.lightImpact();
                                                widget.action!.onPressed();
                                                dismiss();
                                              },
                                              child: Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: isCompactLandscape
                                                      ? 9
                                                      : 11,
                                                  vertical: isCompactLandscape
                                                      ? 4
                                                      : 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: statusColor.withValues(
                                                      alpha: p.isDark
                                                          ? 0.20
                                                          : 0.14),
                                                  borderRadius: AppRadii.r10All,
                                                  border: Border.all(
                                                    color:
                                                        statusColor.withValues(
                                                            alpha: 0.32),
                                                    width: 1.0,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (widget.action!.icon !=
                                                        null) ...[
                                                      Icon(
                                                        widget.action!.icon,
                                                        size: isCompactLandscape
                                                            ? 12
                                                            : 14,
                                                        color: statusColor,
                                                      ),
                                                      const SizedBox(width: 4),
                                                    ],
                                                    Text(
                                                      widget.action!.label,
                                                      style: TextStyle(
                                                        color: statusColor,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize:
                                                            isCompactLandscape
                                                                ? 11.5
                                                                : AppFontSize
                                                                    .bodySmall,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],

                                      // Close Button
                                      const SizedBox(width: 4),
                                      Semantics(
                                        button: true,
                                        label: MaterialLocalizations.of(context)
                                            .closeButtonTooltip,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            HapticFeedback.lightImpact();
                                            dismiss();
                                          },
                                          child: SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: Icon(
                                              Icons.close_rounded,
                                              size:
                                                  isCompactLandscape ? 16 : 18,
                                              color: p.textTertiary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
      },
    );
  }
}
