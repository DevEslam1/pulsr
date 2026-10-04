// lib/core/widgets/pulsr_search_field.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../responsive/pulsr_layout_metrics.dart';
import '../theme/aura_theme.dart';
import '../utils/l10n_extensions.dart';

/// {@category DesignSystem}
/// Standard, responsive search input field used across Settings, Library,
/// Favorites, Recents, and Genre views.
///
/// Automatically uses [PulsrLayoutMetrics.fieldHeight] scaled by text zoom,
/// supports debounce, clear action, autofocus, custom hints, and styling.
class PulsrSearchField extends StatefulWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final Duration debounceDuration;
  final bool autofocus;
  final FocusNode? focusNode;
  final double? height;
  final EdgeInsetsGeometry? margin;
  final bool showBorder;

  const PulsrSearchField({
    super.key,
    this.controller,
    this.initialValue,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.debounceDuration = const Duration(milliseconds: 300),
    this.autofocus = false,
    this.focusNode,
    this.height,
    this.margin,
    this.showBorder = true,
  });

  @override
  State<PulsrSearchField> createState() => _PulsrSearchFieldState();
}

class _PulsrSearchFieldState extends State<PulsrSearchField> {
  late TextEditingController _controller;
  Timer? _debounceTimer;
  bool _ownsController = false;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController(text: widget.initialValue ?? '');
      _ownsController = true;
    }
    _currentQuery = _controller.text;
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (_currentQuery != _controller.text) {
      if (mounted) {
        setState(() {
          _currentQuery = _controller.text;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant PulsrSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      if (_ownsController) {
        _controller.dispose();
        _ownsController = false;
      }
      if (widget.controller != null) {
        _controller = widget.controller!;
      } else {
        _controller = TextEditingController(text: widget.initialValue ?? '');
        _ownsController = true;
      }
      _currentQuery = _controller.text;
      _controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleChanged(String value) {
    if (widget.onChanged == null) return;
    if (value.isEmpty) {
      _debounceTimer?.cancel();
      widget.onChanged!(value);
      return;
    }
    if (widget.debounceDuration == Duration.zero) {
      widget.onChanged!(value);
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceDuration, () {
      if (mounted) {
        widget.onChanged!(value);
      }
    });
  }

  void _handleClear() {
    _debounceTimer?.cancel();
    _controller.clear();
    widget.onClear?.call();
    widget.onChanged?.call('');
    if (mounted) {
      setState(() {
        _currentQuery = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasText = _currentQuery.isNotEmpty;
    final fieldHeight =
        widget.height ?? PulsrLayoutMetrics.fieldHeight(context);

    Widget field = Container(
      height: fieldHeight,
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: widget.showBorder
            ? Border.all(
                color: hasText ? p.accent.withValues(alpha: 0.55) : p.hairline,
                width: hasText ? 1.5 : 1.0,
              )
            : null,
      ),
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onChanged: _handleChanged,
        onSubmitted: widget.onSubmitted,
        style: TextStyle(
          color: p.textPrimary,
          fontSize: AppFontSize.body,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(
            color: p.textTertiary,
            fontSize: AppFontSize.bodySmall,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: hasText ? p.accent : p.textTertiary,
            size: 20,
          ),
          suffixIcon: hasText
              ? IconButton(
                  constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget),
                  icon: Icon(
                    Icons.clear_rounded,
                    color: p.textSecondary,
                    size: 18,
                  ),
                  tooltip: context.l10n.clear,
                  onPressed: _handleClear,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
        ),
      ),
    );

    if (widget.margin != null) {
      field = Padding(padding: widget.margin!, child: field);
    }

    return field;
  }
}
