// lib/core/widgets/throttled_slider.dart
import 'dart:async';
import 'package:flutter/material.dart';

/// A [Slider] wrapper that provides local smooth preview while throttling
/// continuous [onChanged] invocations with a 60ms debounce window (matching
/// the preamp coalescing schedule), committing the final value immediately
/// on gesture end ([onChangeEnd]).
class ThrottledSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final ValueChanged<double>? onPreviewChanged;
  final Duration debounceDuration;

  const ThrottledSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.onChanged,
    this.onChangeEnd,
    this.onPreviewChanged,
    this.debounceDuration = const Duration(milliseconds: 60),
  });

  @override
  State<ThrottledSlider> createState() => _ThrottledSliderState();
}

class _ThrottledSliderState extends State<ThrottledSlider> {
  double? _previewValue;
  Timer? _debounceTimer;

  @override
  void didUpdateWidget(ThrottledSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_debounceTimer == null) {
      _previewValue = null;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _handleChanged(double val) {
    setState(() {
      _previewValue = val;
    });
    widget.onPreviewChanged?.call(val);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceDuration, () {
      _debounceTimer = null;
      widget.onChanged?.call(val);
    });
  }

  void _handleChangeEnd(double val) {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    setState(() {
      _previewValue = null;
    });
    widget.onChanged?.call(val);
    widget.onChangeEnd?.call(val);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveValue =
        (_previewValue ?? widget.value).clamp(widget.min, widget.max);
    return Slider(
      value: effectiveValue,
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      onChanged: widget.onChanged != null ? _handleChanged : null,
      onChangeEnd: widget.onChanged != null ? _handleChangeEnd : null,
    );
  }
}
