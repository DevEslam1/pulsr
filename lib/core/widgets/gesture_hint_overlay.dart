// lib/core/widgets/gesture_hint_overlay.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import '../utils/l10n_extensions.dart';

import '../utils/pulsr_haptics.dart';
/// {@category DesignSystem}
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
    this.padding =
        const EdgeInsetsDirectional.only(bottom: 80, start: 16, end: 16),
    this.autoDismissDuration = const Duration(seconds: 7),
  });

  @override
  State<GestureHintOverlay> createState() => _GestureHintOverlayState();
}

class _GestureHintOverlayState extends State<GestureHintOverlay> {
  bool _dismissed = true;
  bool _visible = false;
  Timer? _autoHideTimer;
  Timer? _revealTimer;
  Timer? _finalizeTimer;

  String get _storageKey => 'pulsr_hint_${widget.hintKey}';

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _revealTimer?.cancel();
    _finalizeTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_storageKey) ?? false;
      if (!seen && mounted) {
        setState(() => _dismissed = false);
        // Cancellable timers, never Future.delayed: an unmanaged delay keeps a
        // timer pending after this State is disposed.
        _revealTimer = Timer(const Duration(milliseconds: 500), () {
          if (!mounted || _dismissed) return;
          setState(() => _visible = true);
          _autoHideTimer = Timer(widget.autoDismissDuration, _dismiss);
        });
      }
    } catch (_) {}
  }

  void _dismiss({bool fromUserTap = false}) {
    if (!mounted || _dismissed) return;
    if (fromUserTap) {
      PulsrHaptics.selectionClick();
    }
    _autoHideTimer?.cancel();
    setState(() => _visible = false);
    _finalizeTimer = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      setState(() => _dismissed = true);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_storageKey, true);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final p = context.palette;
    final motionDuration = context.motionMs(260);
    final motionCurve = context.motionCurve(Curves.easeOutCubic);

    return Align(
      alignment: widget.alignment,
      child: Padding(
        padding: widget.padding,
        child: IgnorePointer(
          ignoring: !_visible,
          child: AnimatedSlide(
            offset: _visible ? Offset.zero : const Offset(0, 0.18),
            duration: motionDuration,
            curve: motionCurve,
            child: AnimatedScale(
              scale: _visible ? 1.0 : 0.94,
              duration: motionDuration,
              curve: motionCurve,
              child: AnimatedOpacity(
                opacity: _visible ? 1.0 : 0.0,
                duration: motionDuration,
                curve: motionCurve,
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    onTap: () => _dismiss(fromUserTap: true),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 480),
                      padding: const EdgeInsetsDirectional.only(
                        start: AppSpacing.s10,
                        end: AppSpacing.xs,
                        top: 6,
                        bottom: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(
                              p.isDark ? p.surfaceContainerHigh : p.surface,
                              p.accent,
                              p.isDark ? 0.10 : 0.05,
                            )!
                                .withValues(alpha: 0.96),
                            (p.isDark ? p.surfaceContainerHigh : p.surface)
                                .withValues(alpha: 0.94),
                          ],
                        ),
                        borderRadius: AppRadii.full,
                        border: Border.all(
                          color: p.accent.withValues(alpha: 0.42),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: p.isDark ? 0.45 : 0.14),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: p.accent.withValues(alpha: 0.18),
                            blurRadius: 14,
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: p.accent.withValues(alpha: 0.40),
                                width: 0.8,
                              ),
                            ),
                            child: Icon(
                              widget.icon,
                              color: p.accent,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: TextStyle(
                                fontSize: AppFontSize.label,
                                fontWeight: FontWeight.w700,
                                color: p.textPrimary,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          IconButton(
                            tooltip: context.l10n.close,
                            onPressed: () => _dismiss(fromUserTap: true),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: AppSpacing.minTouchTarget,
                              minHeight: AppSpacing.minTouchTarget,
                            ),
                            icon: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: p.isDark
                                    ? AppColors.specularAt(0.08)
                                    : p.surfaceContainer,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: p.textSecondary,
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
    );
  }
}
