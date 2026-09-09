import 'dart:async';
import 'package:flutter/material.dart';

/// A widget that displays text normally when it fits within the parent bounds,
/// and smoothly scrolls it horizontally (marquee) when it overflows.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final Duration pauseDuration;
  final double velocity; // pixels per second
  final double blankSpace;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.center,
    this.pauseDuration = const Duration(seconds: 2),
    this.velocity = 30.0,
    this.blankSpace = 48.0,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late final ScrollController _scrollController;
  Timer? _scrollTimer;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _stopScrolling();
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

  void _stopScrolling() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _isScrolling = false;
  }

  void _startScrolling(double maxScroll) {
    if (_isScrolling || !mounted || maxScroll <= 0) return;
    _isScrolling = true;

    void cycle() {
      if (!mounted || !_isScrolling || !_scrollController.hasClients) return;

      _scrollTimer = Timer(widget.pauseDuration, () async {
        if (!mounted || !_isScrolling || !_scrollController.hasClients) return;

        final duration = Duration(
          milliseconds: ((maxScroll / widget.velocity) * 1000).toInt(),
        );

        try {
          await _scrollController.animateTo(
            maxScroll,
            duration: duration,
            curve: Curves.linear,
          );

          if (!mounted || !_isScrolling || !_scrollController.hasClients) return;

          _scrollTimer = Timer(widget.pauseDuration, () async {
            if (!mounted || !_isScrolling || !_scrollController.hasClients) return;

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

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = widget.style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: effectiveStyle),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();

        final textWidth = textPainter.width;
        final availableWidth = constraints.maxWidth;

        // If text fits, display static text
        if (textWidth <= availableWidth || availableWidth <= 0) {
          _stopScrolling();
          return Text(
            widget.text,
            style: effectiveStyle,
            textAlign: widget.textAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        // Text overflows -> animate marquee
        final maxScroll = textWidth - availableWidth + widget.blankSpace;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isScrolling) {
            _startScrolling(maxScroll);
          }
        });

        return SizedBox(
          width: availableWidth,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.text,
                  style: effectiveStyle,
                  maxLines: 1,
                ),
                SizedBox(width: widget.blankSpace),
              ],
            ),
          ),
        );
      },
    );
  }
}
