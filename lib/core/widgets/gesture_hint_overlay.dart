// lib/core/widgets/gesture_hint_overlay.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import '../utils/l10n_extensions.dart';

/// A shared, self-dismissing hint overlay/banner that shows once to educate
/// users about gestures (D6: swipe down to dismiss, double-tap, mini player
/// swipe to skip, song tile swipe actions).
///
/// Automatically persists whether the user has seen/dismissed the hint
/// using [hintKey] in SharedPreferences.
class GestureHintOverlay extends StatefulWidget {
  final String hintKey;
  final String message;
  final IconData icon;
  final Alignment alignment;
  final EdgeInsetsGeometry padding;
  final Duration autoDismissDuration;

  const GestureHintOverlay({
    super.key,
    required this.hintKey,
    required this.message,
    this.icon = Icons.touch_app_rounded,
    this.alignment = Alignment.bottomCenter,
    this.padding = const EdgeInsetsDirectional.only(bottom: 80, start: 16, end: 16),
    this.autoDismissDuration = const Duration(seconds: 7),
  });

  @override
  State<GestureHintOverlay> createState() => _GestureHintOverlayState();
}

class _GestureHintOverlayState extends State<GestureHintOverlay> {
  bool _dismissed = true;
  bool _visible = false;
  Timer? _autoHideTimer;

  String get _storageKey => 'pulsr_hint_${widget.hintKey}';

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_storageKey) ?? false;
      if (!seen && mounted) {
        setState(() => _dismissed = false);
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && !_dismissed) {
          setState(() => _visible = true);
          _autoHideTimer = Timer(widget.autoDismissDuration, _dismiss);
        }
      }
    } catch (_) {}
  }

  Future<void> _dismiss() async {
    if (!mounted || _dismissed) return;
    setState(() => _visible = false);
    await Future.delayed(const Duration(milliseconds: 250));
    if (mounted) setState(() => _dismissed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final p = context.palette;

    return Align(
      alignment: widget.alignment,
      child: Padding(
        padding: widget.padding,
        child: IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1.0 : 0.0,
            duration: context.motionMs(260),
            curve: context.motionCurve(Curves.easeOutCubic),
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: _dismiss,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s14,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: (p.isDark ? const Color(0xFF161824) : Colors.white)
                        .withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(AppRadii.r20),
                    border: Border.all(
                      color: p.accent.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: p.accent.withValues(alpha: 0.15),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.xxs),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.icon,
                          color: p.accent,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s6),
                      IconButton(
                        tooltip: context.l10n.close,
                        onPressed: _dismiss,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: p.textTertiary,
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
