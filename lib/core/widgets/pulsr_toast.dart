import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_radii.dart';
import '../theme/aura_theme.dart';
import 'glass_container.dart';

/// Lightweight, floating pill notification HUD styled in Pulsr's glass aesthetic.
/// Provides immediate, non-intrusive feedback for actions like "Added to queue",
/// "Playlist updated", "Timer set", etc.
class PulsrToast {
  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context, {
    required String message,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 2200),
    bool isError = false,
  }) {
    _dismissTimer?.cancel();
    _activeEntry?.remove();
    _activeEntry = null;

    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    // `Overlay.of` throws when `context` has no Overlay ancestor — e.g. the
    // root Navigator's own context, whose Overlay is a *child* of that
    // context, not an ancestor. Prefer a nullable lookup and fall back to
    // the root navigator's overlay state so app-level listeners can pass
    // `rootNavigatorKey.currentContext` safely.
    OverlayState? overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;
    final p = context.palette;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        message: message,
        icon: icon,
        isError: isError,
        palette: p,
        onDismiss: () {
          entry.remove();
          if (_activeEntry == entry) _activeEntry = null;
        },
      ),
    );

    _activeEntry = entry;
    try {
      overlayState.insert(entry);
    } catch (_) {
      _activeEntry = null;
      return;
    }

    _dismissTimer = Timer(duration, () {
      try {
        if (_activeEntry == entry) {
          entry.remove();
          _activeEntry = null;
        }
      } catch (_) {
        _activeEntry = null;
      }
    });
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final IconData? icon;
  final bool isError;
  final PulsrPalette palette;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    this.icon,
    required this.isError,
    required this.palette,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    ));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final accentColor = widget.isError ? p.error : p.accent;

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding:
              const EdgeInsetsDirectional.only(bottom: 96, start: 24, end: 24),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Material(
                color: Colors.transparent,
                child: GlassContainer(
                  blur: 24,
                  opacity: p.isDark ? 0.94 : 0.97,
                  borderRadius: AppRadii.full,
                  color: Color.alphaBlend(
                    accentColor.withValues(alpha: p.isDark ? 0.12 : 0.08),
                    p.surface,
                  ),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          color: accentColor,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          widget.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
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
    );
  }
}
