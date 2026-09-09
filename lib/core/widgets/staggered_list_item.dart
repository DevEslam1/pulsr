import 'package:flutter/material.dart';

/// Wraps a list item with a staggered cascading entrance animation (smooth fade
/// and subtle vertical rise) inspired by Meloplay's staggered list transitions.
class StaggeredListItem extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration itemDelay;
  final Duration animDuration;
  final double slideOffset;

  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,
    this.itemDelay = const Duration(milliseconds: 30),
    this.animDuration = const Duration(milliseconds: 320),
    this.slideOffset = 16.0,
  });

  @override
  State<StaggeredListItem> createState() => _StaggeredListItemState();
}

class _StaggeredListItemState extends State<StaggeredListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animDuration,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0.0, widget.slideOffset / 100),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    // Stagger animation up to the first 15 items for high performance
    final clampedIndex = widget.index.clamp(0, 14);
    final delay = widget.itemDelay * clampedIndex;

    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}
