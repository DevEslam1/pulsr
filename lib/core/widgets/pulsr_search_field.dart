// lib/core/widgets/pulsr_search_field.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/pulsr_motion.dart';
import '../responsive/pulsr_layout_metrics.dart';
import '../theme/aura_theme.dart';
import '../utils/l10n_extensions.dart';

/// {@category DesignSystem}
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
  late FocusNode _focusNode;
  Timer? _debounceTimer;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _isFocused = false;
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
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _isFocused = _focusNode.hasFocus;
    _currentQuery = _controller.text;
    _controller.addListener(_onControllerChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted && _isFocused != _focusNode.hasFocus) {
      setState(() => _isFocused = _focusNode.hasFocus);
    }
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
    } else if (_ownsController &&
        oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue ?? '';
    }

    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      if (_ownsFocusNode) {
        _focusNode.dispose();
        _ownsFocusNode = false;
      }
      if (widget.focusNode != null) {
        _focusNode = widget.focusNode!;
      } else {
        _focusNode = FocusNode();
        _ownsFocusNode = true;
      }
      _isFocused = _focusNode.hasFocus;
      _focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    if (_ownsFocusNode) {
      _focusNode.dispose();
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
    final active = _isFocused || hasText;
    final fieldHeight =
        widget.height ?? PulsrLayoutMetrics.fieldHeight(context);

    Widget field = AnimatedContainer(
      duration: context.motionMs(180),
      curve: Curves.easeOutCubic,
      height: fieldHeight,
      decoration: BoxDecoration(
        color: _isFocused ? p.surfaceContainerHigh : p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: widget.showBorder
            ? Border.all(
                color: _isFocused
                    ? p.accent
                    : (hasText ? p.accent.withValues(alpha: 0.45) : p.hairline),
                width: _isFocused ? 1.5 : 1.0,
              )
            : null,
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: p.accent.withValues(alpha: p.isDark ? 0.16 : 0.10),
                  blurRadius: 12,
                  spreadRadius: -2,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Center(
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          textAlignVertical: TextAlignVertical.center,
          onChanged: _handleChanged,
          onSubmitted: (value) {
            _debounceTimer?.cancel();
            widget.onChanged?.call(value);
            widget.onSubmitted?.call(value);
          },
          cursorColor: p.accent,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: AppFontSize.body,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hintText,
            hintStyle: TextStyle(
              color: p.textTertiary,
              fontSize: AppFontSize.bodySmall,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: active ? p.accent : p.textTertiary,
              size: 20,
            ),
            suffixIcon: AnimatedSwitcher(
              duration: context.motionMs(150),
              child: hasText
                  ? IconButton(
                      key: const ValueKey('clear_btn'),
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
                      icon: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: p.surfaceContainerHigh,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: p.textSecondary,
                          size: 14,
                        ),
                      ),
                      tooltip: context.l10n.clear,
                      onPressed: _handleClear,
                    )
                  : const SizedBox.shrink(key: ValueKey('empty_btn')),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.xs,
            ),
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
