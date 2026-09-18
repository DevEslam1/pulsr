import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../constants/app_typography.dart';
import '../di/injection.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';
import 'pulsr_dock_tracker.dart';
import 'pulsr_modal_tracker.dart';

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
    if (_activeWidgetState != null && _activeWidgetState!.mounted) {
      _activeWidgetState!.dismiss();
    } else {
      _activeEntry?.remove();
      _activeEntry = null;
    }
  }

  /// Displays a floating SnackBar positioned above the mini player.
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 2200),
    bool isError = false,
    bool isSuccess = false,
    String? actionLabel,
    VoidCallback? onActionPressed,
    VoidCallback? onDismiss,
    double? bottomOffset,
  }) {
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
      } else {
        HapticFeedback.lightImpact();
      }
    } catch (_) {}

    // `Overlay.of` throws when `context` has no Overlay ancestor — e.g. the
    // root Navigator's own context, whose Overlay is a *child* of that
    // context, not an ancestor. Prefer a nullable lookup and fall back to
    // the root navigator's overlay state.
    OverlayState? overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;
    final p = context.palette;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        key: UniqueKey(),
        message: message,
        title: title,
        icon: icon,
        isError: isError,
        isSuccess: isSuccess,
        actionLabel: actionLabel,
        onActionPressed: onActionPressed,
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
  final String? actionLabel;
  final VoidCallback? onActionPressed;
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
    this.actionLabel,
    this.onActionPressed,
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
      duration: const Duration(milliseconds: 260),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.40),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();
    _startAutoDismissTimer();
  }

  void _startAutoDismissTimer() {
    _autoDismissTimer = Timer(widget.duration, () {
      if (mounted) dismiss();
    });
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

    final media = MediaQuery.maybeOf(context);
    final bottomSafeArea = media?.padding.bottom ?? 0.0;
    final keyboardInset = media?.viewInsets.bottom ?? 0.0;

    // 1. If software keyboard is active, position above it
    if (keyboardInset > 0) {
      return keyboardInset + 14.0;
    }

    // 2. If a dialog or bottom sheet modal is open, bottom dock is slid away
    if (PulsrModalTracker.isModalOpen.value) {
      return bottomSafeArea + 16.0;
    }

    // 3. If Now Playing full-screen route is active, bottom dock is not visible
    if (PulsrDockTracker.isNowPlayingOpen.value) {
      return bottomSafeArea + 16.0;
    }

    // 4. Use live height reported by PulsrDockTracker
    final liveDockHeight = PulsrDockTracker.dockHeight.value;
    if (liveDockHeight > 0) {
      return liveDockHeight + bottomSafeArea + 12.0;
    }

    // 5. Fallback inspection if dock has not reported yet
    bool hasSong = false;
    try {
      if (getIt.isRegistered<PlayerCubit>()) {
        hasSong = getIt<PlayerCubit>().state.currentSong != null;
      }
    } catch (_) {}

    final isTablet = Adaptive.isTablet(context);
    final fallbackHeight =
        hasSong ? (isTablet ? 166.0 : 158.0) : (isTablet ? 82.0 : 74.0);
    return fallbackHeight + bottomSafeArea + 12.0;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final statusColor = widget.isError
        ? p.error
        : (widget.isSuccess ? p.success : p.accent);

    final effectiveIcon = widget.icon ??
        (widget.isError
            ? Icons.error_outline_rounded
            : (widget.isSuccess
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded));

    final isTablet = Adaptive.isTablet(context);
    final double maxDockWidth = isTablet ? 640.0 : 540.0;
    final snackbarRadius = BorderRadius.circular(isTablet ? 26.0 : 20.0);

    return AnimatedBuilder(
      animation: Listenable.merge([
        PulsrDockTracker.changeNotifier,
        PulsrModalTracker.isModalOpen,
      ]),
      builder: (context, _) {
        final bottomOffset = _calculateBottomOffset(context);

        return Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedPadding(
            duration: context.motionMs(260),
            curve: Curves.easeOutCubic,
            padding: EdgeInsetsDirectional.only(
              bottom: bottomOffset,
              start: isTablet ? 24.0 : 14.0,
              end: isTablet ? 24.0 : 14.0,
            ),
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
                              color: Colors.black.withValues(
                                  alpha: p.isDark ? 0.40 : 0.12),
                              blurRadius: 24,
                              spreadRadius: 0,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: statusColor.withValues(
                                  alpha: p.isDark ? 0.14 : 0.08),
                              blurRadius: 18,
                              spreadRadius: -2,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: snackbarRadius,
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: snackbarRadius,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    p.surface.withValues(
                                        alpha: p.isDark ? 0.82 : 0.90),
                                    p.surfaceContainer.withValues(
                                        alpha: p.isDark ? 0.76 : 0.86),
                                  ],
                                ),
                                border: Border.all(
                                  color: widget.isError
                                      ? p.error.withValues(alpha: 0.45)
                                      : (widget.isSuccess
                                          ? p.success.withValues(alpha: 0.45)
                                          : (p.isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.14)
                                              : Colors.black
                                                  .withValues(alpha: 0.08))),
                                  width: 1.2,
                                ),
                              ),
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                14,
                                11,
                                12,
                                11,
                              ),
                              child: Row(
                                children: [
                                  // Leading Status Badge
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(
                                          alpha: p.isDark ? 0.18 : 0.12),
                                      borderRadius: BorderRadius.circular(11),
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
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Text Content
                                  Expanded(
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
                                              fontSize: AppFontSize.bodySmall,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
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
                                            fontSize: AppFontSize.bodySmall,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Optional Action Button
                                  if (widget.actionLabel != null) ...[
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        widget.onActionPressed?.call();
                                        dismiss();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(
                                              alpha: p.isDark ? 0.20 : 0.14),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: statusColor.withValues(
                                                alpha: 0.32),
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Text(
                                          widget.actionLabel!,
                                          style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],

                                  // Close Button
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      dismiss();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: p.textTertiary,
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
