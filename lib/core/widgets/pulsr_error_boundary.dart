// lib/core/widgets/pulsr_error_boundary.dart
import 'package:flutter/material.dart';
import '../theme/aura_theme.dart';
import '../utils/error_logger.dart';
import 'pulsr_empty_state.dart';

/// {@category DesignSystem}
enum ErrorSeverity {
  info,
  warning,
  critical,
}

typedef ErrorBoundaryBuilder = Widget Function(
    BuildContext context, Object error, VoidCallback retry);

/// A resilient error boundary that catches rendering/runtime errors in its subtree,
/// logs them via [ErrorLogger], and displays a graceful fallback UI with retry support.
///
/// The synchronous `try/catch` inside `build` only covers exceptions thrown
/// directly by [builder]; descendant widget build errors are captured via a
/// scoped `ErrorWidget.builder` override installed while this boundary is mounted.
class PulsrErrorBoundary extends StatefulWidget {
  final Widget? child;
  final WidgetBuilder? builder;
  final String? category;
  final String? fallbackTitle;
  final String? fallbackSubtitle;
  final ErrorBoundaryBuilder? errorBuilder;
  final VoidCallback? onRetry;
  final ErrorSeverity severity;

  const PulsrErrorBoundary({
    super.key,
    this.child,
    this.builder,
    this.category,
    this.fallbackTitle,
    this.fallbackSubtitle,
    this.errorBuilder,
    this.onRetry,
    this.severity = ErrorSeverity.critical,
  }) : assert(child != null || builder != null,
            'Either child or builder must be provided');

  @override
  State<PulsrErrorBoundary> createState() => _PulsrErrorBoundaryState();
}

class _PulsrErrorBoundaryState extends State<PulsrErrorBoundary> {
  static final List<_PulsrErrorBoundaryState> _mountedBoundaries =
      <_PulsrErrorBoundaryState>[];
  static ErrorWidgetBuilder? _savedErrorBuilder;

  Object? _error;
  int _retryKey = 0;

  @override
  void initState() {
    super.initState();
    if (_mountedBoundaries.isEmpty) {
      _savedErrorBuilder = ErrorWidget.builder;
      ErrorWidget.builder = _scopedErrorWidgetBuilder;
    }
    _mountedBoundaries.add(this);
  }

  @override
  void dispose() {
    _mountedBoundaries.remove(this);
    if (_mountedBoundaries.isEmpty && _savedErrorBuilder != null) {
      ErrorWidget.builder = _savedErrorBuilder!;
      _savedErrorBuilder = null;
    }
    super.dispose();
  }

  static Widget _scopedErrorWidgetBuilder(FlutterErrorDetails details) {
    var logged = false;
    return Builder(
      builder: (ctx) {
        final boundary =
            ctx.findAncestorStateOfType<_PulsrErrorBoundaryState>();
        if (boundary != null && boundary.mounted) {
          if (!logged) {
            logged = true;
            ErrorLogger.log(
              'Caught by PulsrErrorBoundary',
              error: details.exception,
              stackTrace: details.stack,
              category: boundary.widget.category ?? 'ErrorBoundary',
            );
          }
          return boundary._buildFallback(ctx, details.exception);
        }
        final previous = _savedErrorBuilder;
        if (previous != null) {
          return previous(details);
        }
        return ErrorWidget(details.exception);
      },
    );
  }

  @override
  void didUpdateWidget(covariant PulsrErrorBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child ||
        oldWidget.builder != widget.builder) {
      _error = null;
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _retryKey++;
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

    final p = context.palette;
    final IconData effectiveIcon;
    final Color effectiveColor;

    switch (widget.severity) {
      case ErrorSeverity.info:
        effectiveIcon = Icons.info_outline_rounded;
        effectiveColor = p.info;
        break;
      case ErrorSeverity.warning:
        effectiveIcon = Icons.warning_amber_rounded;
        effectiveColor = p.warning;
        break;
      case ErrorSeverity.critical:
        effectiveIcon = Icons.error_outline_rounded;
        effectiveColor = p.error;
        break;
    }

    return PulsrEmptyState(
      icon: effectiveIcon,
      iconColor: effectiveColor,
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

    // Synchronous try/catch only covers [widget.builder]; descendant build
    // failures are routed through [_scopedErrorWidgetBuilder].
    try {
      final content =
          widget.builder != null ? widget.builder!(context) : widget.child!;
      return KeyedSubtree(
        key: ValueKey<int>(_retryKey),
        child: content,
      );
    } catch (e, st) {
      _reportError(e, st);
      return _buildFallback(context, e);
    }
  }
}
