part of 'equalizer_sheet.dart';

extension _EqBandSliderColumn on _EqualizerSheetState {
  Widget _buildBandControl({
    required int index,
    required String label,
    required bool isEnabled,
    required Color accentColor,
    required Color trackColor,
    required Color surfaceColor,
    required Color textColor,
    required Color errorColor,
    required PlayerState state,
    required PlayerCubit cubit,
    double? gain,
  }) {
    if (gain != null) {
      return _buildBandControlContent(
        index: index,
        gain: gain,
        label: label,
        isEnabled: isEnabled,
        accentColor: accentColor,
        trackColor: trackColor,
        surfaceColor: surfaceColor,
        textColor: textColor,
        errorColor: errorColor,
        state: state,
        cubit: cubit,
      );
    }
    return BlocSelector<PlayerCubit, PlayerState, double>(
      selector: (s) =>
          index < s.eqPreset.gains.length ? s.eqPreset.gains[index] : 0.0,
      builder: (context, g) => _buildBandControlContent(
        index: index,
        gain: g,
        label: label,
        isEnabled: isEnabled,
        accentColor: accentColor,
        trackColor: trackColor,
        surfaceColor: surfaceColor,
        textColor: textColor,
        errorColor: errorColor,
        state: state,
        cubit: cubit,
      ),
    );
  }

  Widget _buildBandControlContent({
    required int index,
    required double gain,
    required String label,
    required bool isEnabled,
    required Color accentColor,
    required Color trackColor,
    required Color surfaceColor,
    required Color textColor,
    required Color errorColor,
    required PlayerState state,
    required PlayerCubit cubit,
  }) {
    final isMuted = _mutedBands.contains(index);
    final isSoloed = _soloedBands.contains(index);
    return Semantics(
      slider: true,
      label: context.l10n.eqBandLabel(index + 1),
      value: '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB',
      child: RepaintBoundary(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VerticalEqSlider(
              key: ValueKey('eq_band_$index'),
              value: gain,
              label: label,
              isEnabled: isEnabled,
              accentColor: accentColor,
              trackColor: trackColor,
              surfaceColor: surfaceColor,
              textColor: textColor,
              onInteraction: () {
                if (!state.isEqEnabled) {
                  cubit.setEqualizerEnabled(true);
                }
              },
              onChanged: (val) {
                if (!state.isEqEnabled) {
                  cubit.setEqualizerEnabled(true);
                }
                cubit.setBandGain(index, val);
              },
            ),
            const SizedBox(height: AppSpacing.xxs),
            // F-35: fast solo/mute toggles. State is transient (native has no
            // getter), so it is mirrored locally for the current session only.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _bandToggle(
                    label: 'M',
                    tooltip: isMuted
                        ? context.l10n.dspUnmuteBand
                        : context.l10n.dspMuteBand,
                    active: isMuted,
                    activeColor: errorColor,
                    onTap: isEnabled
                        ? () async {
                            final next = !isMuted;
                            final manager = _equalizerManagerOrNull();
                            if (manager != null) {
                              await manager.setBandMute(index, next);
                            }
                            if (!mounted) return;
                            _setStateSafe(() {
                              if (next) {
                                _mutedBands.add(index);
                              } else {
                                _mutedBands.remove(index);
                              }
                            });
                          }
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  _bandToggle(
                    label: 'S',
                    tooltip: isSoloed
                        ? context.l10n.dspUnsoloBand
                        : context.l10n.dspSoloBand,
                    active: isSoloed,
                    activeColor: accentColor,
                    onTap: isEnabled
                        ? () async {
                            final next = !isSoloed;
                            final manager = _equalizerManagerOrNull();
                            if (manager != null) {
                              await manager.setBandSolo(index, next);
                            }
                            if (!mounted) return;
                            _setStateSafe(() {
                              if (next) {
                                _soloedBands.add(index);
                              } else {
                                _soloedBands.remove(index);
                              }
                            });
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bandToggle({
    required String label,
    required String tooltip,
    required bool active,
    required Color activeColor,
    required VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.r4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 3),
            child: Container(
              width: 15,
              height: 15,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? activeColor.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.r4),
                border: Border.all(
                  color: active ? activeColor : context.palette.hairline,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppFontSize.micro,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  color: active ? activeColor : context.palette.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerticalEqSlider extends StatefulWidget {
  final double value;
  final bool isEnabled;
  final String label;
  final Color accentColor;
  final Color trackColor;
  final Color surfaceColor;
  final Color textColor;
  final ValueChanged<double> onChanged;
  final VoidCallback? onInteraction;

  static const double min = -15.0;
  static const double max = 15.0;

  const _VerticalEqSlider({
    super.key,
    required this.value,
    required this.isEnabled,
    required this.label,
    required this.accentColor,
    required this.trackColor,
    required this.surfaceColor,
    required this.textColor,
    required this.onChanged,
    this.onInteraction,
  });

  @override
  State<_VerticalEqSlider> createState() => _VerticalEqSliderState();
}

class _VerticalEqSliderState extends State<_VerticalEqSlider> {
  bool _isDragging = false;
  double? _dragGain;

  void _handlePointer(double localY, double totalHeight,
      {bool notifyParent = false}) {
    widget.onInteraction?.call();
    const topMargin = 12.0;
    const bottomMargin = 12.0;
    final trackHeight = totalHeight - topMargin - bottomMargin;
    if (trackHeight <= 0) return;
    final clampedY = (localY - topMargin).clamp(0.0, trackHeight);
    final fraction = 1.0 - (clampedY / trackHeight);
    final newGain = _VerticalEqSlider.min +
        fraction * (_VerticalEqSlider.max - _VerticalEqSlider.min);
    final roundedGain = double.parse(newGain.toStringAsFixed(1));
    setState(() {
      _dragGain = roundedGain;
    });
    if (notifyParent) {
      widget.onChanged(roundedGain);
    }
  }

  @override
  void didUpdateWidget(covariant _VerticalEqSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // H-06: Preserve _dragGain while actively dragging so parent rebuilds
    // cannot stomp on the in-flight gesture with stale props.
    if (!_isDragging) {
      _dragGain = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gain = (_isDragging && _dragGain != null ? _dragGain! : widget.value)
        .clamp(_VerticalEqSlider.min, _VerticalEqSlider.max);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Value Pill
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
            decoration: BoxDecoration(
              color: (gain.abs() > 0.1 ? widget.accentColor : widget.trackColor)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadii.r6),
            ),
            child: Text(
              '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
              style: TextStyle(
                fontSize: AppFontSize.tiny,
                color: gain.abs() > 0.1 ? widget.accentColor : widget.textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),

        // Vertical Slider Track
        SizedBox(
          height: 140,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              const topMargin = 12.0;
              const bottomMargin = 12.0;
              final trackHeight = height - topMargin - bottomMargin;
              final fraction = (gain - _VerticalEqSlider.min) /
                  (_VerticalEqSlider.max - _VerticalEqSlider.min);
              final thumbY = topMargin + (1.0 - fraction) * trackHeight;
              final centerY = topMargin + trackHeight / 2;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Tap-to-set: a deliberate tap on the track jumps the band to
                // that gain, matching the horizontal DSP sliders.
                onTapDown: (details) {
                  _handlePointer(details.localPosition.dy, height,
                      notifyParent: true);
                },
                onVerticalDragStart: (details) {
                  setState(() => _isDragging = true);
                  _handlePointer(details.localPosition.dy, height,
                      notifyParent: true);
                },
                onVerticalDragUpdate: (details) {
                  _handlePointer(details.localPosition.dy, height,
                      notifyParent: true);
                },
                onVerticalDragEnd: (_) {
                  final finalGain = _dragGain ?? widget.value;
                  widget.onChanged(finalGain);
                  setState(() {
                    _isDragging = false;
                    _dragGain = null;
                  });
                },
                onVerticalDragCancel: () {
                  setState(() {
                    _isDragging = false;
                    _dragGain = null;
                  });
                },
                child: CustomPaint(
                  size: Size(constraints.maxWidth, height),
                  painter: _VerticalSliderPainter(
                    fraction: fraction,
                    thumbY: thumbY,
                    centerY: centerY,
                    topMargin: topMargin,
                    bottomMargin: bottomMargin,
                    isDragging: _isDragging,
                    isEnabled: widget.isEnabled,
                    accentColor: widget.accentColor,
                    trackColor: widget.trackColor,
                    surfaceColor: widget.surfaceColor,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xs),

        // Frequency Label + Modification Indicator Dot
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                  color: widget.textColor,
                ),
              ),
              if (gain.abs() > 0.1)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(top: AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: widget.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerticalSliderPainter extends CustomPainter {
  final double fraction;
  final double thumbY;
  final double centerY;
  final double topMargin;
  final double bottomMargin;
  final bool isDragging;
  final bool isEnabled;
  final Color accentColor;
  final Color trackColor;
  final Color surfaceColor;

  _VerticalSliderPainter({
    required this.fraction,
    required this.thumbY,
    required this.centerY,
    required this.topMargin,
    required this.bottomMargin,
    required this.isDragging,
    required this.isEnabled,
    required this.accentColor,
    required this.trackColor,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final trackTop = topMargin;
    final trackBottom = size.height - bottomMargin;

    // Background track (Pill)
    final bgPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.35)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    canvas.drawLine(
      Offset(centerX, trackTop),
      Offset(centerX, trackBottom),
      bgPaint,
    );

    // Center 0 dB notch tick
    final notchPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.8)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0;

    canvas.drawLine(
      Offset(centerX - 6, centerY),
      Offset(centerX + 6, centerY),
      notchPaint,
    );

    // Active fill from center (0dB) to thumbY
    final activePaint = Paint()
      ..color = isEnabled ? accentColor : trackColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX, thumbY),
      activePaint,
    );

    // Thumb Glow / Halo when dragging
    if (isDragging && isEnabled) {
      final haloPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, thumbY), 16.0, haloPaint);
    }

    // Thumb Outer Shadow
    final shadowPaint = Paint()
      ..color = AppColors.scrimAt(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawCircle(
        Offset(centerX, thumbY + 1), isDragging ? 9.0 : 8.0, shadowPaint);

    // Thumb Main Circle
    final thumbPaint = Paint()
      ..color = isEnabled ? accentColor : trackColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(centerX, thumbY), isDragging ? 9.0 : 8.0, thumbPaint);

    // Thumb Inner Core
    final corePaint = Paint()
      ..color = isEnabled ? Colors.white : surfaceColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(centerX, thumbY), isDragging ? 3.5 : 3.0, corePaint);
  }

  @override
  bool shouldRepaint(covariant _VerticalSliderPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.thumbY != thumbY ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.isEnabled != isEnabled ||
        oldDelegate.accentColor != accentColor;
  }
}
