// lib/core/widgets/pulsr_error_boundary.dart
import 'package:flutter/material.dart';
import '../utils/error_logger.dart';
import 'empty_state_widget.dart';

typedef ErrorBoundaryBuilder = Widget Function(
    BuildContext context, Object error, VoidCallback retry);

/// A resilient error boundary that catches rendering/runtime errors in its subtree,
/// logs them via [ErrorLogger], and displays a graceful fallback UI with retry support.
class PulsrErrorBoundary extends StatefulWidget {
  final Widget? child;
  final WidgetBuilder? builder;
  final String? category;
  final String? fallbackTitle;
  final String? fallbackSubtitle;
  final ErrorBoundaryBuilder? errorBuilder;
  final VoidCallback? onRetry;

  const PulsrErrorBoundary({
    super.key,
    this.child,
    this.builder,
    this.category,
    this.fallbackTitle,
    this.fallbackSubtitle,
    this.errorBuilder,
    this.onRetry,
  }) : assert(child != null || builder != null,
            'Either child or builder must be provided');

  @override
  State<PulsrErrorBoundary> createState() => _PulsrErrorBoundaryState();
}

class _PulsrErrorBoundaryState extends State<PulsrErrorBoundary> {
  Object? _error;

  void _retry() {
    setState(() {
      _error = null;
    });
    widget.onRetry?.call();
  }

  void _reportError(Object error, StackTrace? stackTrace) {
    _error = error;
    ErrorLogger.log(
      'Caught by PulsrErrorBoundary',
      error: error,
      stackTrace: stackTrace,
      category: widget.category ?? 'ErrorBoundary',
    );
  }

  Widget _buildFallback(BuildContext context, Object error) {
    if (widget.errorBuilder != null) {
      return widget.errorBuilder!(context, error, _retry);
    }
    return EmptyStateWidget(
      icon: Icons.error_outline_rounded,
      title: widget.fallbackTitle ?? 'Something went wrong',
      subtitle: widget.fallbackSubtitle ??
          'An unexpected error occurred while displaying this content.',
      primaryActionLabel: 'Try Again',
      primaryActionIcon: Icons.refresh_rounded,
      onPrimaryAction: _retry,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildFallback(context, _error!);
    }

    try {
      if (widget.builder != null) {
        return widget.builder!(context);
      }
      return widget.child!;
    } catch (e, st) {
      _reportError(e, st);
      return _buildFallback(context, e);
    }
  }
}
