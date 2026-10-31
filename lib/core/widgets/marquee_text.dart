import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../motion/pulsr_motion.dart';
import '../utils/l10n_extensions.dart';
import 'pulsr_scroll_edge_fade.dart';

/// {@category DesignSystem}
/// A widget that displays text normally when it fits within the parent bounds,
/// and smoothly scrolls it horizontally (marquee) when it overflows.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final Duration pauseDuration;
  final double velocity; // pixels per second
  final double? scrollSpeed; // optional explicit speed
  final double blankSpace;
  final bool pauseOnHover;

  /// When true, a tap pauses/resumes the marquee and assistive technology gets
  /// an equivalent action. Required by WCAG 2.2.2 (Pause, Stop, Hide): a title
  /// that scrolls indefinitely must be stoppable without a mouse.
  final bool allowUserPause;

  /// Explicit text direction override. When null, [MarqueeText] automatically
  /// detects whether the content contains Arabic/RTL glyphs and formats/scrolls
  /// naturally in RTL, or LTR for English/Latin content.
  final TextDirection? textDirection;

  /// When running in test environments, continuous auto-scrolling is disabled
  /// by default so that [WidgetTester.pumpAndSettle] does not time out.
  @visibleForTesting
  static bool enableInTests = false;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.center,
    this.pauseDuration = const Duration(milliseconds: 1400),
    this.velocity = 30.0,
    this.scrollSpeed,
    this.blankSpace = 48.0,
    this.pauseOnHover = true,
    this.allowUserPause = true,
    this.textDirection,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late final ScrollController _scrollController;
  Timer? _scrollTimer;
  bool _isScrolling = false;
  bool _isHovered = false;
  int _scrollGeneration = 0;
  double _currentMaxScroll = 0;
  bool _userPaused = false;

  double get _effectiveVelocity => widget.scrollSpeed ?? widget.velocity;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.textAlign != widget.textAlign ||
        oldWidget.blankSpace != widget.blankSpace ||
        oldWidget.velocity != widget.velocity ||
        oldWidget.scrollSpeed != widget.scrollSpeed ||
        oldWidget.textDirection != widget.textDirection) {
      _stopScrolling();
      _userPaused = false;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  @override
  void dispose() {
    _stopScrolling();
    _scrollController.dispose();
    super.dispose();
  }

  Completer<void>? _unhoverCompleter;

  Future<void> _waitUntilUnhovered() async {
    if (!_isHovered || !mounted || !_isScrolling) return;
    _unhoverCompleter ??= Completer<void>();
    await _unhoverCompleter!.future;
  }

  void _setHovered(bool hovered) {
    if (_isHovered == hovered) return;
    _isHovered = hovered;
    if (!hovered) {
      if (_unhoverCompleter != null && !_unhoverCompleter!.isCompleted) {
        _unhoverCompleter!.complete();
      }
      _unhoverCompleter = null;
    }
  }

  void _stopScrolling() {
    _scrollGeneration++;
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _isScrolling = false;
    if (_unhoverCompleter != null && !_unhoverCompleter!.isCompleted) {
      _unhoverCompleter!.complete();
    }
    _unhoverCompleter = null;
  }

  bool get _isTestEnv =>
      const bool.fromEnvironment('flutter.test') ||
      (WidgetsBinding.instance is! WidgetsFlutterBinding);

  void _startScrolling(double maxScroll) {
    if (_isScrolling ||
        !mounted ||
        maxScroll <= 0 ||
        !context.motionEnabled ||
        _userPaused ||
        (_isTestEnv && !MarqueeText.enableInTests)) {
      return;
    }
    _isScrolling = true;
    final generation = ++_scrollGeneration;
    bool isActive() =>
        mounted &&
        _isScrolling &&
        generation == _scrollGeneration &&
        context.motionEnabled;

    void cycle() {
      if (!isActive() || !_scrollController.hasClients) return;

      _scrollTimer = Timer(widget.pauseDuration, () async {
        if (!isActive() || !_scrollController.hasClients) return;

        // If hovered on desktop/tablet, wait until unhovered event-driven
        await _waitUntilUnhovered();
        if (!isActive() || !_scrollController.hasClients) return;

        final duration = Duration(
          milliseconds: ((maxScroll / _effectiveVelocity) * 1000).toInt(),
        );

        try {
          await _scrollController.animateTo(
            maxScroll,
            duration: duration,
            curve: Curves.linear,
          );

          if (!isActive() || !_scrollController.hasClients) {
            return;
          }

          _scrollTimer = Timer(widget.pauseDuration, () async {
            if (!isActive() || !_scrollController.hasClients) {
              return;
            }

            await _waitUntilUnhovered();
            if (!isActive() || !_scrollController.hasClients) {
              return;
            }

            try {
              await _scrollController.animateTo(
                0.0,
                duration: duration,
                curve: Curves.linear,
              );
              cycle();
            } catch (_) {}
          });
        } catch (_) {}
      });
    }

    cycle();
  }

  /// Toggles the marquee. WCAG 2.2.2: moving content that starts automatically
  /// must be pausable by touch, pointer and assistive technology.
  void _toggleUserPause() {
    if (!widget.allowUserPause || !mounted) return;
    setState(() => _userPaused = !_userPaused);
    HapticFeedback.selectionClick();
    if (_userPaused) {
      _stopScrolling();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  static bool hasRtlGlyphs(String text) {
    return RegExp(r'[\u0590-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]').hasMatch(text);
  }

  TextDirection _resolveDirection(BuildContext context) {
    if (widget.textDirection != null) return widget.textDirection!;
    if (hasRtlGlyphs(widget.text)) return TextDirection.rtl;
    if (RegExp(r'[a-zA-Z]').hasMatch(widget.text)) {
      return TextDirection.ltr;
    }
    return Directionality.of(context);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final motionEnabled = context.motionEnabled;
    final effectiveDirection = _resolveDirection(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: effectiveStyle),
          textDirection: effectiveDirection,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();

        final textWidth = textPainter.width;
        textPainter.dispose();
        final availableWidth = constraints.maxWidth;

        // If text fits, display static text
        if (!motionEnabled ||
            textWidth <= availableWidth ||
            availableWidth <= 0 ||
            !availableWidth.isFinite) {
          _stopScrolling();
          _currentMaxScroll = 0;
          return Directionality(
            textDirection: effectiveDirection,
            child: Tooltip(
              message: widget.text,
              // Respect the incoming width even in the static branch: without
              // this, a long title inside a constrained Row overflows when
              // Reduce Motion swaps the marquee for plain text.
              child: SizedBox(
                width: availableWidth.isFinite ? availableWidth : null,
                child: Text(
                  widget.text,
                  style: effectiveStyle,
                  textAlign: widget.textAlign,
                  textDirection: effectiveDirection,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        }

        // Text overflows -> animate marquee
        final maxScroll = textWidth - availableWidth + widget.blankSpace;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !context.motionEnabled) return;
          if (_isScrolling && (_currentMaxScroll - maxScroll).abs() > 0.5) {
            _stopScrolling();
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0.0);
            }
          }
          _currentMaxScroll = maxScroll;
          if (!_isScrolling) _startScrolling(maxScroll);
        });

        Widget marquee = SizedBox(
          width: availableWidth,
          child: Directionality(
            textDirection: effectiveDirection,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: effectiveDirection,
                children: [
                  Text(
                    widget.text,
                    style: effectiveStyle,
                    textDirection: effectiveDirection,
                    maxLines: 1,
                  ),
                  SizedBox(width: widget.blankSpace),
                ],
              ),
            ),
          ),
        );

        if (widget.pauseOnHover) {
          marquee = MouseRegion(
            onEnter: (_) => _setHovered(true),
            onExit: (_) => _setHovered(false),
            child: marquee,
          );
        }

        if (widget.allowUserPause) {
          final l10n = context.l10n;
          marquee = Semantics(
            hint: _userPaused ? l10n.marqueeResume : l10n.marqueePause,
            onTap: _toggleUserPause,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleUserPause,
              child: marquee,
            ),
          );
        }

        // Fade the clipped edge instead of cutting a glyph in half before the
        // marquee starts. The 1.4 s pause is still enough to read the opening.
        return Directionality(
          textDirection: effectiveDirection,
          child: PulsrScrollEdgeFade(
            extent: 32,
            child: marquee,
          ),
        );
      },
    );
  }
}
